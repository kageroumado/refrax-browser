// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/engine_host_impl.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/logging.h"
#include "base/uuid.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "content/public/browser/web_contents.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/host_page.h"

namespace refrax {

namespace {

// A space id from the contract: a UUID, which also makes it safe as a directory name.
std::optional<std::string> SpaceID(const base::DictValue& fields) {
  const std::string* id = fields.FindString("id");
  if (!id) {
    return std::nullopt;
  }
  base::Uuid uuid = base::Uuid::ParseCaseInsensitive(*id);
  if (!uuid.is_valid()) {
    return std::nullopt;
  }
  return uuid.AsLowercaseString();
}

base::FilePath IsolatedProfilePath(const std::string& space_id) {
  // ProfileManager only creates profiles directly inside the user data directory.
  return g_browser_process->profile_manager()->user_data_dir().AppendASCII(
      "space-" + space_id);
}

}  // namespace

EngineHostImpl::EngineHostImpl(mojo::PendingReceiver<mojom::EngineHost> receiver,
                               base::OnceClosure on_disconnect)
    : receiver_(this, std::move(receiver)) {
  receiver_.set_disconnect_handler(std::move(on_disconnect));
}

EngineHostImpl::~EngineHostImpl() {
  // Pages detach their views through `application_`, so they go first.
  pages_.clear();
}

void EngineHostImpl::Start(
    const std::string& configuration,
    mojo::PendingAssociatedRemote<remote_cocoa::mojom::Application> application,
    StartCallback callback) {
  if (application_.is_bound()) {
    std::move(callback).Run("The engine is already started.");
    return;
  }
  // The configuration's storage directory is this process's --user-data-dir, chosen by the
  // client at launch; its languages are the profiles' accept-languages (applied per profile).
  application_.Bind(std::move(application));
  std::move(callback).Run(std::nullopt);
}

void EngineHostImpl::CreatePage(
    const std::string& spec,
    mojo::PendingAssociatedReceiver<mojom::Page> page,
    mojo::PendingAssociatedRemote<mojom::PageClient> client,
    CreatePageCallback callback) {
  std::optional<base::Value> parsed =
      base::JSONReader::Read(spec, base::JSON_PARSE_RFC);
  const base::DictValue* fields = parsed ? parsed->GetIfDict() : nullptr;
  const std::string* id = fields ? fields->FindString("id") : nullptr;
  const base::DictValue* profile = fields ? fields->FindDict("profile") : nullptr;
  if (!application_.is_bound() || !id || !profile) {
    receiver_.ReportBadMessage("CreatePage: malformed spec");
    return;
  }
  const std::string* initial_url = fields->FindString("initialURL");
  ResolveProfile(
      *profile,
      base::BindOnce(&EngineHostImpl::CreatePageInProfile,
                     weak_factory_.GetWeakPtr(), *id,
                     initial_url ? GURL(*initial_url) : GURL(), std::move(page),
                     std::move(client), std::move(callback)));
}

void EngineHostImpl::CreatePageInProfile(
    std::string page_id,
    GURL initial_url,
    mojo::PendingAssociatedReceiver<mojom::Page> page,
    mojo::PendingAssociatedRemote<mojom::PageClient> client,
    CreatePageCallback callback,
    Profile* profile) {
  if (!profile) {
    // The client sees the page as closed; Refrax reports the failure on its side.
    std::move(callback).Run(0);
    return;
  }
  auto host_page = std::make_unique<HostPage>(
      this, profile, std::move(page_id), std::move(page), std::move(client));
  const uint64_t container_id = host_page->container_ns_view_id();
  pages_.push_back(std::move(host_page));
  std::move(callback).Run(container_id);
  if (initial_url.is_valid()) {
    pages_.back()->Load(initial_url);
  }
}

void EngineHostImpl::DestroyPage(HostPage* page) {
  std::erase_if(pages_, [page](const auto& p) { return p.get() == page; });
}

void EngineHostImpl::ApplyPolicy(const std::string& update) {
  // Content blocking, scripts, extensions and site settings arrive in milestone 4.
  VLOG(1) << "Policy update ignored: " << update.substr(0, 64);
}

void EngineHostImpl::RemoveProfile(const std::string& profile,
                                   RemoveProfileCallback callback) {
  auto message = contract::ParseMessage(profile);
  if (!message) {
    receiver_.ReportBadMessage("RemoveProfile: malformed spec");
    return;
  }
  auto& [kind, fields] = *message;
  std::optional<std::string> space_id = SpaceID(fields);
  if (kind == "ephemeral" && space_id) {
    auto it = ephemeral_spaces_.find(*space_id);
    if (it != ephemeral_spaces_.end()) {
      Profile* base_profile = ProfileManager::GetLastUsedProfile();
      if (base_profile && base_profile->HasOffTheRecordProfile(it->second)) {
        base_profile->DestroyOffTheRecordProfile(
            base_profile->GetOffTheRecordProfile(it->second,
                                                 /*create_if_needed=*/false));
      }
      ephemeral_spaces_.erase(it);
    }
  } else if (kind == "isolated" && space_id) {
    isolated_spaces_.erase(*space_id);
    g_browser_process->profile_manager()
        ->GetDeleteProfileHelper()
        .MaybeScheduleProfileForDeletion(
            IsolatedProfilePath(*space_id), base::DoNothing(),
            ProfileMetrics::DELETE_PROFILE_SETTINGS);
  }
  std::move(callback).Run();
}

void EngineHostImpl::ResolveProfile(const base::DictValue& spec,
                                    base::OnceCallback<void(Profile*)> callback) {
  if (spec.size() != 1) {
    std::move(callback).Run(nullptr);
    return;
  }
  const auto& [kind, value] = *spec.begin();
  Profile* shared = ProfileManager::GetLastUsedProfile();
  if (kind == "shared") {
    std::move(callback).Run(shared);
    return;
  }
  std::optional<std::string> space_id =
      value.is_dict() ? SpaceID(value.GetDict()) : std::nullopt;
  if (!space_id) {
    std::move(callback).Run(nullptr);
    return;
  }
  if (kind == "ephemeral") {
    auto [it, inserted] = ephemeral_spaces_.try_emplace(
        *space_id, Profile::OTRProfileID::CreateUnique("refrax-space"));
    std::move(callback).Run(
        shared->GetOffTheRecordProfile(it->second, /*create_if_needed=*/true));
    return;
  }
  if (kind == "isolated") {
    g_browser_process->profile_manager()->CreateProfileAsync(
        IsolatedProfilePath(*space_id),
        base::BindOnce(&EngineHostImpl::OnIsolatedProfileLoaded,
                       weak_factory_.GetWeakPtr(), *space_id,
                       std::move(callback)));
    return;
  }
  std::move(callback).Run(nullptr);
}

void EngineHostImpl::OnIsolatedProfileLoaded(
    const std::string& space_id,
    base::OnceCallback<void(Profile*)> callback,
    Profile* profile) {
  if (profile && !isolated_spaces_.contains(space_id)) {
    isolated_spaces_[space_id] = std::make_unique<ScopedProfileKeepAlive>(
        profile, ProfileKeepAliveOrigin::kRemoteDebugging);
  }
  std::move(callback).Run(profile);
}

}  // namespace refrax
