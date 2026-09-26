// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_NOTIFICATIONS_H_
#define REFRAX_HOST_NOTIFICATIONS_H_

#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile_manager_observer.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_pattern.h"
#include "url/gurl.h"

class Profile;

namespace blink {
struct PlatformNotificationData;
}

namespace refrax {

class HostPage;
class NotificationPermissionProvider;

// Web notifications for Refrax (CONTRACT.md §4.1, §4.5, §4.6). Refrax decides and delivers;
// Chromium only reports and dispatches.
//
// Permission: each regular profile's content settings get a provider holding the contract's
// `notifications` policy, ahead of Chrome's stored settings, which swallows every notification
// decision Chrome would store (and prompt embargoes). So `Notification.permission`, permission
// queries and the prompt all follow Refrax's store, and a change reaches open pages at once.
//
// Delivery: each regular profile's PlatformNotificationService becomes one that reports to
// Refrax instead of Chrome's notification bridge: a page's notification as that page's event,
// a service worker's (or one no page can be named for) as an engine event. Refrax's click and
// dismissal come back as commands and fire the page's or worker's events.
class Notifications : public ProfileManagerObserver {
 public:
  // The engine connection notifications travel over.
  class Delegate {
   public:
    virtual ~Delegate() = default;
    // The page in `profile` whose document is `document_url`, or nullptr.
    virtual HostPage* PageShowing(Profile* profile, const GURL& document_url) = 0;
    // The contract's EngineProfileSpec for `profile`, or nullopt for one Refrax didn't ask for.
    virtual std::optional<base::DictValue> ProfileSpec(Profile* profile) = 0;
    // Sends the contract's EngineEvent.
    virtual void EmitEngineEvent(std::string event) = 0;
  };

  static Notifications& Get();

  Notifications(const Notifications&) = delete;
  Notifications& operator=(const Notifications&) = delete;

  // Null when no client is connected; notifications shown meanwhile go nowhere.
  void SetDelegate(Delegate* delegate);

  // Watches profiles as ProfileManager creates them. Called before the first profile exists.
  void Install();

  // The contract's `notifications` policy: {"granted": [...], "denied": [...], "asksByDefault"}.
  void ApplyPolicy(const base::DictValue& policy);

  // ProfileManagerObserver: Refrax's notification service goes on each regular profile as it is
  // created (content keeps the service it finds when the profile's storage starts), and the
  // permission provider once the profile is initialized. Off-the-record profiles are left
  // alone: Chrome denies notifications there and gives them no notification service.
  void OnProfileCreationStarted(Profile* profile) override;
  void OnProfileAdded(Profile* profile) override;
  void OnProfileManagerDestroying() override;

  // The contract's notificationClicked / notificationClosed commands.
  void Click(const std::string& id);
  void Dismiss(const std::string& id);

  // From a profile's notification service.
  void Show(Profile* profile,
            const std::string& notification_id,
            const GURL& origin,
            const GURL& document_url,
            const blink::PlatformNotificationData& data,
            bool persistent);
  void Close(Profile* profile, const std::string& notification_id);
  // Chromium's ids of the notifications `profile` has showing; every origin for an empty one.
  std::set<std::string> Displayed(Profile* profile, const GURL& origin) const;

  // The provider's rules, and its registration while its settings map lives.
  const std::vector<std::pair<ContentSettingsPattern, ContentSetting>>& rules() const {
    return rules_;
  }
  void RemoveProvider(NotificationPermissionProvider* provider);

 private:
  friend class base::NoDestructor<Notifications>;

  // A notification Refrax was told about, by contract id.
  struct Shown {
    base::FilePath profile_path;
    // Chromium's id: unique within its profile.
    std::string notification_id;
    GURL origin;
    bool persistent;
    // The page it was reported on; unset when it was an engine event.
    std::optional<base::WeakPtr<HostPage>> page;
  };

  Notifications();
  ~Notifications() override;

  // The contract id: Chromium's id qualified by its profile, unique across the engine.
  static std::string ContractID(Profile* profile, const std::string& notification_id);

  raw_ptr<Delegate> delegate_ = nullptr;
  std::vector<std::pair<ContentSettingsPattern, ContentSetting>> rules_;
  std::set<raw_ptr<NotificationPermissionProvider>> providers_;
  std::map<std::string, Shown> shown_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_NOTIFICATIONS_H_
