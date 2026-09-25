// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_PAGE_DOWNLOADS_H_
#define REFRAX_HOST_PAGE_DOWNLOADS_H_

#include <map>
#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/download/download_target_determiner_delegate.h"

namespace download {
class DownloadItem;
}

namespace refrax {

// A page's downloads on the contract (CONTRACT.md §4.3): asks Refrax where each one goes, then
// reports downloadProgressed and exactly one of downloadFinished or downloadFailed.
class PageDownloads {
 public:
  using RequestSender = base::RepeatingCallback<void(
      std::string request,
      base::OnceCallback<void(const std::string& answer)> answer)>;
  using EventSender =
      base::RepeatingCallback<void(std::string_view name, base::DictValue fields)>;

  PageDownloads(RequestSender requests, EventSender events);
  PageDownloads(const PageDownloads&) = delete;
  PageDownloads& operator=(const PageDownloads&) = delete;
  // Cancels downloads still waiting for a destination.
  ~PageDownloads();

  // Asks Refrax where `download` goes; `callback` confirms that path or cancels.
  void Ask(download::DownloadItem* download,
           const base::FilePath& suggested_path,
           DownloadTargetDeterminerDelegate::ConfirmationCallback callback);

  // The contract's cancelDownload.
  void Cancel(const std::string& id);

 private:
  class Tracker;

  void OnAnswer(const std::string& id, const std::string& answer);
  void OnFinished(const std::string& id);

  RequestSender requests_;
  EventSender events_;
  // Downloads waiting on Refrax's answer, by contract id (the download's GUID).
  std::map<std::string, DownloadTargetDeterminerDelegate::ConfirmationCallback> pending_;
  // Downloads running to the destination Refrax chose.
  std::map<std::string, std::unique_ptr<Tracker>> running_;
  base::WeakPtrFactory<PageDownloads> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_PAGE_DOWNLOADS_H_
