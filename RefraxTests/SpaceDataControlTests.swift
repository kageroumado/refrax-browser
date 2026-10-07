import Foundation
import RefraxProtocol
import Testing
@testable import Refrax

// MARK: - Space References

@Suite("Space references and data modes", .tags(.spaceManager), .serialized)
@MainActor
struct SpaceReferenceTests {
    @Test("A UUID resolves to its space, in any letter case")
    func resolvesUUID() throws {
        let env = try SpaceManagerTestEnvironment()
        let space = env.spaceManager.createSpace(name: "Ref UUID", iconName: "star")

        #expect(try env.spaceManager.findSpace(byReference: space.id.uuidString) === space)
        #expect(try env.spaceManager.findSpace(byReference: space.id.uuidString.lowercased()) === space)
    }

    @Test("A name resolves by exact, case-insensitive match")
    func resolvesName() throws {
        let env = try SpaceManagerTestEnvironment()
        let space = env.spaceManager.createSpace(name: "Ref Tools", iconName: "star")

        #expect(try env.spaceManager.findSpace(byReference: "Ref Tools") === space)
        #expect(try env.spaceManager.findSpace(byReference: "ref tools") === space)
    }

    @Test("A partial name matches nothing")
    func partialNameIsNotFound() throws {
        let env = try SpaceManagerTestEnvironment()
        _ = env.spaceManager.createSpace(name: "Ref Tools", iconName: "star")

        #expect(throws: SpaceReferenceError.notFound("Ref Too")) {
            try env.spaceManager.findSpace(byReference: "Ref Too")
        }
    }

    @Test("A name shared by two spaces is ambiguous and lists both IDs")
    func sharedNameIsAmbiguous() throws {
        let env = try SpaceManagerTestEnvironment()
        let first = env.spaceManager.createSpace(name: "Ref Twin", iconName: "star")
        let second = env.spaceManager.createSpace(name: "ref twin", iconName: "heart")

        #expect(throws: SpaceReferenceError.ambiguous("Ref Twin", candidateIDs: [first.id, second.id])) {
            try env.spaceManager.findSpace(byReference: "Ref Twin")
        }
    }

    @Test("Each --data argument creates a space with that mode", arguments: [
        ("global", DataStoreMode.global),
        ("separate", .separate),
        ("Private", .private),
    ])
    func createsEachMode(argument: String, expected: DataStoreMode) throws {
        let env = try SpaceManagerTestEnvironment()
        let mode = try #require(DataStoreMode(controlArgument: argument))
        let space = env.spaceManager.createSpace(name: "Ref \(argument)", iconName: "star", dataStoreMode: mode)

        #expect(space.dataStoreMode == expected)
    }

    @Test("An unknown --data argument is rejected")
    func rejectsUnknownMode() {
        #expect(DataStoreMode(controlArgument: "isolated") == nil)
    }

    @Test("A shared-store space never exposes its cookies, even with the flag set")
    func globalSpaceNeverExposes() throws {
        let env = try SpaceManagerTestEnvironment()
        let global = env.spaceManager.createSpace(name: "Ref Global", iconName: "star", dataStoreMode: .global)
        let separate = env.spaceManager.createSpace(name: "Ref Separate", iconName: "star", dataStoreMode: .separate)
        global.exposesCookiesToControl = true
        separate.exposesCookiesToControl = true

        #expect(!global.exposesCookiesToControlServer)
        #expect(separate.exposesCookiesToControlServer)
    }
}

// MARK: - Cookie Access

@Suite("Control server cookie access")
struct ControlCookieAccessTests {
    private static func cookie(
        _ name: String,
        domain: String,
        path: String = "/",
        httpOnly: Bool = false,
        expires: Date? = nil,
    ) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: "secret-\(name)",
            .domain: domain,
            .path: path,
            .secure: "TRUE",
        ]
        if httpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if let expires {
            properties[.expires] = expires
        }
        return try #require(HTTPCookie(properties: properties))
    }

    // MARK: Domain matching

    @Test("Domain filter matching", arguments: [
        ("example.com", true),
        (".example.com", true),
        ("api.example.com", true),
        (".API.Example.com", true),
        ("notexample.com", false),
        ("example.com.evil.net", false),
        ("com", false),
    ])
    func domainMatching(cookieDomain: String, expected: Bool) {
        #expect(ControlCookieAccess.domain(cookieDomain, matches: "example.com") == expected)
    }

    @Test("A leading dot on the filter is ignored")
    func filterLeadingDot() {
        #expect(ControlCookieAccess.domain("example.com", matches: ".example.com"))
    }

    // MARK: Gate

    @Test("A locked space refuses every read, gate or not", arguments: [false, true])
    func lockedRefusesEverything(exposes: Bool) {
        let gate = ControlCookieAccess.Gate(isLocked: true, exposesCookies: exposes)

        #expect(throws: ControlCookieAccess.Refusal.locked) {
            try ControlCookieAccess.authorizeRead(reveal: false, gate: gate)
        }
        #expect(throws: ControlCookieAccess.Refusal.locked) {
            try ControlCookieAccess.authorizeExport(gate: gate)
        }
    }

    @Test("Without exposure: script-visible metadata only; --reveal and export refused")
    func unexposedSpace() throws {
        let gate = ControlCookieAccess.Gate(isLocked: false, exposesCookies: false)

        let grant = try ControlCookieAccess.authorizeRead(reveal: false, gate: gate)
        #expect(grant == .init(includesHTTPOnly: false, revealsValues: false))
        #expect(!grant.isGated)

        #expect(throws: ControlCookieAccess.Refusal.notExposed) {
            try ControlCookieAccess.authorizeRead(reveal: true, gate: gate)
        }
        #expect(throws: ControlCookieAccess.Refusal.notExposed) {
            try ControlCookieAccess.authorizeExport(gate: gate)
        }
    }

    @Test("With exposure: HttpOnly cookies listed and values revealable")
    func exposedSpace() throws {
        let gate = ControlCookieAccess.Gate(isLocked: false, exposesCookies: true)

        let listing = try ControlCookieAccess.authorizeRead(reveal: false, gate: gate)
        #expect(listing == .init(includesHTTPOnly: true, revealsValues: false))
        #expect(listing.isGated)

        let revealing = try ControlCookieAccess.authorizeRead(reveal: true, gate: gate)
        #expect(revealing.revealsValues)
        try ControlCookieAccess.authorizeExport(gate: gate)
    }

    @Test("HttpOnly cookies are hidden unless the grant includes them")
    func httpOnlyFiltering() throws {
        let cookies = try [
            Self.cookie("visible", domain: "example.com"),
            Self.cookie("session", domain: "example.com", httpOnly: true),
        ]

        let hidden = ControlCookieAccess.visibleCookies(
            cookies,
            domain: "example.com",
            grant: .init(includesHTTPOnly: false, revealsValues: false),
        )
        #expect(hidden.map(\.name) == ["visible"])

        let shown = ControlCookieAccess.visibleCookies(
            cookies,
            domain: "example.com",
            grant: .init(includesHTTPOnly: true, revealsValues: false),
        )
        #expect(Set(shown.map(\.name)) == ["visible", "session"])
    }

    // MARK: Export selection

    @Test("Export picks the most specific cookie per name and reports missing names")
    func exportSelection() throws {
        let cookies = try [
            Self.cookie("sid", domain: ".example.com"),
            Self.cookie("sid", domain: "app.example.com", path: "/api"),
            Self.cookie("csrf", domain: "example.com"),
            Self.cookie("sid", domain: "other.com"),
        ]

        let (selected, missing) = ControlCookieAccess.exportSelection(
            cookies,
            domain: "example.com",
            names: ["sid", "csrf", "absent"],
        )

        #expect(selected.map(\.name) == ["sid", "csrf"])
        #expect(selected.first?.domain == "app.example.com")
        #expect(missing == ["absent"])
    }

    // MARK: Mapping

    @Test("CookieInfo carries real metadata and redacts the value by default")
    func cookieInfoMapping() throws {
        // Within HTTPCookie's 400-day lifetime cap, in whole seconds as ISO 8601 prints it.
        let expiry = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 30 * 86_400).rounded(.down))
        let persistent = try Self.cookie("sid", domain: ".example.com", path: "/app", httpOnly: true, expires: expiry)
        let session = try Self.cookie("tmp", domain: "example.com")

        let redacted = ControlCookieAccess.cookieInfo(persistent, revealValue: false)
        #expect(redacted.value == nil)
        #expect(redacted.domain == ".example.com")
        #expect(redacted.path == "/app")
        #expect(redacted.isSecure)
        #expect(redacted.isHTTPOnly)
        #expect(redacted.expiresDate == expiry.formatted(.iso8601))

        #expect(ControlCookieAccess.cookieInfo(persistent, revealValue: true).value == "secret-sid")
        #expect(ControlCookieAccess.cookieInfo(session, revealValue: false).expiresDate == nil)
    }

    @Test("A redacted value encodes as an explicit null")
    func redactedValueEncodesNull() throws {
        let info = CTL.CookieInfo(
            name: "sid", value: nil, domain: "example.com", path: "/",
            isSecure: true, isHTTPOnly: true, expiresDate: nil,
        )
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])

        #expect(json.keys.contains("value"))
        #expect(json["value"] is NSNull)
    }
}

// MARK: - Protocol

@Suite("Control protocol space updates")
struct SpaceUpdateProtocolTests {
    @Test("spaceUpdate rejects a payload that tries to set cookie exposure")
    func rejectsExposureKey() {
        let payload = Data(#"{"type":"spaceUpdate","id":"Tools","exposesCookiesToControl":true}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ControlRequest.self, from: payload)
        }
    }

    @Test("spaceUpdate still decodes its own fields")
    func decodesOrdinaryUpdate() throws {
        let payload = Data(#"{"type":"spaceUpdate","id":"Tools","name":"Tools 2"}"#.utf8)

        guard case let .spaceUpdate(params) = try JSONDecoder().decode(ControlRequest.self, from: payload) else {
            Issue.record("Decoded the wrong request type")
            return
        }
        #expect(params.id == "Tools")
        #expect(params.name == "Tools 2")
    }
}
