import Foundation
import Observation

/// The File Island's download list, derived once per change of the downloads rather than on
/// every read.
///
/// The island's body reads the list several times per pass, a pass runs on every pointer move
/// and every frame of a drag, and the browser remembers thousands of downloads: each read
/// walked all of them through their SwiftData storage. The cache reads them once, under
/// observation tracking, and drops its copy when any of them changes.
@Observable
final class FileIslandDownloadsCache {
    /// Bumped when the downloads change, so a view reading the list evaluates again.
    private(set) var version: UInt64 = 0

    private struct Entry {
        let download: Download
        /// In progress or paused: listed first, newest first.
        let isCurrent: Bool
        /// Completed or failed: listed while recent, most recently finished first.
        let isFinished: Bool
        let createdAt: Date
        let finishDate: Date
    }

    @ObservationIgnored private var entries: [Entry]?
    @ObservationIgnored private var listedAt: Date?
    @ObservationIgnored private var listed: [Download] = []

    /// Downloads in progress, newest first, then those finished within the hour, most recent first.
    func downloads(from manager: DownloadManager, now: Date) -> [Download] {
        _ = version
        if let listedAt, listedAt == now, entries != nil {
            return listed
        }
        let entries = entries(from: manager)
        let inProgress = entries.filter(\.isCurrent).sorted { $0.createdAt > $1.createdAt }
        let finished = entries.filter { $0.isFinished && FileIslandLayout.isRecent($0.finishDate, now: now) }
            .sorted { $0.finishDate > $1.finishDate }
        listed = (inProgress + finished).map(\.download)
        listedAt = now
        return listed
    }

    /// When the next finished download leaves the island.
    func nextExpiry(from manager: DownloadManager, now: Date) -> Date? {
        _ = version
        return entries(from: manager)
            .filter(\.isFinished)
            .map { $0.finishDate.addingTimeInterval(FileIslandLayout.recentInterval) }
            .filter { $0 > now }
            .min()
    }

    private func entries(from manager: DownloadManager) -> [Entry] {
        if let entries { return entries }
        let entries = withObservationTracking {
            manager.downloads.map { download in
                let state = download.state
                return Entry(
                    download: download,
                    isCurrent: state.isActive || state == .paused,
                    isFinished: state == .completed || state == .failed,
                    createdAt: download.createdAt,
                    finishDate: download.completedAt ?? download.modifiedAt,
                )
            }
        } onChange: { [weak self] in
            // Called as the first tracked value changes, on the changing thread.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.invalidate() }
            } else {
                Task { @MainActor [weak self] in self?.invalidate() }
            }
        }
        self.entries = entries
        return entries
    }

    private func invalidate() {
        guard entries != nil else { return }
        entries = nil
        listedAt = nil
        version &+= 1
    }
}
