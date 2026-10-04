import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Refrax

@Suite("RoutingRule Persistence", .tags(.dataIntegrity), .serialized)
@MainActor
struct RoutingRulePersistenceTests {
    static let allActions: [RoutingAction] = [
        .openInSpace(UUID()),
        .openInGroup(spaceID: UUID(), groupID: UUID()),
        .createSpace(.init(namePattern: "{domain}", colorHex: "#FF0000", iconName: "globe", useSeparateDataStore: true)),
        .createGroup(spaceID: UUID(), template: .init(namePattern: "{path}", colorHex: "#00FF00")),
        .openInGlimpse,
        .openInBackground,
        .block,
    ]

    static let allConditions: [RoutingCondition] = [
        .domain("*.github.com"),
        .path("*/issues/*"),
        .referrer("news.ycombinator.com"),
        .timeRange(start: "22:00", end: "06:00"),
        .dayOfWeek(.weekday),
        .dayOfWeek(.weekend),
        .dayOfWeek(.specific(3)),
        .currentSpace(UUID()),
        .sourceApp("com.apple.mail"),
    ]

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test(arguments: allActions)
    func `Every action and condition survives a save and a fetch from a fresh context`(action: RoutingAction) throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let rule = RoutingRule(name: "Rule", conditions: Self.allConditions, action: action)
        context.insert(rule)
        try context.save()

        let fetched = try #require(try ModelContext(container).fetch(FetchDescriptor<RoutingRule>()).first)
        #expect(fetched.action == action)
        #expect(fetched.conditions == Self.allConditions)
    }

    @Test
    func `Editing conditions and action persists the new values`() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let rule = RoutingRule(name: "Rule", conditions: [.domain("a.com")], action: .openInGlimpse)
        context.insert(rule)
        try context.save()

        rule.conditions = [.path("/docs/*"), .dayOfWeek(.weekend)]
        rule.action = .block
        try context.save()

        let fetched = try #require(try ModelContext(container).fetch(FetchDescriptor<RoutingRule>()).first)
        #expect(fetched.conditions == [.path("/docs/*"), .dayOfWeek(.weekend)])
        #expect(fetched.action == .block)
    }

    @Test
    func `A rule with undecodable conditions matches nothing`() throws {
        let rule = RoutingRule(name: "Rule", conditions: [], action: .block)
        let context = try NavigationContext(url: #require(URL(string: "https://example.com")))
        #expect(rule.matches(context))

        rule.conditionsJSON = "not json"
        #expect(!rule.matches(context))
    }

    @Test(arguments: allActions)
    func `CloudKit record carries the same JSON shape and round-trips`(action: RoutingAction) throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let original = RoutingRule(name: "Synced", conditions: Self.allConditions, action: action)
        context.insert(original)
        try context.save()

        let record = CKRecord(recordType: RoutingRule.ckRecordType, recordID: RecordMapper.recordID(for: original.id))
        original.encodeToRecord(record)

        let actionJSON = try #require(record["actionJSON"] as? String)
        let conditionsJSON = try #require(record["conditionsJSON"] as? String)
        #expect(try JSONDecoder().decode(RoutingAction.self, from: Data(actionJSON.utf8)) == action)
        #expect(try JSONDecoder().decode([RoutingCondition].self, from: Data(conditionsJSON.utf8)) == Self.allConditions)

        let otherContext = try ModelContext(Self.makeContainer())
        let applied = try RoutingRule.applyRecord(record, into: otherContext)
        try otherContext.save()
        #expect(applied.action == action)
        #expect(applied.conditions == Self.allConditions)
    }
}
