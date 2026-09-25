import Foundation
import SwiftData

/// The stored notification permissions, one ``WebNotificationPermission`` per origin.
///
/// Reads are served from an in-memory map keyed by origin string, because WebKit asks for
/// the whole map every time a web process launches. Writes update the map and the model
/// context together. Decisions save right away, since they must survive a crash; delivery
/// statistics save on a debounce.
@MainActor
final class WebNotificationPermissionStore {
    private static let statisticsSaveDelay: TimeInterval = 5

    private let modelContext: ModelContext
    private let statisticsSaver: DebouncedModelContextSaver
    private var recordsByOrigin: [String: WebNotificationPermission] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.statisticsSaver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: Self.statisticsSaveDelay,
            logCategory: Logger.notifications,
        )
        reload()
    }

    // MARK: Reading

    /// The origin's decision, or nil when it never asked or was removed.
    func state(for origin: WebOrigin) -> WebNotificationPermission.State? {
        recordsByOrigin[origin.string]?.state
    }

    func record(for origin: WebOrigin) -> WebNotificationPermission? {
        recordsByOrigin[origin.string]
    }

    /// Every origin that asked, ordered by host.
    var records: [WebNotificationPermission] {
        recordsByOrigin.values.sorted { lhs, rhs in
            switch (lhs.webOrigin, rhs.webOrigin) {
            case let (left?, right?): left < right
            default: lhs.origin < rhs.origin
            }
        }
    }

    /// Origin string → granted, in the form WebKit's permission maps take.
    var permissionMap: [String: Bool] {
        recordsByOrigin.mapValues { $0.state == .granted }
    }

    // MARK: Writing

    /// Stores `state` for `origin`, creating the record on its first decision.
    @discardableResult
    func setState(_ state: WebNotificationPermission.State, for origin: WebOrigin, at date: Date = Date()) -> WebNotificationPermission {
        let record: WebNotificationPermission
        if let existing = recordsByOrigin[origin.string] {
            existing.state = state
            existing.decidedAt = date
            record = existing
        } else {
            record = WebNotificationPermission(origin: origin, state: state, at: date)
            modelContext.insert(record)
            recordsByOrigin[origin.string] = record
        }
        save()
        return record
    }

    /// Counts a notification the origin showed.
    func recordNotification(from origin: WebOrigin, at date: Date = Date()) {
        guard let record = recordsByOrigin[origin.string] else { return }
        record.notificationCount += 1
        record.lastNotificationAt = date
        statisticsSaver.scheduleSave()
    }

    /// Forgets the origins; each asks again next time.
    func remove(_ origins: [WebOrigin]) {
        for origin in origins {
            if let record = recordsByOrigin.removeValue(forKey: origin.string) {
                modelContext.delete(record)
            }
        }
        save()
    }

    /// Forgets every origin.
    func removeAll() {
        for record in recordsByOrigin.values {
            modelContext.delete(record)
        }
        recordsByOrigin.removeAll()
        save()
    }

    // MARK: Persistence

    private func reload() {
        let records = (try? modelContext.fetch(FetchDescriptor<WebNotificationPermission>())) ?? []
        recordsByOrigin = Dictionary(records.map { ($0.origin, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save notification permissions: \(error)", category: Logger.notifications)
        }
    }
}
