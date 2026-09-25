// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/page_downloads.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "components/download/public/common/download_interrupt_reasons.h"
#include "components/download/public/common/download_item.h"
#include "net/base/filename_util.h"
#include "refrax/host/contract_json.h"
#include "ui/shell_dialogs/selected_file_info.h"

namespace refrax {

// Follows one download to its end and reports it.
class PageDownloads::Tracker : public download::DownloadItem::Observer {
 public:
  Tracker(download::DownloadItem* item, EventSender events, base::OnceClosure done)
      : item_(item), events_(std::move(events)), done_(std::move(done)) {
    item_->AddObserver(this);
  }
  ~Tracker() override {
    if (item_) {
      item_->RemoveObserver(this);
    }
  }

  download::DownloadItem* item() const { return item_; }

  void OnDownloadUpdated(download::DownloadItem* item) override {
    const std::string& id = item->GetGuid();
    switch (item->GetState()) {
      case download::DownloadItem::IN_PROGRESS: {
        base::DictValue fields;
        fields.Set("id", id);
        fields.Set("receivedBytes", static_cast<double>(item->GetReceivedBytes()));
        if (item->GetTotalBytes() > 0) {
          fields.Set("totalBytes", static_cast<double>(item->GetTotalBytes()));
        }
        events_.Run("downloadProgressed", std::move(fields));
        return;
      }
      case download::DownloadItem::COMPLETE:
        events_.Run("downloadFinished", base::DictValue().Set("id", id));
        break;
      case download::DownloadItem::CANCELLED:
        events_.Run("downloadFailed",
                    base::DictValue().Set("id", id).Set("reason", "cancelled"));
        break;
      case download::DownloadItem::INTERRUPTED:
        events_.Run("downloadFailed",
                    base::DictValue().Set("id", id).Set(
                        "reason",
                        download::DownloadInterruptReasonToString(item->GetLastReason())));
        break;
      case download::DownloadItem::MAX_DOWNLOAD_STATE:
        return;
    }
    Finish();
  }

  void OnDownloadDestroyed(download::DownloadItem* item) override {
    item_->RemoveObserver(this);
    item_ = nullptr;
    Finish();
  }

 private:
  void Finish() {
    if (done_) {
      std::move(done_).Run();  // Deletes this.
    }
  }

  raw_ptr<download::DownloadItem> item_;
  EventSender events_;
  base::OnceClosure done_;
};

PageDownloads::PageDownloads(RequestSender requests, EventSender events)
    : requests_(std::move(requests)), events_(std::move(events)) {}

PageDownloads::~PageDownloads() {
  for (auto& [id, callback] : pending_) {
    std::move(callback).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
  }
}

void PageDownloads::Ask(download::DownloadItem* download,
                        const base::FilePath& suggested_path,
                        DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
  const std::string id = download->GetGuid();
  base::DictValue fields;
  fields.Set("id", id);
  fields.Set("url", contract::URLValue(download->GetURL()));
  fields.Set("suggestedFilename", suggested_path.BaseName().AsUTF8Unsafe());
  if (!download->GetMimeType().empty()) {
    fields.Set("mimeType", download->GetMimeType());
  }
  if (download->GetTotalBytes() > 0) {
    fields.Set("totalBytes", static_cast<double>(download->GetTotalBytes()));
  }
  pending_[id] = std::move(callback);
  running_[id] = std::make_unique<Tracker>(
      download, events_,
      base::BindOnce(&PageDownloads::OnFinished, weak_factory_.GetWeakPtr(), id));
  requests_.Run(contract::Message("download", std::move(fields)),
                base::BindOnce(&PageDownloads::OnAnswer, weak_factory_.GetWeakPtr(), id));
}

void PageDownloads::OnAnswer(const std::string& id, const std::string& answer) {
  auto it = pending_.find(id);
  if (it == pending_.end()) {
    return;
  }
  auto callback = std::move(it->second);
  pending_.erase(it);
  auto message = contract::ParseMessage(answer);
  const std::string* url =
      message && message->first == "saveTo" ? message->second.FindString("url") : nullptr;
  base::FilePath path;
  if (!url || !net::FileURLToFilePath(GURL(*url), &path) || path.empty()) {
    // Refrax declined: it never started this download, so nothing is reported for it.
    running_.erase(id);
    std::move(callback).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
    return;
  }
  std::move(callback).Run(DownloadConfirmationResult::CONFIRMED, ui::SelectedFileInfo(path));
}

void PageDownloads::Cancel(const std::string& id) {
  if (auto it = running_.find(id); it != running_.end() && it->second->item()) {
    it->second->item()->Cancel(/*user_cancel=*/true);
  }
}

void PageDownloads::OnFinished(const std::string& id) {
  running_.erase(id);
}

}  // namespace refrax
