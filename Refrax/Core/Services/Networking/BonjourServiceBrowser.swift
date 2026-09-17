import dnssd
import Foundation

/// Collects every Bonjour service advertised on the local network.
///
/// One call is one browse: it asks the meta-service `_services._dns-sd._udp` which service
/// types are present, browses each of them plus the two web types, resolves every instance to
/// a host, port, and TXT path, and looks up the host's IPv4 address, all within one bounded
/// window. `mDNSResponder` answers from its cache, so on a warm network everything arrives
/// within a few hundred milliseconds and the window mostly covers slow responders.
nonisolated enum BonjourServiceBrowser {
    /// The service types browsed before the meta-query answers, so web interfaces are never
    /// missed even on a network whose meta-query is slow.
    static let webServiceTypes = ["_http._tcp", "_https._tcp"]

    /// Service types browsed on every run regardless of what the meta-query reports, so the
    /// map still shows computers, media players, printers, and smart-home hubs when the
    /// meta-query answers late or is withheld.
    static let wellKnownServiceTypes = [
        "_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_hap._tcp", "_matter._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_rfb._tcp", "_adisk._tcp", "_nfs._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
        "_googlecast._tcp", "_spotify-connect._tcp", "_sonos._tcp", "_hue._tcp", "_shelly._tcp", "_device-info._tcp",
    ]

    static let metaServiceType = "_services._dns-sd._udp"

    static func browse(window: Duration) async -> [LocalNetworkService] {
        await withCheckedContinuation { continuation in
            BrowseSession(window: window) { services in
                continuation.resume(returning: services)
            }.start()
        }
    }
}

/// One bounded browse over the `dns_sd` C API.
///
/// Every `DNSServiceRef` is bound to ``queue`` with `DNSServiceSetDispatchQueue`, so all
/// callbacks and all state mutation happen on that one serial queue. Callbacks receive the
/// session (or a ``ResolveContext`` it owns) through the C context pointer, unretained; the
/// closure scheduled by ``start()`` keeps the session alive until ``finish()`` has
/// deallocated every ref, after which no callback can arrive.
private final nonisolated class BrowseSession: @unchecked Sendable {
    /// Ties one resolve/address-lookup chain back to the session and the service it belongs to.
    final nonisolated class ResolveContext {
        unowned let session: BrowseSession
        let key: String

        init(session: BrowseSession, key: String) {
            self.session = session
            self.key = key
        }
    }

    private struct PendingService {
        let name: String
        let type: String
        var host: String?
        var port: UInt16 = 0
        var path = "/"
        var model: String?
        var address: String?
    }

    /// Answers on the loopback interface describe this Mac's own services with a `127.x`
    /// address; the same services also answer on the LAN interface with the real one.
    private let loopbackInterfaceIndex = if_nametoindex("lo0")

    private let queue = DispatchQueue(label: "website.refrax.browser.bonjour-browse")
    private let window: Duration
    private let completion: @Sendable ([LocalNetworkService]) -> Void
    private var serviceRefs: [DNSServiceRef] = []
    private var resolveContexts: [ResolveContext] = []
    private var browsedTypes: Set<String> = []
    private var pending: [String: PendingService] = [:]
    private var isFinished = false

    init(window: Duration, completion: @escaping @Sendable ([LocalNetworkService]) -> Void) {
        self.window = window
        self.completion = completion
    }

    func start() {
        queue.async { self.startBrowsing() }
        let nanoseconds = window.components.seconds * 1_000_000_000 + window.components.attoseconds / 1_000_000_000
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { self.finish() }
    }

    // MARK: - Browse

    private func startBrowsing() {
        let context = Unmanaged.passUnretained(self).toOpaque()

        var metaRef: DNSServiceRef?
        let error = DNSServiceBrowse(&metaRef, 0, 0, BonjourServiceBrowser.metaServiceType, nil, metaReply, context)
        if error == kDNSServiceErr_NoError, let metaRef {
            DNSServiceSetDispatchQueue(metaRef, queue)
            serviceRefs.append(metaRef)
        } else {
            Logger.debug("Bonjour meta-query unavailable (\(error)); relying on the well-known types", category: Logger.network)
        }

        for type in BonjourServiceBrowser.webServiceTypes + BonjourServiceBrowser.wellKnownServiceTypes {
            browse(type: type)
        }
    }

    private func browse(type: String) {
        guard !isFinished, !browsedTypes.contains(type) else { return }
        browsedTypes.insert(type)

        var ref: DNSServiceRef?
        let error = DNSServiceBrowse(&ref, 0, 0, type, nil, browseReply, Unmanaged.passUnretained(self).toOpaque())
        guard error == kDNSServiceErr_NoError, let ref else {
            Logger.error("Bonjour browse for \(type) failed to start: \(error)", category: Logger.network)
            return
        }
        DNSServiceSetDispatchQueue(ref, queue)
        serviceRefs.append(ref)
    }

    /// A meta-query answer names a type as `name: "_airplay", type: "_tcp.local."`.
    private func serviceTypeFound(name: String, type: String) {
        guard let transport = type.split(separator: ".").first, transport == "_tcp" || transport == "_udp" else { return }
        browse(type: "\(name).\(transport)")
    }

    private func serviceFound(name: String, type: String, domain: String, interfaceIndex: UInt32) {
        guard !isFinished, interfaceIndex != loopbackInterfaceIndex else { return }
        let normalizedType = type.hasSuffix(".") ? String(type.dropLast()) : type
        let key = "\(name).\(normalizedType)"
        guard pending[key] == nil else { return }

        pending[key] = PendingService(name: name, type: normalizedType)

        let resolveContext = ResolveContext(session: self, key: key)
        resolveContexts.append(resolveContext)

        var ref: DNSServiceRef?
        let error = DNSServiceResolve(
            &ref, 0, interfaceIndex, name, type, domain,
            resolveReply, Unmanaged.passUnretained(resolveContext).toOpaque(),
        )
        guard error == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, queue)
        serviceRefs.append(ref)
    }

    // MARK: - Resolve

    private func serviceResolved(
        key: String,
        host: String,
        port: UInt16,
        path: String,
        model: String?,
        interfaceIndex _: UInt32,
        context: ResolveContext,
    ) {
        guard !isFinished, pending[key] != nil else { return }
        pending[key]?.host = host.hasSuffix(".") ? String(host.dropLast()) : host
        pending[key]?.port = port
        pending[key]?.path = path
        pending[key]?.model = model

        var ref: DNSServiceRef?
        let error = DNSServiceGetAddrInfo(
            &ref, 0, 0, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host,
            addressReply, Unmanaged.passUnretained(context).toOpaque(),
        )
        guard error == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, queue)
        serviceRefs.append(ref)
    }

    /// Keeps the most local address a host answers with: a LAN address beats a VPN or
    /// carrier-grade NAT one (Tailscale's `100.64/10`), which beats loopback.
    private func addressResolved(key: String, address: String) {
        guard !isFinished, pending[key] != nil else { return }
        let current = pending[key]?.address
        if current == nil || Self.locality(of: address) > Self.locality(of: current ?? "") {
            pending[key]?.address = address
        }
    }

    private static func locality(of address: String) -> Int {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return 0 }
        if octets[0] == 127 {
            return 0
        }
        if octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16 ... 31).contains(octets[1])) {
            return 2
        }
        return 1
    }

    // MARK: - Finish

    private func finish() {
        guard !isFinished else { return }
        isFinished = true

        for ref in serviceRefs {
            DNSServiceRefDeallocate(ref)
        }
        serviceRefs.removeAll()

        let services = pending.values.compactMap { service -> LocalNetworkService? in
            guard let host = service.host else { return nil }
            return LocalNetworkService(
                name: service.name,
                type: service.type,
                host: host,
                address: service.address,
                port: service.port,
                path: service.path,
                model: service.model,
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        completion(services)
    }

    // MARK: - C Callbacks

    private let metaReply: DNSServiceBrowseReply = { _, flags, _, error, name, type, _, context in
        guard error == kDNSServiceErr_NoError, (flags & kDNSServiceFlagsAdd) != 0, let name, let type, let context else { return }

        let session = Unmanaged<BrowseSession>.fromOpaque(context).takeUnretainedValue()
        session.serviceTypeFound(name: String(cString: name), type: String(cString: type))
    }

    private let browseReply: DNSServiceBrowseReply = { _, flags, interfaceIndex, error, name, type, domain, context in
        guard error == kDNSServiceErr_NoError else {
            Logger.error("Bonjour browse reported error \(error)", category: Logger.network)
            return
        }
        guard (flags & kDNSServiceFlagsAdd) != 0, let name, let type, let domain, let context else { return }

        let session = Unmanaged<BrowseSession>.fromOpaque(context).takeUnretainedValue()
        session.serviceFound(
            name: String(cString: name),
            type: String(cString: type),
            domain: String(cString: domain),
            interfaceIndex: interfaceIndex,
        )
    }

    private let resolveReply: DNSServiceResolveReply = { _, _, interfaceIndex, error, _, host, port, txtLength, txtRecord, context in
        guard error == kDNSServiceErr_NoError, let host, let context else { return }

        let resolveContext = Unmanaged<ResolveContext>.fromOpaque(context).takeUnretainedValue()
        resolveContext.session.serviceResolved(
            key: resolveContext.key,
            host: String(cString: host),
            port: UInt16(bigEndian: port),
            path: BrowseSession.path(fromTXTRecord: txtRecord, length: txtLength),
            model: BrowseSession.txtValue("model", in: txtRecord, length: txtLength),
            interfaceIndex: interfaceIndex,
            context: resolveContext,
        )
    }

    private let addressReply: DNSServiceGetAddrInfoReply = { _, flags, _, error, _, address, _, context in
        guard error == kDNSServiceErr_NoError,
              (flags & kDNSServiceFlagsAdd) != 0,
              let address, let context,
              address.pointee.sa_family == sa_family_t(AF_INET)
        else { return }

        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inet in
            var ipv4 = inet.pointee.sin_addr
            _ = inet_ntop(AF_INET, &ipv4, &text, socklen_t(INET_ADDRSTRLEN))
        }

        let ipv4Text = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let resolveContext = Unmanaged<ResolveContext>.fromOpaque(context).takeUnretainedValue()
        resolveContext.session.addressResolved(key: resolveContext.key, address: ipv4Text)
    }

    /// The `path` key of an `_http._tcp` TXT record, normalized to an absolute path.
    private static func path(fromTXTRecord record: UnsafePointer<UInt8>?, length: UInt16) -> String {
        guard let path = txtValue("path", in: record, length: length) else { return "/" }
        return path.hasPrefix("/") ? path : "/" + path
    }

    private static func txtValue(_ key: String, in record: UnsafePointer<UInt8>?, length: UInt16) -> String? {
        guard let record, length > 0 else { return nil }

        var valueLength: UInt8 = 0
        guard let value = TXTRecordGetValuePtr(length, record, key, &valueLength), valueLength > 0 else { return nil }

        return String(decoding: UnsafeRawBufferPointer(start: value, count: Int(valueLength)), as: UTF8.self)
    }
}
