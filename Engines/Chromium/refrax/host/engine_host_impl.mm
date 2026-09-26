// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/engine_host_impl.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/uuid.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "content/public/browser/browsing_data_remover.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "ui/shell_dialogs/selected_file_info.h"
#include "refrax/host/content_blocking.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/download_delegate.h"
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

// Deletes everything `profile` stored, then runs its callback and deletes itself.
class ProfileWipe : public content::BrowsingDataRemover::Observer {
 public:
  static void Start(Profile* profile, base::OnceClosure done) {
    content::BrowsingDataRemover* remover = profile->GetBrowsingDataRemover();
    auto* wipe = new ProfileWipe(remover, std::move(done));
    // The remover notifies only observers in its list.
    remover->AddObserver(wipe);
    remover->RemoveAndReply(base::Time(), base::Time::Max(),
                            chrome_browsing_data_remover::ALL_DATA_TYPES,
                            chrome_browsing_data_remover::ALL_ORIGIN_TYPES, wipe);
  }

  // content::BrowsingDataRemover::Observer:
  void OnBrowsingDataRemoverDone(uint64_t failed_data_types) override {
    if (failed_data_types) {
      LOG(ERROR) << "Removing a profile's data left types " << failed_data_types;
    }
    remover_->RemoveObserver(this);
    std::move(done_).Run();
    delete this;
  }

 private:
  ProfileWipe(content::BrowsingDataRemover* remover, base::OnceClosure done)
      : remover_(remover), done_(std::move(done)) {}
  ~ProfileWipe() override = default;

  raw_ptr<content::BrowsingDataRemover> remover_;
  base::OnceClosure done_;
};

}  // namespace

EngineHostImpl::EngineHostImpl(mojo::PendingReceiver<mojom::EngineHost> receiver,
                               base::OnceClosure on_disconnect)
    : receiver_(this, std::move(receiver)) {
  receiver_.set_disconnect_handler(std::move(on_disconnect));
  DownloadDelegate::SetAsker(base::BindRepeating(
      [](base::WeakPtr<EngineHostImpl> engine, content::WebContents* web_contents,
         download::DownloadItem* download, const base::FilePath& suggested_path,
         DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
        HostPage* page = engine ? engine->PageFor(web_contents) : nullptr;
        if (!page) {
          std::move(callback).Run(DownloadConfirmationResult::CANCELED,
                                  ui::SelectedFileInfo());
          return;
        }
        page->AskForDownload(download, suggested_path, std::move(callback));
      },
      weak_factory_.GetWeakPtr()));
}

EngineHostImpl::~EngineHostImpl() {
  Notifications::Get().SetDelegate(nullptr);
  DownloadDelegate::SetAsker({});
  // Pages detach their views through `application_`, so they go first.
  pages_.clear();
}

void EngineHostImpl::Start(
    const std::string& configuration,
    mojo::PendingAssociatedRemote<remote_cocoa::mojom::Application> application,
    mojo::PendingAssociatedRemote<mojom::EngineClient> client,
    StartCallback callback) {
  if (application_.is_bound()) {
    std::move(callback).Run("The engine is already started.");
    return;
  }
  // The configuration's storage directory is this process's --user-data-dir, chosen by the
  // client at launch; its languages are the profiles' accept-languages (applied per profile).
  application_.Bind(std::move(application));
  client_.Bind(std::move(client));
  Notifications::Get().SetDelegate(this);
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

HostPage* EngineHostImpl::PageFor(content::WebContents* web_contents) const {
  for (const auto& page : pages_) {
    if (page->web_contents() == web_contents) {
      return page.get();
    }
  }
  return nullptr;
}

void EngineHostImpl::DestroyPage(HostPage* page) {
  std::erase_if(pages_, [page](const auto& p) { return p.get() == page; });
}

void EngineHostImpl::ApplyPolicy(const std::string& update) {
  auto message = contract::ParseMessage(update);
  if (!message) {
    receiver_.ReportBadMessage("ApplyPolicy: malformed update");
    return;
  }
  auto& [category, fields] = *message;
  if (category == "scripts") {
    const base::ListValue* scripts = fields.FindList("scripts");
    if (!scripts) {
      receiver_.ReportBadMessage("ApplyPolicy: scripts without a list");
      return;
    }
    scripts_ = scripts->Clone();
    for (const auto& page : pages_) {
      page->ApplyScripts(scripts_);
    }
    return;
  }
  if (category == "contentBlocking") {
    const base::DictValue* policy = fields.FindDict("policy");
    if (!policy) {
      receiver_.ReportBadMessage("ApplyPolicy: contentBlocking without a policy");
      return;
    }
    ContentBlocking::Get().Apply(*policy);
    return;
  }
  if (category == "notifications") {
    const base::DictValue* policy = fields.FindDict("policy");
    if (!policy) {
      receiver_.ReportBadMessage("ApplyPolicy: notifications without a policy");
      return;
    }
    Notifications::Get().ApplyPolicy(*policy);
    return;
  }
  // Extensions and site settings are not declared in the engine's capabilities yet, so
  // Refrax does not send them.
  VLOG(1) << "Policy category not handled: " << category;
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
  if (kind == "ephemeral") {
    auto it = space_id ? ephemeral_spaces_.find(*space_id) : ephemeral_spaces_.end();
    if (it != ephemeral_spaces_.end()) {
      Profile* base_profile = ProfileManager::GetLastUsedProfile();
      if (base_profile && base_profile->HasOffTheRecordProfile(it->second)) {
        base_profile->DestroyOffTheRecordProfile(
            base_profile->GetOffTheRecordProfile(it->second,
                                                 /*create_if_needed=*/false));
      }
      ephemeral_spaces_.erase(it);
    }
    std::move(callback).Run();
    return;
  }
  // A persistent profile is emptied and kept: a space whose data was cleared goes on opening
  // pages in it. Never Chrome's profile deletion here: it marks the directory dead for the
  // host's lifetime, and the space's next page never loads.
  base::DictValue spec;
  spec.Set(kind, fields.Clone());
  ResolveProfile(spec, base::BindOnce(
                           [](RemoveProfileCallback callback, Profile* profile) {
                             if (!profile) {
                               std::move(callback).Run();
                               return;
                             }
                             ProfileWipe::Start(profile, std::move(callback));
                           },
                           std::move(callback)));
}

void EngineHostImpl::PerformCommand(const std::string& command) {
  auto message = contract::ParseMessage(command);
  if (!message) {
    receiver_.ReportBadMessage("PerformCommand: malformed command");
    return;
  }
  auto& [name, fields] = *message;
  const std::string* id = fields.FindString("id");
  if (name == "notificationClicked" && id) {
    Notifications::Get().Click(*id);
  } else if (name == "notificationClosed" && id) {
    Notifications::Get().Dismiss(*id);
  }
}

HostPage* EngineHostImpl::PageShowing(Profile* profile, const GURL& document_url) {
  HostPage* frame_match = nullptr;
  for (const auto& page : pages_) {
    content::WebContents* contents = page->web_contents();
    if (contents->GetBrowserContext() != profile) {
      continue;
    }
    if (contents->GetPrimaryMainFrame()->GetLastCommittedURL() == document_url) {
      return page.get();
    }
    if (!frame_match) {
      contents->ForEachRenderFrameHost([&](content::RenderFrameHost* frame) {
        if (frame->GetLastCommittedURL() == document_url) {
          frame_match = page.get();
        }
      });
    }
  }
  return frame_match;
}

std::optional<base::DictValue> EngineHostImpl::ProfileSpec(Profile* profile) {
  if (profile == ProfileManager::GetLastUsedProfile()) {
    return base::DictValue().Set("shared", base::DictValue());
  }
  for (const auto& [space_id, keep_alive] : isolated_spaces_) {
    if (profile->GetPath() == IsolatedProfilePath(space_id)) {
      return base::DictValue().Set("isolated", base::DictValue().Set("id", space_id));
    }
  }
  return std::nullopt;
}

void EngineHostImpl::EmitEngineEvent(std::string event) {
  if (client_.is_bound()) {
    client_->OnEvent(event);
  }
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
