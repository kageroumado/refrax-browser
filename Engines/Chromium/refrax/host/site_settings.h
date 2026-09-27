// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SITE_SETTINGS_H_
#define REFRAX_HOST_SITE_SETTINGS_H_

#include <string>
#include <utility>
#include <vector>

#include "base/no_destructor.h"
#include "base/values.h"

class Profile;

namespace refrax {

// Refrax's per-site settings (CONTRACT.md §4.5 `siteSettings`), written into the Chrome profiles
// pages use: JavaScript as content settings, autoplay with sound as Chrome's autoplay allowlist,
// and popups allowed everywhere, since Refrax decides each one through `openURL`. Sites with
// content blocking off go to ContentBlocking. One per host process, on the UI thread.
//
// A profile holds the policy as of the last write to it: Apply rewrites the profiles of open
// pages, and a page made in another profile rewrites that one first.
class SiteSettings {
 public:
  static SiteSettings& Get();

  SiteSettings(const SiteSettings&) = delete;
  SiteSettings& operator=(const SiteSettings&) = delete;

  // Replaces the policy with the contract's SiteSettingsPolicy. Returns false for one without
  // its fields.
  bool Apply(const base::DictValue& policy);

  // Writes the policy into `profile`, replacing whatever was there.
  void ApplyTo(Profile* profile) const;

 private:
  friend class base::NoDestructor<SiteSettings>;

  SiteSettings();
  ~SiteSettings();

  bool javascript_enabled_ = true;
  // (content settings pattern, whether JavaScript runs) for each site that differs.
  std::vector<std::pair<std::string, bool>> javascript_rules_;
  // Content settings patterns of the sites that may autoplay with sound.
  std::vector<std::string> autoplay_patterns_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_SITE_SETTINGS_H_
