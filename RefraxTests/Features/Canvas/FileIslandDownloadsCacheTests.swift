import Foundation
import SwiftData
import Testing
@testable import Refrax

/// The island's list of downloads is read from the store once per change, and follows changes.
@MainActor
struct FileIslandDownloadsCacheTests {
    /// The container is returned with the manager: the models it holds are only valid while it lives.
    private func makeManager(downloads count: Int) throws -> (DownloadManager, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0 ..< count {
            let download = try Download(
                sourceURL: #require(URL(string: "https://example.com/file\(index).bin")),
                suggestedFilename: "file\(index).bin",
                destinationDirectory: URL(fileURLWithPath: "/tmp"),
            )
            download.createdAt = origin.addingTimeInterval(Double(index))
            download.modifiedAt = download.createdAt
            if index % 50 == 0 {
                download.state = .downloading
            } else {
                download.state = index % 7 == 0 ? .failed : .completed
                download.completedAt = origin.addingTimeInterval(Double(index) + 30)
            }
            context.insert(download)
        }
        try context.save()
        let manager = DownloadManager(modelContext: context)
        manager.performDeferredSetup()
        #expect(manager.downloads.count == count)
        return (manager, container)
    }

    @Test
    func `lists downloads in progress first, then recent ones, and follows a change`() throws {
        let (manager, container) = try makeManager(downloads: 200)
        defer { withExtendedLifetime(container) {} }
        let cache = FileIslandDownloadsCache()
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 200 + 30 + 60)

        let listed = cache.downloads(from: manager, now: now)
        let inProgress = listed.prefix { $0.state.isActive }
        #expect(inProgress.count == 4)
        #expect(zip(inProgress, inProgress.dropFirst()).allSatisfy { $0.createdAt > $1.createdAt })
        let finished = listed.dropFirst(inProgress.count)
        #expect(!finished.isEmpty)
        #expect(finished.allSatisfy { FileIslandLayout.isRecent($0.completedAt ?? $0.modifiedAt, now: now) })
        #expect(zip(finished, finished.dropFirst()).allSatisfy { ($0.completedAt ?? $0.modifiedAt) >= ($1.completedAt ?? $1.modifiedAt) })
        #expect(cache.nextExpiry(from: manager, now: now) != nil)

        // Same clock, no change: the same list, with no new reading of the store.
        let version = cache.version
        #expect(cache.downloads(from: manager, now: now) == listed)
        #expect(cache.version == version)

        // A download finishing changes the list.
        let active = try #require(inProgress.first)
        active.state = .completed
        active.completedAt = now
        let after = cache.downloads(from: manager, now: now)
        #expect(cache.version != version)
        #expect(after.first?.id != active.id)
        #expect(after.contains { $0.id == active.id })
    }

    @Test
    func `a cached read costs a small fraction of a reading of the store`() throws {
        let (manager, container) = try makeManager(downloads: 2_000)
        defer { withExtendedLifetime(container) {} }
        let cache = FileIslandDownloadsCache()
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 2_000 + 60)
        let clock = ContinuousClock()

        // What every read cost before: the whole list through SwiftData, with filters and sorts.
        let uncached = clock.measure { _ = cache.downloads(from: manager, now: now) }
        let cached = clock.measure {
            for _ in 0 ..< 1_000 {
                _ = cache.downloads(from: manager, now: now)
            }
        } / 1_000

        print("FileIslandDownloadsCache: 2000 downloads, reading the store \(uncached), cached read \(cached)")
        #expect(cached * 20 < uncached)
    }
}
