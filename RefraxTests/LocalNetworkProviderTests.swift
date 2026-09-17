import Foundation
import Testing
@testable import Refrax

// MARK: - Test Support

/// A local network with nothing on it, for tests that construct a `CommandLensManager`.
nonisolated struct EmptyLocalNetworkSource: LocalNetworkSnapshotSource {
    func snapshot() async -> LocalNetworkSnapshot {
        .empty
    }
}

/// A fixed local network: a router that also advertises itself over Bonjour, two devices
/// with web interfaces, and a Mac that advertises none.
nonisolated struct FixedLocalNetworkSource: LocalNetworkSnapshotSource {
    static let gateway = LocalNetworkGateway(address: "192.168.1.1", interfaceName: "Ethernet")
    static let router = LocalNetworkService(
        name: "LIVEBOX", type: "_http._tcp", host: "LIVEBOX.local", address: "192.168.1.1", port: 80,
    )
    static let shelly = LocalNetworkService(
        name: "shelly1minig3-3030f9ed2790", type: "_http._tcp", host: "shelly1minig3-3030f9ed2790.local",
        address: "192.168.1.13", port: 80,
    )
    static let shellyControl = LocalNetworkService(
        name: "shelly1minig3-3030f9ed2790", type: "_shelly._tcp", host: "shelly1minig3-3030f9ed2790.local",
        address: "192.168.1.13", port: 80,
    )
    static let homeAssistant = LocalNetworkService(
        name: "Home Assistant", type: "_http._tcp", host: "homeassistant.local", address: "192.168.1.30",
        port: 8_123, path: "/lovelace",
    )
    static let macFiles = LocalNetworkService(
        name: "Kiri's Mac Studio", type: "_smb._tcp", host: "Mac-Studio.local", address: "192.168.1.11", port: 445,
    )
    static let macAudio = LocalNetworkService(
        name: "9C760E465B85@Kiri's Mac Studio", type: "_raop._tcp", host: "Mac-Studio.local", address: nil, port: 7_000,
    )

    var gateway: LocalNetworkGateway? = FixedLocalNetworkSource.gateway
    var services: [LocalNetworkService] = [
        FixedLocalNetworkSource.shelly,
        FixedLocalNetworkSource.shellyControl,
        FixedLocalNetworkSource.router,
        FixedLocalNetworkSource.homeAssistant,
        FixedLocalNetworkSource.macAudio,
        FixedLocalNetworkSource.macFiles,
    ]

    func snapshot() async -> LocalNetworkSnapshot {
        LocalNetworkSnapshot(gateway: gateway, services: services, capturedAt: .now)
    }
}

// MARK: - Provider Tests

@Suite("LocalNetworkProvider", .tags(.commandLensManager))
@MainActor
struct LocalNetworkProviderTests {
    private func context(_ input: String) throws -> SuggestionContext {
        let env = try TabManagerTestEnvironment()
        return SuggestionContext(input: input, settings: env.settings, currentTabID: nil, selectedSearchEngine: nil)
    }

    private func suggestions(for input: String, source: any LocalNetworkSnapshotSource = FixedLocalNetworkSource()) async throws -> [CommandLensSuggestion] {
        let provider = LocalNetworkProvider(source: source)
        let context = try context(input)
        guard provider.shouldProvide(for: context) else { return [] }
        return await provider.suggestions(for: context)
    }

    @Test
    func `Address prefix lists the gateway first, then devices with web interfaces`() async throws {
        let results = try await suggestions(for: "192.168")

        #expect(results.map(\.text) == ["LIVEBOX", "Home Assistant", "shelly1minig3-3030f9ed2790"])
        #expect(results.first?.type == .localDevice(.gateway))
        #expect(results.dropFirst().allSatisfy { $0.type == .localDevice(.service) })
    }

    @Test
    func `A gateway that advertises itself takes its name, address, and interface`() async throws {
        let gateway = try #require(try await suggestions(for: "192").first)

        #expect(gateway.text == "LIVEBOX")
        #expect(gateway.description == "192.168.1.1 · Ethernet")
        #expect(gateway.url == URL(string: "http://192.168.1.1"))
        #expect(gateway.iconName == "wifi.router")
        #expect(gateway.groupHeader == "Local Network")
        #expect(!gateway.isRemovable)
    }

    @Test
    func `A silent gateway shows its address and role`() async throws {
        let source = FixedLocalNetworkSource(services: [FixedLocalNetworkSource.shelly])
        let gateway = try #require(try await suggestions(for: "192.168.1.1", source: source).first)

        #expect(gateway.text == "192.168.1.1")
        #expect(gateway.description == "Default gateway · Ethernet")
        #expect(gateway.url == URL(string: "http://192.168.1.1"))
    }

    @Test
    func `Address prefix narrows to matching devices only`() async throws {
        let results = try await suggestions(for: "192.168.1.3")

        #expect(results.map(\.text) == ["Home Assistant"])
        #expect(results.first?.description == "192.168.1.30:8123/lovelace")
        #expect(results.first?.url == URL(string: "http://192.168.1.30:8123/lovelace"))
    }

    @Test
    func `Devices without a web interface stay out of the lens`() async throws {
        #expect(try await suggestions(for: "192.168.1.11").isEmpty)
        #expect(try await suggestions(for: "mac studio").isEmpty)
    }

    @Test
    func `Other private ranges do not match this network`() async throws {
        #expect(try await suggestions(for: "10.0").isEmpty)
    }

    @Test
    func `Router keywords match the gateway by prefix`() async throws {
        for input in ["rou", "router", "gate", "Gateway"] {
            let results = try await suggestions(for: input)
            #expect(results.map(\.text) == ["LIVEBOX"], "input: \(input)")
        }
    }

    @Test
    func `Name fragments match device names and host names`() async throws {
        #expect(try await suggestions(for: "shelly").map(\.text) == ["shelly1minig3-3030f9ed2790"])
        #expect(try await suggestions(for: "homeassistant").map(\.text) == ["Home Assistant"])
        #expect(try await suggestions(for: "live").map(\.text) == ["LIVEBOX"])
    }

    @Test
    func `Name fragments shorter than three characters are ignored`() throws {
        let provider = LocalNetworkProvider(source: FixedLocalNetworkSource())

        #expect(try !provider.shouldProvide(for: context("sh")))
        #expect(try !provider.shouldProvide(for: context("  ")))
        #expect(try provider.shouldProvide(for: context("1")))
    }

    @Test
    func `A typed scheme is ignored when matching`() async throws {
        #expect(try await suggestions(for: "http://192.168.1.13").map(\.text) == ["shelly1minig3-3030f9ed2790"])
    }

    @Test
    func `Keyword search mode suppresses local network suggestions`() throws {
        let env = try TabManagerTestEnvironment()
        let provider = LocalNetworkProvider(source: FixedLocalNetworkSource())
        let context = SuggestionContext(input: "192", settings: env.settings, currentTabID: nil, selectedSearchEngine: .google)

        #expect(!provider.shouldProvide(for: context))
    }
}

// MARK: - Model Tests

@Suite("LocalNetworkDevice", .tags(.commandLensManager))
struct LocalNetworkDeviceTests {
    @Test
    func `Web address rendering covers ports, paths, unresolved hosts, and non-web services`() {
        #expect(FixedLocalNetworkSource.shelly.displayURL == "192.168.1.13")
        #expect(FixedLocalNetworkSource.homeAssistant.displayURL == "192.168.1.30:8123/lovelace")
        #expect(FixedLocalNetworkSource.macFiles.displayURL == nil)
        #expect(FixedLocalNetworkSource.macFiles.url == nil)

        let secure = LocalNetworkService(name: "NAS", type: "_https._tcp", host: "nas.local", address: nil, port: 443)
        #expect(secure.displayURL == "nas.local")
        #expect(secure.url == URL(string: "https://nas.local"))

        let securePort = LocalNetworkService(name: "NAS", type: "_https._tcp", host: "nas.local", address: "192.168.1.40", port: 5_001)
        #expect(securePort.displayURL == "192.168.1.40:5001")
    }

    @Test
    func `Services group into devices by host, sorted by name`() async {
        let snapshot = await FixedLocalNetworkSource().snapshot()

        #expect(snapshot.devices.map(\.name) == ["Home Assistant", "Kiri's Mac Studio", "LIVEBOX", "shelly1minig3-3030f9ed2790"])

        let shelly = snapshot.devices.first { $0.host == "shelly1minig3-3030f9ed2790.local" }
        #expect(shelly?.serviceTypes == ["_http._tcp", "_shelly._tcp"])
        #expect(shelly?.kind == .homeAutomation)
        #expect(shelly?.webService == FixedLocalNetworkSource.shelly)
    }

    @Test
    func `The router is the device on the gateway address`() async {
        let snapshot = await FixedLocalNetworkSource().snapshot()

        #expect(snapshot.gatewayDevice?.name == "LIVEBOX")
        #expect(snapshot.gatewayDevice?.kind == .router)
    }

    @Test
    func `A device name drops the AirPlay audio MAC prefix and its address comes from any service`() async {
        let snapshot = await FixedLocalNetworkSource().snapshot()
        let mac = snapshot.devices.first { $0.host == "Mac-Studio.local" }

        #expect(mac?.name == "Kiri's Mac Studio")
        #expect(mac?.address == "192.168.1.11")
        #expect(mac?.kind == .computer)
        #expect(mac?.webService == nil)
        #expect(mac?.url == URL(string: "http://192.168.1.11"))
    }

    @Test
    func `A host with no usable instance name falls back to its host label`() {
        let service = LocalNetworkService(name: "", type: "_ssh._tcp", host: "raspberrypi.local", address: nil, port: 22)
        let devices = LocalNetworkDevice.group([service], gatewayAddress: nil)

        #expect(devices.first?.name == "raspberrypi")
        #expect(devices.first?.url == URL(string: "http://raspberrypi.local"))
    }

    @Test
    func `Device kind follows the hardware model, then the most specific service type`() {
        #expect(LocalNetworkDeviceKind.infer(from: ["_ipp._tcp", "_http._tcp"]) == .printer)
        #expect(LocalNetworkDeviceKind.infer(from: ["_airplay._tcp", "_raop._tcp", "_companion-link._tcp"]) == .television)
        #expect(LocalNetworkDeviceKind.infer(from: ["_raop._tcp"]) == .speaker)
        #expect(LocalNetworkDeviceKind.infer(from: ["_hap._tcp", "_http._tcp"]) == .homeAutomation)
        #expect(LocalNetworkDeviceKind.infer(from: ["_http._tcp"]) == .generic)
        #expect(LocalNetworkDeviceKind.infer(from: ["_airplay._tcp", "_hap._tcp"], models: ["AudioAccessory5,1"]) == .speaker)
        #expect(LocalNetworkDeviceKind.infer(from: ["_airplay._tcp", "_hap._tcp"], models: ["AppleTV14,1"]) == .television)
    }

    @Test
    func `Hosts sharing an address merge into one device named by its web interface`() {
        let matter = LocalNetworkService(
            name: "2293D7888BDB090C-00000000B69FF016", type: "_matter._tcp", host: "8CBFEAA1BDBC.local",
            address: "192.168.1.10", port: 5_540,
        )
        let plug = LocalNetworkService(
            name: "shellyplugsg3-8cbfeaa1bdbc", type: "_http._tcp", host: "ShellyPlugSG3-8CBFEAA1BDBC.local",
            address: "192.168.1.10", port: 80,
        )
        let devices = LocalNetworkDevice.group([matter, plug], gatewayAddress: nil)

        #expect(devices.count == 1)
        #expect(devices.first?.name == "shellyplugsg3-8cbfeaa1bdbc")
        #expect(devices.first?.serviceTypes == ["_http._tcp", "_matter._tcp"])
        #expect(devices.first?.webService == plug)
    }
}
