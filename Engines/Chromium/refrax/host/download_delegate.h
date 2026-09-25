// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_DOWNLOAD_DELEGATE_H_
#define REFRAX_HOST_DOWNLOAD_DELEGATE_H_

#include "base/functional/callback.h"
#include "chrome/browser/download/chrome_download_manager_delegate.h"

namespace content {
class WebContents;
}

namespace refrax {

// Every profile's download delegate: Chrome's, except that the destination of each download
// comes from Refrax through the page that started it (the contract's `download` request).
// Refrax never lets an engine choose where files land (CONTRACT.md §4.3).
class DownloadDelegate : public ChromeDownloadManagerDelegate {
 public:
  // Asks the page showing `page` where `download` goes; `callback` runs once.
  using Asker = base::RepeatingCallback<void(content::WebContents* page,
                                             download::DownloadItem* download,
                                             const base::FilePath& suggested_path,
                                             ConfirmationCallback callback)>;

  // Makes every profile's downloads use a DownloadDelegate. Call before any profile loads
  // (patches/download-delegate-factory.patch).
  static void Install();

  // Where downloads are asked about while a client is connected; a null asker cancels them.
  static void SetAsker(Asker asker);

  explicit DownloadDelegate(Profile* profile);
  DownloadDelegate(const DownloadDelegate&) = delete;
  DownloadDelegate& operator=(const DownloadDelegate&) = delete;
  ~DownloadDelegate() override;

 protected:
  // ChromeDownloadManagerDelegate:
  void RequestConfirmation(download::DownloadItem* download,
                           const base::FilePath& suggested_path,
                           DownloadConfirmationReason reason,
                           ConfirmationCallback callback) override;
};

}  // namespace refrax

#endif  // REFRAX_HOST_DOWNLOAD_DELEGATE_H_
