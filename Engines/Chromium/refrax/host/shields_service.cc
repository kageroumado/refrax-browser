// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/shields_service.h"

#include <utility>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/task/thread_pool.h"
#include "base/types/expected.h"
#include "content/public/browser/browser_thread.h"
#include "crypto/hash.h"
#include "net/base/filename_util.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/url_matching.h"
#include "url/gurl.h"

namespace refrax {

namespace {

// Larger files are refused: a debug DAT of every default list is tens of megabytes.
constexpr int64_t kMaxEngineBytes = 512 * 1024 * 1024;
constexpr int64_t kMaxResourcesBytes = 64 * 1024 * 1024;

// adblock-rust asks the embedder for registrable domains: Chromium's registry, private
// registries included, as Brave's resolver does.
void ResolveDomain(const char* host, size_t host_len, size_t* start, size_t* end) {
  const std::string_view name(host, host_len);
  const std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      name, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  if (domain.empty() || !base::EndsWith(name, domain)) {
    *start = 0;
    *end = host_len;
    return;
  }
  *start = host_len - domain.size();
  *end = host_len;
}

// A contract path: a file: URL, or an absolute path.
std::optional<base::FilePath> PolicyPath(const std::string& value) {
  GURL url(value);
  base::FilePath path;
  if (url.SchemeIsFile()) {
    if (!net::FileURLToFilePath(url, &path)) {
      return std::nullopt;
    }
  } else {
    path = base::FilePath(value);
  }
  return path.IsAbsolute() ? std::optional(path) : std::nullopt;
}

struct FileSpec {
  base::FilePath path;
  std::string sha256;
};

// {path, sha256} from the policy's `engine` or `resources` object.
std::optional<FileSpec> ParseFileSpec(const base::DictValue* fields) {
  const std::string* path = fields ? fields->FindString("path") : nullptr;
  const std::string* sha256 = fields ? fields->FindString("sha256") : nullptr;
  if (!path || !sha256) {
    return std::nullopt;
  }
  std::optional<base::FilePath> file = PolicyPath(*path);
  if (!file) {
    return std::nullopt;
  }
  return FileSpec{*file, base::ToLowerASCII(*sha256)};
}

// The file's contents when its SHA-256 is `spec.sha256`; otherwise a reason.
base::expected<std::string, std::string> ReadVerified(const FileSpec& spec, int64_t limit) {
  std::optional<int64_t> size = base::GetFileSize(spec.path);
  if (!size) {
    return base::unexpected("cannot read " + spec.path.value());
  }
  if (*size > limit) {
    return base::unexpected(spec.path.value() + " is too large");
  }
  std::string contents;
  if (!base::ReadFileToString(spec.path, &contents)) {
    return base::unexpected("cannot read " + spec.path.value());
  }
  if (base::HexEncodeLower(crypto::hash::Sha256(contents)) != spec.sha256) {
    return base::unexpected("the SHA-256 of " + spec.path.value() + " does not match");
  }
  return base::ok(std::move(contents));
}

struct LoadResult {
  ShieldsEngine* engine = nullptr;
  std::optional<std::string> failure;
};

// Runs on a thread that may block: reads both files, checks their hashes, deserializes the
// engine and gives it the resources.
LoadResult Load(FileSpec engine_spec, std::optional<FileSpec> resources_spec) {
  base::expected<std::string, std::string> dat = ReadVerified(engine_spec, kMaxEngineBytes);
  if (!dat.has_value()) {
    return {nullptr, dat.error()};
  }
  std::string resources;
  if (resources_spec) {
    base::expected<std::string, std::string> json =
        ReadVerified(*resources_spec, kMaxResourcesBytes);
    if (!json.has_value()) {
      return {nullptr, json.error()};
    }
    resources = std::move(json.value());
  }
  ShieldsEngine* engine = shields_engine_deserialize(
      reinterpret_cast<const uint8_t*>(dat->data()), dat->size());
  if (!engine) {
    return {nullptr, "the engine file is corrupt"};
  }
  if (!resources.empty() &&
      shields_engine_use_resources(engine, reinterpret_cast<const uint8_t*>(resources.data()),
                                   resources.size()) != SHIELDS_OK) {
    shields_engine_free(engine);
    return {nullptr, "the resources file is malformed"};
  }
  return {engine, std::nullopt};
}

std::string StatusEvent(std::string_view status,
                        const std::string* sha256,
                        const std::string* reason) {
  base::DictValue fields;
  fields.Set("status", status);
  if (sha256) {
    fields.Set("sha256", *sha256);
  }
  if (reason) {
    fields.Set("reason", *reason);
  }
  return contract::Message("contentBlockingStatus", std::move(fields));
}

}  // namespace

ShieldsEngineRef::ShieldsEngineRef(ShieldsEngine* engine,
                                   std::string sha256,
                                   std::vector<std::string> list_ids)
    : engine_(engine), sha256_(std::move(sha256)), list_ids_(std::move(list_ids)) {}

ShieldsEngineRef::~ShieldsEngineRef() {
  shields_engine_free(engine_.ExtractAsDangling());
}

std::optional<std::string> ShieldsEngineRef::ListID(int32_t source_index) const {
  if (source_index < 0 || static_cast<size_t>(source_index) >= list_ids_.size() ||
      list_ids_[source_index].empty()) {
    return std::nullopt;
  }
  return list_ids_[source_index];
}

// static
ShieldsService& ShieldsService::Get() {
  static base::NoDestructor<ShieldsService> instance;
  return *instance;
}

ShieldsService::ShieldsService() {
  CHECK_EQ(shields_abi_version(), static_cast<uint32_t>(SHIELDS_ABI_VERSION));
  CHECK_EQ(shields_set_domain_resolver(&ResolveDomain), SHIELDS_OK);
}

ShieldsService::~ShieldsService() = default;

bool ShieldsService::Apply(const base::DictValue& policy,
                           base::OnceCallback<void(std::string event)> status) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const uint64_t generation = ++generation_;
  enabled_ = policy.FindBool("isEnabled").value_or(true);

  const std::string* mode = policy.FindString("mode");
  mode_ = mode && *mode == "aggressive" ? Mode::kAggressive : Mode::kStandard;

  allowlisted_hosts_.clear();
  if (const base::ListValue* hosts = policy.FindList("allowlistedHosts")) {
    for (const base::Value& host : *hosts) {
      if (host.is_string()) {
        allowlisted_hosts_.insert(base::ToLowerASCII(host.GetString()));
      }
    }
  }

  if (!enabled_) {
    engine_ = nullptr;
    std::move(status).Run(StatusEvent("unfiltered", nullptr, nullptr));
    return true;
  }

  const base::DictValue* engine = policy.FindDict("engine");
  std::optional<FileSpec> engine_spec = ParseFileSpec(engine);
  if (!engine_spec) {
    return false;
  }
  std::optional<FileSpec> resources_spec;
  if (const base::DictValue* resources = policy.FindDict("resources")) {
    resources_spec = ParseFileSpec(resources);
    if (!resources_spec) {
      return false;
    }
  }

  // Lists by sourceIndex, for the request log.
  std::vector<std::string> list_ids;
  if (const base::ListValue* lists = policy.FindList("lists")) {
    for (const base::Value& list : *lists) {
      const base::DictValue* fields = list.GetIfDict();
      const std::string* id = fields ? fields->FindString("id") : nullptr;
      std::optional<int> index = fields ? fields->FindInt("sourceIndex") : std::nullopt;
      if (!id || !index || *index < 0 || *index > 4096) {
        continue;
      }
      if (list_ids.size() <= static_cast<size_t>(*index)) {
        list_ids.resize(*index + 1);
      }
      list_ids[*index] = *id;
    }
  }

  const std::string* format = engine->FindString("format");
  if (!format || *format != shields_engine_format()) {
    const std::string reason = "the engine's format is " + (format ? *format : "missing") +
                               "; this engine reads " + shields_engine_format();
    std::move(status).Run(StatusEvent("unfiltered", nullptr, &reason));
    return true;
  }

  // The engine already loaded: only the hosts or the mode changed. A DAT's lists are part of
  // its hash, so the list ids are the same too.
  if (engine_ && engine_->sha256() == engine_spec->sha256) {
    std::move(status).Run(StatusEvent("applied", &engine_spec->sha256, nullptr));
    return true;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&Load, *engine_spec, resources_spec),
      base::BindOnce(
          [](base::WeakPtr<ShieldsService> self, uint64_t generation,
             base::OnceCallback<void(std::string)> status,
             std::vector<std::string> list_ids, std::string sha256, LoadResult result) {
            if (!self) {
              if (result.engine) {
                shields_engine_free(result.engine);
              }
              return;
            }
            self->OnLoaded(generation, std::move(status), std::move(list_ids),
                           std::move(result.failure), result.engine, std::move(sha256));
          },
          weak_factory_.GetWeakPtr(), generation, std::move(status), std::move(list_ids),
          engine_spec->sha256));
  return true;
}

void ShieldsService::OnLoaded(uint64_t generation,
                              base::OnceCallback<void(std::string event)> status,
                              std::vector<std::string> list_ids,
                              std::optional<std::string> failure,
                              ShieldsEngine* engine,
                              std::string sha256) {
  if (generation != generation_) {
    // A newer policy replaced this one while it loaded; that one reports its own status.
    if (engine) {
      shields_engine_free(engine);
    }
    return;
  }
  if (!engine) {
    LOG(ERROR) << "Content blocking: " << failure.value_or("the engine did not load");
    engine_ = nullptr;
    std::move(status).Run(StatusEvent("unfiltered", nullptr, &*failure));
    return;
  }
  engine_ = base::MakeRefCounted<ShieldsEngineRef>(engine, sha256, std::move(list_ids));
  std::move(status).Run(StatusEvent("applied", &sha256, nullptr));
}

void ShieldsService::SetSiteExceptions(std::set<std::string> hosts) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  site_exceptions_ = std::move(hosts);
}

bool ShieldsService::IsActiveFor(const GURL& top_url) const {
  if (!enabled_ || !engine_ || !engine_->engine() || !top_url.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  return !url_matching::IsAllowlistedHost(allowlisted_hosts_, top_url.host()) &&
         !url_matching::IsAllowlistedHost(site_exceptions_, top_url.host());
}

scoped_refptr<ShieldsEngineRef> ShieldsService::engine() const {
  return enabled_ && engine_ && engine_->engine() ? engine_ : nullptr;
}

}  // namespace refrax
