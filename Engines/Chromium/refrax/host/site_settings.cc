// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/site_settings.h"

#include <optional>
#include <set>

#include "base/strings/string_util.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_pattern.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_thread.h"
#include "refrax/host/content_blocking.h"

namespace refrax {

namespace {

// The pattern covering a rule's host and its subdomains, or an empty string for a host no
// pattern can name.
std::string SitePattern(const std::string& host) {
  std::string pattern = "[*.]" + base::ToLowerASCII(host);
  return ContentSettingsPattern::FromString(pattern).IsValid() ? pattern : std::string();
}

ContentSetting Setting(bool allow) {
  return allow ? CONTENT_SETTING_ALLOW : CONTENT_SETTING_BLOCK;
}

}  // namespace

// static
SiteSettings& SiteSettings::Get() {
  static base::NoDestructor<SiteSettings> instance;
  return *instance;
}

SiteSettings::SiteSettings() = default;
SiteSettings::~SiteSettings() = default;

bool SiteSettings::Apply(const base::DictValue& policy) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const base::ListValue* rules = policy.FindList("rules");
  if (!rules) {
    return false;
  }
  javascript_enabled_ = policy.FindBool("javaScriptEnabled").value_or(true);
  javascript_rules_.clear();
  autoplay_patterns_.clear();
  std::set<std::string> unblocked_hosts;
  for (const base::Value& value : *rules) {
    const base::DictValue* rule = value.GetIfDict();
    const std::string* host = rule ? rule->FindString("host") : nullptr;
    if (!host) {
      continue;
    }
    std::string pattern = SitePattern(*host);
    if (pattern.empty()) {
      continue;
    }
    if (std::optional<bool> javascript = rule->FindBool("javaScriptEnabled")) {
      javascript_rules_.emplace_back(pattern, *javascript);
    }
    if (rule->FindBool("autoplayWithSound").value_or(false)) {
      autoplay_patterns_.push_back(pattern);
    }
    if (!rule->FindBool("contentBlockingEnabled").value_or(true)) {
      unblocked_hosts.insert(base::ToLowerASCII(*host));
    }
  }
  ContentBlocking::Get().SetSiteExceptions(std::move(unblocked_hosts));
  return true;
}

void SiteSettings::ApplyTo(Profile* profile) const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  HostContentSettingsMap* map = HostContentSettingsMapFactory::GetForProfile(profile);
  if (map) {
    map->ClearSettingsForOneType(ContentSettingsType::JAVASCRIPT);
    map->SetDefaultContentSetting(ContentSettingsType::JAVASCRIPT,
                                  Setting(javascript_enabled_));
    for (const auto& [pattern, allow] : javascript_rules_) {
      map->SetContentSettingCustomScope(ContentSettingsPattern::FromString(pattern),
                                        ContentSettingsPattern::Wildcard(),
                                        ContentSettingsType::JAVASCRIPT, Setting(allow));
    }
    map->SetDefaultContentSetting(ContentSettingsType::POPUPS, CONTENT_SETTING_ALLOW);
  }
  base::ListValue autoplay;
  for (const std::string& pattern : autoplay_patterns_) {
    autoplay.Append(pattern);
  }
  profile->GetPrefs()->SetList(prefs::kAutoplayAllowlist, std::move(autoplay));
}

}  // namespace refrax
