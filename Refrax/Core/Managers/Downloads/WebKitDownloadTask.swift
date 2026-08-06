import Foundation
import WebKit

/// Tracks a download whose transfer is performed by WebKit's own `WKDownload`.
///
/// Most downloads are re-requested through `DownloadTask`'s URLSession (or aria2)
/// so they get acceleration and pause/resume. `blob:` URLs cannot be re-requested —
/// the data exists only inside the web content process — so the original `WKDownload`
/// performs the transfer and this task mirrors its progress into the `Download` model.
///
/// Created by ``DownloadManager/adoptWebKitDownload(_:response:suggestedFilename:originatingURL:originatingTitle:customDownloadPath:spaceID:spaceName:colorTag:)``.
/// Completion and failure arrive through `WKDownloadDelegate` callbacks, which
/// `WKNavigationDelegateAdapter` forwards to the manager.
final class WebKitDownloadTask {
    /// The download model receiving progress updates.
    let download: Download

    /// The WebKit download performing the transfer.
    let wkDownload: WKDownload

    /// Called on every mirrored progress update.
    var onProgress: (@MainActor (WebKitDownloadTask) -> Void)?

    private var progressObservation: NSKeyValueObservation?

    /// Timestamp of the last speed sample.
    private var lastSampleTime = ContinuousClock.now

    /// Bytes received at the last speed sample.
    private var lastSampleBytes: Int64 = 0

    /// Minimum interval between speed recalculations.
    private static let speedSampleInterval: Duration = .milliseconds(500)

    init(download: Download, wkDownload: WKDownload) {
        self.download = download
        self.wkDownload = wkDownload
    }

    /// Begins mirroring the `WKDownload`'s progress into the download model.
    func startObservingProgress() {
        lastSampleTime = ContinuousClock.now
        progressObservation = wkDownload.progress.observe(
            \.completedUnitCount,
            options: [.new],
        ) { [weak self] progress, _ in
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            // KVO can fire on the transfer's queue — hop to main for model updates.
            DispatchQueue.main.async {
                self?.recordProgress(completed: completed, total: total)
            }
        }
    }

    /// Stops mirroring progress. Call before completion/failure bookkeeping.
    func stopObservingProgress() {
        progressObservation = nil
    }

    /// Cancels the underlying WebKit download.
    func cancel() {
        stopObservingProgress()
        wkDownload.cancel(nil)
    }

    private func recordProgress(completed: Int64, total: Int64) {
        let now = ContinuousClock.now
        var speed = download.liveBytesPerSecond
        if now - lastSampleTime >= Self.speedSampleInterval {
            let elapsed = (now - lastSampleTime) / Duration.seconds(1)
            speed = Double(completed - lastSampleBytes) / elapsed
            lastSampleBytes = completed
            lastSampleTime = now
        }

        download.updateLiveProgress(
            bytesReceived: completed,
            totalBytes: total > 0 ? total : nil,
            bytesPerSecond: speed,
        )
        onProgress?(self)
    }
}
