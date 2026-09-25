// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/download_delegate.h"

#include <utility>

#include "base/no_destructor.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_item_utils.h"
#include "ui/shell_dialogs/selected_file_info.h"

namespace refrax {

namespace {

DownloadDelegate::Asker& AskerStorage() {
  static base::NoDestructor<DownloadDelegate::Asker> asker;
  return *asker;
}

}  // namespace

// static
void DownloadDelegate::Install() {
  DownloadCoreService::SetDelegateFactory(base::BindRepeating(
      [](Profile* profile) -> std::unique_ptr<ChromeDownloadManagerDelegate> {
        return std::make_unique<DownloadDelegate>(profile);
      }));
}

// static
void DownloadDelegate::SetAsker(Asker asker) {
  AskerStorage() = std::move(asker);
}

DownloadDelegate::DownloadDelegate(Profile* profile)
    : ChromeDownloadManagerDelegate(profile) {
  // "Ask where to save each file": every download reaches RequestConfirmation.
  profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, true);
}

DownloadDelegate::~DownloadDelegate() = default;

void DownloadDelegate::RequestConfirmation(download::DownloadItem* download,
                                           const base::FilePath& suggested_path,
                                           DownloadConfirmationReason reason,
                                           ConfirmationCallback callback) {
  content::WebContents* page = content::DownloadItemUtils::GetWebContents(download);
  const Asker& asker = AskerStorage();
  if (!page || !asker) {
    // Nobody to ask: a download never picks its own destination.
    std::move(callback).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
    return;
  }
  asker.Run(page, download, suggested_path, std::move(callback));
}

}  // namespace refrax
