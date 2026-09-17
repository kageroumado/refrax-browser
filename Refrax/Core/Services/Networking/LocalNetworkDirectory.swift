import Foundation
import SystemConfiguration

/// The router this Mac sends non-local traffic through.
nonisolated struct LocalNetworkGateway: Hashable, Sendable {
    /// IPv4 address of the router, e.g. `192.168.1.1`.
    let address: String

    /// Localized name of the interface that reaches the router, e.g. "Wi-Fi" or "Ethernet".
    let interfaceName: String?

    /// The router's web interface over plain HTTP.
    var url: URL? {
        URL(string: "http://\(address)")
    }
}

/// One Bonjour service instance on the local network.
nonisolated struct LocalNetworkService: Hashable, Sendable {
    /// The Bonjour instance name, e.g. "LIVEBOX" or "Kiri's Mac Studio".
    let name: String

    /// The service type without domain, e.g. `_http._tcp` or `_airplay._tcp`.
    let type: String

    /// The mDNS host name without its trailing dot, e.g. `LIVEBOX.local`.
    let host: String

    /// The IPv4 address the host resolved to, when resolution finished within the browse window.
    let address: String?

    /// TCP or UDP port the service listens on.
    let port: UInt16

    /// Absolute path of a web interface, from the TXT record's `path` key; `/` when absent.
    let path: String

    /// Hardware model from the TXT record's `model` key, e.g. `AppleTV14,1` or `AudioAccessory5,1`.
    let model: String?

    init(name: String, type: String, host: String, address: String?, port: UInt16, path: String = "/", model: String? = nil) {
        self.name = name
        self.type = type
        self.host = host
        self.address = address
        self.port = port
        self.path = path
        self.model = model
    }

    /// URL scheme for the two service types that are web interfaces.
    var webScheme: String? {
        switch type {
        case "_http._tcp": "http"
        case "_https._tcp": "https"
        default: nil
        }
    }

    /// The address a user would type for a web interface: the IPv4 address when known, otherwise
    /// the host name, then the port when it is not the scheme default and the path when it is not
    /// the root. `nil` for services that are not web interfaces.
    var displayURL: String? {
        guard let webScheme else { return nil }
        var result = address ?? host
        let defaultPort: UInt16 = webScheme == "https" ? 443 : 80
        if port != defaultPort {
            result += ":\(port)"
        }
        if path != "/" {
            result += path
        }
        return result
    }

    var url: URL? {
        guard let webScheme, let displayURL else { return nil }
        return URL(string: "\(webScheme)://\(displayURL)")
    }
}

/// What a device on the local network is, judged from the services it advertises.
nonisolated enum LocalNetworkDeviceKind: Hashable, Sendable {
    case router
    case computer
    case television
    case speaker
    case printer
    case storage
    case homeAutomation
    case generic

    var iconName: String {
        switch self {
        case .router: "wifi.router"
        case .computer: "desktopcomputer"
        case .television: "appletv"
        case .speaker: "hifispeaker"
        case .printer: "printer"
        case .storage: "externaldrive.connected.to.line.below"
        case .homeAutomation: "homekit"
        case .generic: "network"
        }
    }

    /// Picks the kind from the hardware models and service types a host advertises, most
    /// specific first. Apple devices name their model in the AirPlay TXT record, which tells a
    /// HomePod from an Apple TV when both advertise the same services.
    static func infer(from serviceTypes: Set<String>, models: Set<String> = []) -> LocalNetworkDeviceKind {
        func advertises(_ types: String...) -> Bool {
            types.contains { serviceTypes.contains($0) }
        }
        func model(startsWith prefixes: String...) -> Bool {
            models.contains { model in prefixes.contains { model.hasPrefix($0) } }
        }
        if model(startsWith: "AudioAccessory") {
            return .speaker
        }
        if model(startsWith: "AppleTV") {
            return .television
        }
        if model(startsWith: "Mac", "iMac") {
            return .computer
        }
        if advertises("_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp") {
            return .printer
        }
        if advertises("_smb._tcp", "_sftp-ssh._tcp", "_ssh._tcp", "_rfb._tcp") {
            return .computer
        }
        if advertises("_afpovertcp._tcp", "_nfs._tcp", "_adisk._tcp") {
            return .storage
        }
        if advertises("_airplay._tcp") {
            return .television
        }
        if advertises("_raop._tcp") {
            return .speaker
        }
        if advertises("_hap._tcp", "_matter._tcp", "_shelly._tcp", "_meshcop._udp") {
            return .homeAutomation
        }
        return .generic
    }
}

/// One host on the local network with everything it advertises.
nonisolated struct LocalNetworkDevice: Hashable, Sendable, Identifiable {
    /// The mDNS host name, which is what groups services into a device.
    let host: String

    /// The IPv4 address, when any of the host's services resolved one.
    let address: String?

    /// The name shown to the user: the instance name its services agree on, else the host label.
    let name: String

    /// Every service the host advertises, sorted by type.
    let services: [LocalNetworkService]

    let kind: LocalNetworkDeviceKind

    var id: String {
        host
    }

    /// The advertised web interface, preferring plain HTTP because local devices rarely carry
    /// certificates a browser trusts.
    var webService: LocalNetworkService? {
        services.first { $0.type == "_http._tcp" } ?? services.first { $0.type == "_https._tcp" }
    }

    /// The URL to open for this device: its advertised web interface, or a plain HTTP attempt at
    /// its address for devices that advertise none.
    var url: URL? {
        webService?.url ?? URL(string: "http://\(address ?? host)")
    }

    /// Distinct service types, in the order the services are sorted.
    var serviceTypes: [String] {
        var seen: Set<String> = []
        return services.compactMap { seen.insert($0.type).inserted ? $0.type : nil }
    }

    /// Groups services into devices: first by host, then hosts that resolved to the same
    /// address merge, because a device that speaks several protocols (a Shelly plug on both
    /// Matter and HTTP) registers one host name per protocol stack.
    ///
    /// - Parameter gatewayAddress: The router's address, so the matching device is marked as such.
    static func group(_ services: [LocalNetworkService], gatewayAddress: String?) -> [LocalNetworkDevice] {
        let byHost = Dictionary(grouping: services) { $0.host.lowercased() }
        let byDevice = Dictionary(grouping: byHost.values) { hostServices -> String in
            hostServices.compactMap(\.address).first ?? hostServices[0].host.lowercased()
        }

        return byDevice.values.map { hostGroups -> LocalNetworkDevice in
            let sorted = hostGroups.flatMap(\.self).sorted { $0.type < $1.type }
            let address = sorted.compactMap(\.address).first
            let host = sorted.first { $0.address == address }?.host ?? sorted[0].host
            let kind: LocalNetworkDeviceKind = address != nil && address == gatewayAddress
                ? .router
                : .infer(from: Set(sorted.map(\.type)), models: Set(sorted.compactMap(\.model)))

            return LocalNetworkDevice(
                host: host,
                address: address,
                name: displayName(for: sorted, host: host),
                services: sorted,
                kind: kind,
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The instance name the device's services vote for. Web interfaces count double because
    /// they carry the name a person set; the `MAC@` prefix AirPlay audio (`_raop`) puts in front
    /// of its name is dropped; bare hexadecimal ids such as Matter node names only win when
    /// nothing else is offered; the host label is the last resort.
    private static func displayName(for services: [LocalNetworkService], host: String) -> String {
        var votes: [String: Int] = [:]
        for service in services {
            var name = service.name
            if service.type == "_raop._tcp", let at = name.firstIndex(of: "@") {
                name = String(name[name.index(after: at)...])
            }
            guard !name.isEmpty else { continue }
            let weight = service.webScheme != nil ? 2 : 1
            votes[name, default: 0] += name.isBareIdentifier ? weight - 1 : weight
        }

        let best = votes.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }
        if let best {
            return best.key
        }
        return host.hasSuffix(".local") ? String(host.dropLast(".local".count)) : host
    }
}

private nonisolated extension String {
    /// A machine id of hexadecimal digits and dashes, such as a Matter node name.
    var isBareIdentifier: Bool {
        count >= 12 && allSatisfy { $0.isHexDigit || $0 == "-" }
    }
}

/// What the local network looked like at one moment: the gateway and the devices around it.
nonisolated struct LocalNetworkSnapshot: Sendable {
    let gateway: LocalNetworkGateway?
    let services: [LocalNetworkService]
    let devices: [LocalNetworkDevice]
    let capturedAt: ContinuousClock.Instant

    init(gateway: LocalNetworkGateway?, services: [LocalNetworkService], capturedAt: ContinuousClock.Instant) {
        self.gateway = gateway
        self.services = services
        self.devices = LocalNetworkDevice.group(services, gatewayAddress: gateway?.address)
        self.capturedAt = capturedAt
    }

    static let empty = LocalNetworkSnapshot(gateway: nil, services: [], capturedAt: .now)

    /// The device that is the router, when it advertises anything.
    var gatewayDevice: LocalNetworkDevice? {
        devices.first { $0.kind == .router }
    }
}

/// Anything that can describe the local network, so the Command Lens provider can be tested
/// against a fixed snapshot instead of the live network.
nonisolated protocol LocalNetworkSnapshotSource: Sendable {
    func snapshot() async -> LocalNetworkSnapshot
}

/// Caches the gateway and the Bonjour-advertised devices of the local network.
///
/// Reads are instant: the first call returns the gateway alone, read synchronously from the
/// system configuration store, and starts a Bonjour browse in the background; later calls
/// return the cached snapshot and refresh it in the background once it is older than
/// ``Constants/freshness``. Nothing here scans address ranges or opens connections. The
/// gateway comes from the routing configuration and the devices from mDNS answers that
/// `mDNSResponder` already caches for every app on the Mac.
///
/// The first browse raises the macOS local-network permission prompt, so the app delegate
/// calls ``snapshot()`` once at launch rather than letting the prompt interrupt typing.
actor LocalNetworkDirectory: LocalNetworkSnapshotSource {
    private enum Constants {
        /// How long a snapshot serves reads before a background refresh is scheduled.
        static let freshness: Duration = .seconds(120)

        /// Freshness of a snapshot that found no devices. A browse comes back empty while the
        /// local-network permission prompt is still open, so the next lens query retries soon.
        static let emptyFreshness: Duration = .seconds(10)

        /// How long one Bonjour browse listens for answers.
        static let browseWindow: Duration = .milliseconds(1_500)
    }

    private var cached: LocalNetworkSnapshot?
    private var refreshTask: Task<LocalNetworkSnapshot, Never>?

    func snapshot() -> LocalNetworkSnapshot {
        if let cached {
            let freshness = cached.services.isEmpty ? Constants.emptyFreshness : Constants.freshness
            if ContinuousClock.now - cached.capturedAt > freshness {
                scheduleRefresh()
            }
            return cached
        }

        let initial = LocalNetworkSnapshot(
            gateway: DefaultGatewayProbe.current(),
            services: [],
            capturedAt: .now,
        )
        cached = initial
        scheduleRefresh()
        return initial
    }

    /// Browses the network now and returns the result, joining a refresh already under way.
    func refresh() async -> LocalNetworkSnapshot {
        scheduleRefresh()
        guard let refreshTask else { return snapshot() }
        return await refreshTask.value
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else { return }

        refreshTask = Task(name: "Local network directory refresh") {
            let gateway = DefaultGatewayProbe.current()
            let services = await BonjourServiceBrowser.browse(window: Constants.browseWindow)
            let snapshot = LocalNetworkSnapshot(gateway: gateway, services: services, capturedAt: .now)
            Logger.debug(
                "Local network: gateway \(gateway?.address ?? "none"), \(services.count) services on \(snapshot.devices.count) devices",
                category: Logger.network,
            )
            cached = snapshot
            refreshTask = nil
            return snapshot
        }
    }
}

/// Reads the default IPv4 gateway from the system configuration store.
nonisolated enum DefaultGatewayProbe {
    static func current() -> LocalNetworkGateway? {
        guard let store = SCDynamicStoreCreate(nil, "Refrax" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = global["Router"] as? String
        else { return nil }

        let interfaceName = (global["PrimaryInterface"] as? String).flatMap(localizedInterfaceName)
        return LocalNetworkGateway(address: router, interfaceName: interfaceName)
    }

    private static func localizedInterfaceName(forBSDName bsdName: String) -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }

        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
            return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
        }
        return nil
    }
}
