import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Refrax

@Suite("Sync Round-Trip", .serialized)
@MainActor
struct SyncRoundTripTests {

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer with the full app schema.
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a CKRecord with a deterministic ID for the given model UUID and type.
    private static func makeRecord(for uuid: UUID, recordType: String) -> CKRecord {
        CKRecord(
            recordType: recordType,
            recordID: RecordMapper.recordID(for: uuid)
        )
    }

    // MARK: - Space Round-Trip

    @Test("Space encodes all fields to CKRecord")
    func spaceEncode() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let space = Space(
            name: "Work",
            iconName: "briefcase",
            colorHex: "Flamingo",
            position: 7,
            dataStoreMode: .separate,
            isLockEnabled: true
        )
        space.spaceDescription = "My work space"
        space.customDownloadPath = "/tmp/downloads"
        space.downloadColorTag = 3
        space.lockTimeoutOverride = 120
        context.insert(space)
        try context.save()

        let record = Self.makeRecord(for: space.id, recordType: Space.ckRecordType)
        space.encodeToRecord(record)

        #expect(record["name"] as? String == "Work")
        #expect(record["iconName"] as? String == "briefcase")
        #expect(record["colorHex"] as? String == "Flamingo")
        #expect(record["position"] as? Int == 7)
        #expect(record["dataStoreMode"] as? String == "separate")
        #expect(record["isLockEnabled"] as? Bool == true)
        #expect(record["createdAt"] as? Date != nil)
        #expect(record["spaceDescription"] as? String == "My work space")
        #expect(record["customDownloadPath"] as? String == "/tmp/downloads")
        #expect(record["downloadColorTag"] as? Int == 3)
        #expect(record["lockTimeoutOverride"] as? Int == 120)
    }

    @Test("Space round-trips through CKRecord without data loss")
    func spaceRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let original = Space(
            name: "Research",
            iconName: "magnifyingglass",
            colorHex: "Emerald",
            position: 3,
            dataStoreMode: .global,
            isLockEnabled: false
        )
        original.spaceDescription = "Deep dives"
        context.insert(original)
        try context.save()

        let record = Self.makeRecord(for: original.id, recordType: Space.ckRecordType)
        original.encodeToRecord(record)

        let freshContext = ModelContext(container)
        context.delete(original)
        try context.save()

        let decoded = try Space.applyRecord(record, into: freshContext)
        try freshContext.save()

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Research")
        #expect(decoded.iconName == "magnifyingglass")
        #expect(decoded.colorHex == "Emerald")
        #expect(decoded.position == 3)
        #expect(decoded.dataStoreMode == .global)
        #expect(decoded.isLockEnabled == false)
        #expect(decoded.spaceDescription == "Deep dives")
    }

    // MARK: - Tab Round-Trip

    @Test("Tab encodes all fields to CKRecord")
    func tabEncode() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let space = Space(name: "Default", iconName: "globe")
        context.insert(space)

        let tab = Tab(
            space: space,
            url: URL(string: "https://example.com")!,
            title: "Example",
            status: .pinned,
            position: 5
        )
        tab.customName = "My Tab"
        tab.isUnread = true
        tab.unreadFromBadge = true
        tab.lastBadgeCount = 3
        tab.originURL = URL(string: "https://origin.example.com")!
        context.insert(tab)
        try context.save()

        let record = Self.makeRecord(for: tab.id, recordType: Tab.ckRecordType)
        tab.encodeToRecord(record)

        #expect(record["status"] as? String == "pinned")
        #expect(record["isReferenceTab"] as? Bool == false)
        #expect(record["isUnread"] as? Bool == true)
        #expect(record["unreadFromBadge"] as? Bool == true)
        #expect(record["position"] as? Int == 5)
        #expect(record["customName"] as? String == "My Tab")
        #expect(record["lastBadgeCount"] as? Int == 3)
        #expect(record["originURL"] as? String == "https://origin.example.com")
        #expect(record["createdAt"] as? Date != nil)

        let spaceRef = record["spaceRef"] as? CKRecord.Reference
        #expect(spaceRef != nil)
        #expect(RecordMapper.uuid(from: spaceRef!.recordID) == space.id)
    }

    @Test("Tab round-trips through CKRecord without data loss")
    func tabRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let space = Space(name: "Default", iconName: "globe")
        context.insert(space)

        let tab = Tab(
            space: space,
            url: URL(string: "https://swift.org")!,
            title: "Swift",
            status: .regular,
            position: 2
        )
        tab.customName = "Swift Lang"
        tab.isUnread = true
        context.insert(tab)
        try context.save()

        let record = Self.makeRecord(for: tab.id, recordType: Tab.ckRecordType)
        tab.encodeToRecord(record)

        let freshContext = ModelContext(container)
        context.delete(tab)
        try context.save()

        let decoded = try Tab.applyRecord(record, into: freshContext)
        try freshContext.save()

        #expect(decoded.id == tab.id)
        #expect(decoded.status == .regular)
        #expect(decoded.customName == "Swift Lang")
        #expect(decoded.isUnread == true)
        #expect(decoded.position == 2)
        #expect(decoded.space?.id == space.id)
    }

    // MARK: - Bookmark Round-Trip

    @Test("Bookmark encodes all fields to CKRecord")
    func bookmarkEncode() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let bookmark = Bookmark(
            url: URL(string: "https://apple.com")!,
            title: "Apple",
            isFavorite: true,
            tags: ["tech", "apple"]
        )
        bookmark.favoriteColor = "Coral"
        bookmark.visitCount = 42
        context.insert(bookmark)
        try context.save()

        let record = Self.makeRecord(for: bookmark.id, recordType: Bookmark.ckRecordType)
        bookmark.encodeToRecord(record)

        #expect(record["url"] as? String == "https://apple.com")
        #expect(record["title"] as? String == "Apple")
        #expect(record["isFavorite"] as? Bool == true)
        #expect(record["favoriteMode"] as? String == FavoriteMode.liveFavorite.rawValue)
        #expect(record["visitCount"] as? Int == 42)
        #expect(record["tags"] as? [String] == ["tech", "apple"])
        #expect(record["favoriteColor"] as? String == "Coral")
        #expect(record["createdAt"] as? Date != nil)
        #expect(record["lastModified"] as? Date != nil)
    }

    @Test("Bookmark lastModified survives round-trip")
    func bookmarkLastModifiedRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let bookmark = Bookmark(
            url: URL(string: "https://example.com/article")!,
            title: "Article"
        )
        bookmark.lastModified = fixedDate
        context.insert(bookmark)
        try context.save()

        let record = Self.makeRecord(for: bookmark.id, recordType: Bookmark.ckRecordType)
        bookmark.encodeToRecord(record)

        let freshContext = ModelContext(container)
        context.delete(bookmark)
        try context.save()

        let decoded = try Bookmark.applyRecord(record, into: freshContext)
        try freshContext.save()

        #expect(decoded.id == bookmark.id)
        #expect(decoded.url == URL(string: "https://example.com/article")!)
        #expect(decoded.title == "Article")
        #expect(decoded.lastModified == fixedDate)
    }

    @Test("Bookmark round-trips tags and optional fields")
    func bookmarkFullRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let spaceID = UUID()
        let bookmark = Bookmark(
            url: URL(string: "https://news.ycombinator.com")!,
            title: "Hacker News",
            isFavorite: true,
            favoriteMode: .shortcut,
            tags: ["news", "tech", "daily"],
            spaceID: spaceID
        )
        bookmark.favoriteColor = "Violet"
        bookmark.customIconJSON = "{\"type\":\"emoji\",\"value\":\"📰\"}"
        bookmark.visitCount = 100
        context.insert(bookmark)
        try context.save()

        let record = Self.makeRecord(for: bookmark.id, recordType: Bookmark.ckRecordType)
        bookmark.encodeToRecord(record)

        let freshContext = ModelContext(container)
        context.delete(bookmark)
        try context.save()

        let decoded = try Bookmark.applyRecord(record, into: freshContext)
        try freshContext.save()

        #expect(decoded.url == URL(string: "https://news.ycombinator.com")!)
        #expect(decoded.title == "Hacker News")
        #expect(decoded.isFavorite == true)
        #expect(decoded.favoriteMode == .shortcut)
        #expect(decoded.tags == ["news", "tech", "daily"])
        #expect(decoded.spaceID == spaceID)
        #expect(decoded.favoriteColor == "Violet")
        #expect(decoded.customIconJSON == "{\"type\":\"emoji\",\"value\":\"📰\"}")
        #expect(decoded.visitCount == 100)
    }

    // MARK: - BrowserSettings Round-Trip

    @Test("BrowserSettings encodes representative fields to CKRecord")
    func browserSettingsEncode() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let settings = BrowserSettings()
        settings.searchEngineID = "duckduckgo"
        settings.doNotTrack = true
        settings.enableAutoConsent = true
        settings.defaultVideoSpeed = 1.5
        settings.speedReaderWPM = 400
        settings.feedbackName = "Kiri"
        settings.feedbackEmail = "test@example.com"
        settings.archiveEnabled = true
        settings.agentDisplayName = "Sora"
        context.insert(settings)
        try context.save()

        let recordID = CKRecord.ID(
            recordName: BrowserSettings.singletonRecordName,
            zoneID: RecordMapper.zoneID
        )
        let record = CKRecord(recordType: BrowserSettings.ckRecordType, recordID: recordID)
        settings.encodeToRecord(record)

        #expect(record["searchEngineID"] as? String == "duckduckgo")
        #expect(record["doNotTrack"] as? Bool == true)
        #expect(record["enableAutoConsent"] as? Bool == true)
        #expect(record["defaultVideoSpeed"] as? Double == 1.5)
        #expect(record["speedReaderWPM"] as? Int == 400)
        #expect(record["feedbackName"] as? String == "Kiri")
        #expect(record["feedbackEmail"] as? String == "test@example.com")
        #expect(record["archiveEnabled"] as? Bool == true)
        #expect(record["agentDisplayName"] as? String == "Sora")
    }

    @Test("BrowserSettings applyRecord updates existing singleton")
    func browserSettingsSingletonBehavior() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let existing = BrowserSettings()
        existing.feedbackName = "Original"
        context.insert(existing)
        try context.save()

        let recordID = CKRecord.ID(
            recordName: BrowserSettings.singletonRecordName,
            zoneID: RecordMapper.zoneID
        )
        let record = CKRecord(recordType: BrowserSettings.ckRecordType, recordID: recordID)
        record["feedbackName"] = "Updated" as NSString
        record["feedbackEmail"] = "updated@example.com" as NSString
        record["doNotTrack"] = false as NSNumber
        record["speedReaderWPM"] = 350 as NSNumber
        record["agentDisplayName"] = "Agent V2" as NSString

        let result = try BrowserSettings.applyRecord(record, into: context)
        try context.save()

        #expect(result.feedbackName == "Updated")
        #expect(result.feedbackEmail == "updated@example.com")
        #expect(result.doNotTrack == false)
        #expect(result.speedReaderWPM == 350)
        #expect(result.agentDisplayName == "Agent V2")

        let allSettings = try context.fetch(FetchDescriptor<BrowserSettings>())
        #expect(allSettings.count == 1, "BrowserSettings must remain a singleton")
    }

    @Test("BrowserSettings round-trips representative fields")
    func browserSettingsRoundTrip() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let settings = BrowserSettings()
        settings.searchEngineID = "google"
        settings.doNotTrack = false
        settings.enableGlobalPrivacyControl = false
        settings.defaultVideoSpeed = 2.0
        settings.speedReaderWPM = 500
        settings.feedbackName = "Tester"
        settings.archiveEnabled = true
        settings.archiveClearHours = 48
        settings.agentClaudeMaxTokens = 16_384
        settings.controlAccessModeRaw = ControlAccessMode.open.rawValue
        context.insert(settings)
        try context.save()

        let recordID = CKRecord.ID(
            recordName: BrowserSettings.singletonRecordName,
            zoneID: RecordMapper.zoneID
        )
        let record = CKRecord(recordType: BrowserSettings.ckRecordType, recordID: recordID)
        settings.encodeToRecord(record)

        context.delete(settings)
        try context.save()

        let decoded = try BrowserSettings.applyRecord(record, into: context)
        try context.save()

        #expect(decoded.searchEngineID == "google")
        #expect(decoded.doNotTrack == false)
        #expect(decoded.enableGlobalPrivacyControl == false)
        #expect(decoded.defaultVideoSpeed == 2.0)
        #expect(decoded.speedReaderWPM == 500)
        #expect(decoded.feedbackName == "Tester")
        #expect(decoded.archiveEnabled == true)
        #expect(decoded.archiveClearHours == 48)
        #expect(decoded.agentClaudeMaxTokens == 16_384)
        #expect(decoded.controlAccessModeRaw == ControlAccessMode.open.rawValue)
    }

    // MARK: - RecordMapper Utilities

    @Test("RecordMapper round-trips UUID through record ID")
    func recordMapperUUIDRoundTrip() {
        let uuid = UUID()
        let recordID = RecordMapper.recordID(for: uuid)
        let extracted = RecordMapper.uuid(from: recordID)
        #expect(extracted == uuid)
    }

    @Test("RecordMapper uses correct zone")
    func recordMapperZone() {
        let uuid = UUID()
        let recordID = RecordMapper.recordID(for: uuid)
        #expect(recordID.zoneID == RecordMapper.zoneID)
        #expect(recordID.zoneID.zoneName == "RefraxSync")
    }

    @Test("RecordMapper reference contains correct target UUID")
    func recordMapperReference() {
        let targetUUID = UUID()
        let ref = RecordMapper.reference(
            to: targetUUID,
            recordType: "Space",
            action: .deleteSelf
        )
        #expect(RecordMapper.uuid(from: ref.recordID) == targetUUID)
    }

    @Test("RecordMapper optional reference returns nil for nil UUID")
    func recordMapperOptionalReference() {
        let ref = RecordMapper.optionalReference(
            to: nil,
            recordType: "Space",
            action: .none
        )
        #expect(ref == nil)
    }
}
