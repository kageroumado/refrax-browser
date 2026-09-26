// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/notifications.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/notifications/platform_notification_service_factory.h"
#include "chrome/browser/notifications/platform_notification_service_impl.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "components/content_settings/core/browser/content_settings_observable_provider.h"
#include "components/content_settings/core/browser/content_settings_origin_value_map.h"
#include "components/content_settings/core/browser/content_settings_rule.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings_metadata.h"
#include "components/content_settings/core/common/content_settings_utils.h"
#include "content/public/browser/notification_event_dispatcher.h"
#include "content/public/browser/platform_notification_context.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/common/persistent_notification_status.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/host_page.h"
#include "third_party/blink/public/common/notifications/platform_notification_data.h"
#include "url/origin.h"

namespace refrax {

// The contract's `notifications` policy as content settings. It sits ahead of Chrome's stored
// settings (kNotificationAndroidProvider's slot, unused on macOS) and accepts every notification
// setting and prompt embargo Chrome writes, keeping none: Refrax sends its policy before it
// answers a prompt, so nothing Chrome would remember is missing from it.
class NotificationPermissionProvider : public content_settings::ObservableProvider {
 public:
  NotificationPermissionProvider() { SetRules(Notifications::Get().rules()); }
  NotificationPermissionProvider(const NotificationPermissionProvider&) = delete;
  NotificationPermissionProvider& operator=(const NotificationPermissionProvider&) = delete;
  ~NotificationPermissionProvider() override = default;

  void SetRules(const std::vector<std::pair<ContentSettingsPattern, ContentSetting>>& rules) {
    {
      base::AutoLock lock(value_map_.GetLock());
      value_map_.clear();
      for (const auto& [pattern, setting] : rules) {
        value_map_.SetValue(pattern, ContentSettingsPattern::Wildcard(),
                            ContentSettingsType::NOTIFICATIONS,
                            content_settings::ContentSettingToValue(setting),
                            content_settings::RuleMetaData());
      }
    }
    NotifyObservers(ContentSettingsPattern::Wildcard(), ContentSettingsPattern::Wildcard(),
                    ContentSettingsType::NOTIFICATIONS);
  }

  // content_settings::ProviderInterface:
  std::unique_ptr<content_settings::RuleIterator> GetRuleIterator(
      ContentSettingsType content_type,
      bool off_the_record) const override {
    if (off_the_record) {
      return nullptr;
    }
    return value_map_.GetRuleIterator(content_type);
  }

  std::unique_ptr<content_settings::Rule> GetRule(const GURL& primary_url,
                                                  const GURL& secondary_url,
                                                  ContentSettingsType content_type,
                                                  bool off_the_record) const override {
    if (off_the_record) {
      return nullptr;
    }
    base::AutoLock lock(value_map_.GetLock());
    return value_map_.GetRule(primary_url, secondary_url, content_type);
  }

  bool SetWebsiteSetting(const ContentSettingsPattern& primary_pattern,
                         const ContentSettingsPattern& secondary_pattern,
                         ContentSettingsType content_type,
                         const base::Value& value,
                         const content_settings::ContentSettingConstraints& constraints) override {
    return content_type == ContentSettingsType::NOTIFICATIONS ||
           content_type == ContentSettingsType::PERMISSION_AUTOBLOCKER_DATA;
  }

  void ClearAllContentSettingsRules(ContentSettingsType content_type) override {}

  void ShutdownOnUIThread() override {
    RemoveAllObservers();
    Notifications::Get().RemoveProvider(this);
  }

 private:
  content_settings::OriginValueMap value_map_;
};

namespace {

// Marks a profile whose settings have Refrax's provider.
const char kPreparedKey[] = "refrax-notifications";

// Chrome's notification service with delivery replaced: Refrax shows the notifications. Chrome's
// id counters and trigger scheduling stay.
class NotificationService : public PlatformNotificationServiceImpl {
 public:
  explicit NotificationService(Profile* profile)
      : PlatformNotificationServiceImpl(profile), profile_(profile) {}

  // content::PlatformNotificationService:
  void DisplayNotification(
      const std::string& notification_id,
      const GURL& origin,
      const GURL& document_url,
      const blink::PlatformNotificationData& notification_data,
      const blink::NotificationResources& notification_resources) override {
    Notifications::Get().Show(profile_, notification_id, origin, document_url,
                              notification_data, /*persistent=*/false);
    content::NotificationEventDispatcher::GetInstance()->DispatchNonPersistentShowEvent(
        notification_id);
  }

  void DisplayPersistentNotification(
      const std::string& notification_id,
      const GURL& service_worker_scope,
      const GURL& origin,
      const blink::PlatformNotificationData& notification_data,
      const blink::NotificationResources& notification_resources) override {
    Notifications::Get().Show(profile_, notification_id, origin, GURL(), notification_data,
                              /*persistent=*/true);
  }

  void CloseNotification(const std::string& notification_id) override {
    Notifications::Get().Close(profile_, notification_id);
  }

  void ClosePersistentNotification(const std::string& notification_id) override {
    Notifications::Get().Close(profile_, notification_id);
  }

  void GetDisplayedNotifications(DisplayedNotificationsCallback callback) override {
    Reply(std::move(callback), Notifications::Get().Displayed(profile_, GURL()));
  }

  void GetDisplayedNotificationsForOrigin(const GURL& origin,
                                          DisplayedNotificationsCallback callback) override {
    Reply(std::move(callback), Notifications::Get().Displayed(profile_, origin));
  }

 private:
  // Posted, as content expects. Unsynchronized: Notification Center can drop a notification
  // without Refrax hearing of it, so the set is no reason to delete a worker's stored ones.
  static void Reply(DisplayedNotificationsCallback callback, std::set<std::string> ids) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(callback), std::move(ids),
                                  /*supports_synchronization=*/false));
  }

  raw_ptr<Profile> profile_;
};

// A pattern for exactly the origin a contract origin names, or nullopt for an invalid or
// opaque one.
std::optional<ContentSettingsPattern> OriginPattern(const std::string& serialized) {
  GURL url(serialized);
  if (!url.is_valid() || url::Origin::Create(url).opaque()) {
    return std::nullopt;
  }
  return ContentSettingsPattern::FromURLNoWildcard(url);
}

}  // namespace

// static
Notifications& Notifications::Get() {
  static base::NoDestructor<Notifications> instance;
  return *instance;
}

Notifications::Notifications() = default;
Notifications::~Notifications() = default;

void Notifications::SetDelegate(Delegate* delegate) {
  delegate_ = delegate;
}

void Notifications::ApplyPolicy(const base::DictValue& policy) {
  rules_.clear();
  auto add = [this](const base::ListValue* origins, ContentSetting setting) {
    if (!origins) {
      return;
    }
    for (const base::Value& origin : *origins) {
      if (!origin.is_string()) {
        continue;
      }
      if (std::optional<ContentSettingsPattern> pattern = OriginPattern(origin.GetString())) {
        rules_.emplace_back(*pattern, setting);
      }
    }
  };
  add(policy.FindList("granted"), CONTENT_SETTING_ALLOW);
  add(policy.FindList("denied"), CONTENT_SETTING_BLOCK);
  if (!policy.FindBool("asksByDefault").value_or(true)) {
    rules_.emplace_back(ContentSettingsPattern::Wildcard(), CONTENT_SETTING_BLOCK);
  }
  for (NotificationPermissionProvider* provider : providers_) {
    provider->SetRules(rules_);
  }
}

void Notifications::Install() {
  g_browser_process->profile_manager()->AddObserver(this);
}

void Notifications::OnProfileCreationStarted(Profile* profile) {
  if (profile->IsOffTheRecord()) {
    return;
  }
  PlatformNotificationServiceFactory::GetInstance()->SetTestingFactory(
      profile, base::BindRepeating([](content::BrowserContext* context)
                                       -> std::unique_ptr<KeyedService> {
        return std::make_unique<NotificationService>(Profile::FromBrowserContext(context));
      }));
}

void Notifications::OnProfileAdded(Profile* profile) {
  if (profile->IsOffTheRecord() || profile->GetUserData(kPreparedKey)) {
    return;
  }
  profile->SetUserData(kPreparedKey, std::make_unique<base::SupportsUserData::Data>());

  HostContentSettingsMap* settings = HostContentSettingsMapFactory::GetForProfile(profile);
  // Chrome's own stored notification decisions and prompt embargoes: none may outrank or
  // outlast Refrax's policy.
  settings->ClearSettingsForOneType(ContentSettingsType::NOTIFICATIONS);
  settings->ClearSettingsForOneType(ContentSettingsType::PERMISSION_AUTOBLOCKER_DATA);
  auto provider = std::make_unique<NotificationPermissionProvider>();
  providers_.insert(provider.get());
  settings->RegisterProvider(HostContentSettingsMap::ProviderType::kNotificationAndroidProvider,
                             std::move(provider));
}

void Notifications::OnProfileManagerDestroying() {
  g_browser_process->profile_manager()->RemoveObserver(this);
}

void Notifications::RemoveProvider(NotificationPermissionProvider* provider) {
  providers_.erase(provider);
}

// static
std::string Notifications::ContractID(Profile* profile, const std::string& notification_id) {
  return profile->GetBaseName().AsUTF8Unsafe() + "/" + notification_id;
}

void Notifications::Show(Profile* profile,
                         const std::string& notification_id,
                         const GURL& origin,
                         const GURL& document_url,
                         const blink::PlatformNotificationData& data,
                         bool persistent) {
  if (!delegate_) {
    return;
  }
  const std::string id = ContractID(profile, notification_id);
  base::DictValue notification;
  notification.Set("id", id);
  notification.Set("origin", url::Origin::Create(origin).Serialize());
  notification.Set("title", base::UTF16ToUTF8(data.title));
  notification.Set("body", base::UTF16ToUTF8(data.body));
  if (!data.tag.empty()) {
    notification.Set("tag", data.tag);
  }
  if (data.icon.is_valid()) {
    notification.Set("iconURL", contract::URLValue(data.icon));
  }
  notification.Set("isSilent", data.silent);

  Shown shown{profile->GetPath(), notification_id, origin, persistent, std::nullopt};
  HostPage* page = persistent || document_url.is_empty()
                       ? nullptr
                       : delegate_->PageShowing(profile, document_url);
  if (page) {
    shown.page = page->GetWeakPtr();
    page->Emit("notificationShown",
               base::DictValue().Set("notification", std::move(notification)));
  } else {
    std::optional<base::DictValue> spec = delegate_->ProfileSpec(profile);
    if (!spec) {
      return;
    }
    delegate_->EmitEngineEvent(contract::Message(
        "notificationShown", base::DictValue()
                                 .Set("profile", std::move(*spec))
                                 .Set("notification", std::move(notification))));
  }
  shown_.insert_or_assign(id, std::move(shown));
}

void Notifications::Close(Profile* profile, const std::string& notification_id) {
  auto it = shown_.find(ContractID(profile, notification_id));
  if (it == shown_.end()) {
    return;
  }
  base::DictValue fields = base::DictValue().Set("id", it->first);
  if (!it->second.page) {
    if (delegate_) {
      delegate_->EmitEngineEvent(contract::Message("notificationClosed", std::move(fields)));
    }
  } else if (HostPage* page = it->second.page->get()) {
    page->Emit("notificationClosed", std::move(fields));
  }
  shown_.erase(it);
}

std::set<std::string> Notifications::Displayed(Profile* profile, const GURL& origin) const {
  std::set<std::string> ids;
  for (const auto& [id, shown] : shown_) {
    if (shown.profile_path == profile->GetPath() &&
        (origin.is_empty() || url::IsSameOriginWith(shown.origin, origin))) {
      ids.insert(shown.notification_id);
    }
  }
  return ids;
}

void Notifications::Click(const std::string& id) {
  auto it = shown_.find(id);
  if (it == shown_.end()) {
    return;
  }
  Shown shown = std::move(it->second);
  shown_.erase(it);
  content::NotificationEventDispatcher* dispatcher =
      content::NotificationEventDispatcher::GetInstance();
  if (!shown.persistent) {
    dispatcher->DispatchNonPersistentClickEvent(shown.notification_id, base::DoNothing());
    return;
  }
  Profile* profile =
      g_browser_process->profile_manager()->GetProfileByPath(shown.profile_path);
  if (!profile) {
    return;
  }
  // Notification Center forgets a clicked notification, so the worker's
  // getNotifications() does too, once its notificationclick has run.
  dispatcher->DispatchNotificationClickEvent(
      profile, shown.notification_id, shown.origin, /*action_index=*/std::nullopt,
      /*reply=*/std::nullopt,
      base::BindOnce(
          [](base::WeakPtr<Profile> profile, std::string notification_id, GURL origin,
             content::PersistentNotificationStatus) {
            if (!profile) {
              return;
            }
            profile->GetDefaultStoragePartition()
                ->GetPlatformNotificationContext()
                ->DeleteNotificationData(notification_id, origin,
                                         /*close_notification=*/false, base::DoNothing());
          },
          profile->GetWeakPtr(), shown.notification_id, shown.origin));
}

void Notifications::Dismiss(const std::string& id) {
  auto it = shown_.find(id);
  if (it == shown_.end()) {
    return;
  }
  Shown shown = std::move(it->second);
  shown_.erase(it);
  content::NotificationEventDispatcher* dispatcher =
      content::NotificationEventDispatcher::GetInstance();
  if (!shown.persistent) {
    dispatcher->DispatchNonPersistentCloseEvent(shown.notification_id, base::DoNothing());
    return;
  }
  Profile* profile =
      g_browser_process->profile_manager()->GetProfileByPath(shown.profile_path);
  if (profile) {
    // Content deletes the stored notification once its notificationclose has run.
    dispatcher->DispatchNotificationCloseEvent(profile, shown.notification_id, shown.origin,
                                               /*by_user=*/true, base::DoNothing());
  }
}

}  // namespace refrax
