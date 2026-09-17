import Foundation

/// Suggests the router and the web interfaces of devices on the local network.
///
/// Typing the start of a private address (`192.168`) lists the default gateway first,
/// then every Bonjour-advertised device whose address starts the same way; typing part of a
/// device name (`shelly`), or `router` / `gateway`, matches by name. The data comes from
/// ``LocalNetworkDirectory``, which never scans the network.
struct LocalNetworkProvider: CommandLensSuggestionProvider {
    let id = "local-network"
    let priority = 40
    let groupHeader: String? = "Local Network"
    let maxSuggestions = 5

    private let source: any LocalNetworkSnapshotSource

    private enum Constants {
        /// Shortest name fragment worth matching; shorter ones match nearly every device.
        static let minimumNameQueryLength = 3
        static let gatewayKeywords = ["router", "gateway"]
    }

    /// What the user typed, reduced to the part that can match an address or a name.
    struct Query: Equatable {
        let text: String

        /// The query starts with a digit, so it is compared against addresses by prefix.
        let isAddress: Bool

        init?(input: String) {
            var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
                text = String(text.dropFirst(scheme.count))
            }
            guard let first = text.first else { return nil }

            let isAddress = first.isNumber
            guard isAddress || text.count >= Constants.minimumNameQueryLength else { return nil }

            self.text = text
            self.isAddress = isAddress
        }

        func matches(gateway: LocalNetworkGateway, name: String?) -> Bool {
            if isAddress {
                return gateway.address.hasPrefix(text)
            }
            return Constants.gatewayKeywords.contains { $0.hasPrefix(text) }
                || name?.lowercased().contains(text) == true
        }

        func matches(device: LocalNetworkDevice) -> Bool {
            if isAddress {
                return device.webService?.displayURL?.hasPrefix(text) == true
            }
            return device.name.lowercased().contains(text) || device.host.lowercased().contains(text)
        }
    }

    init(source: any LocalNetworkSnapshotSource) {
        self.source = source
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        guard !context.isEmptyInput, context.selectedSearchEngine == nil else { return false }
        return Query(input: context.input) != nil
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        guard let query = Query(input: context.input) else { return [] }
        let snapshot = await source.snapshot()

        var suggestions: [CommandLensSuggestion] = []

        let gatewayDevice = snapshot.gatewayDevice
        if let gateway = snapshot.gateway,
           query.matches(gateway: gateway, name: gatewayDevice?.name),
           let suggestion = makeGatewaySuggestion(gateway, device: gatewayDevice) {
            suggestions.append(suggestion)
        }

        let devices = snapshot.devices
            .filter { $0.kind != .router && $0.webService != nil && query.matches(device: $0) }
            .prefix(maxSuggestions - suggestions.count)

        for device in devices {
            if let suggestion = makeDeviceSuggestion(device) {
                suggestions.append(suggestion)
            }
        }

        return suggestions
    }

    private func makeGatewaySuggestion(
        _ gateway: LocalNetworkGateway,
        device: LocalNetworkDevice?,
    ) -> CommandLensSuggestion? {
        guard let url = device?.webService?.url ?? gateway.url else { return nil }

        let text: String
        var details: [String]
        if let device {
            text = device.name
            details = [device.webService?.displayURL ?? gateway.address]
        } else {
            text = gateway.address
            details = ["Default gateway"]
        }
        if let interfaceName = gateway.interfaceName {
            details.append(interfaceName)
        }

        return CommandLensSuggestion(
            type: .localDevice(.gateway),
            text: text,
            description: details.joined(separator: " · "),
            iconName: LocalNetworkDeviceKind.router.iconName,
            groupHeader: groupHeader,
            isRemovable: false,
            keywordAction: nil,
            url: url,
        )
    }

    private func makeDeviceSuggestion(_ device: LocalNetworkDevice) -> CommandLensSuggestion? {
        guard let service = device.webService, let url = service.url, let displayURL = service.displayURL else { return nil }

        return CommandLensSuggestion(
            type: .localDevice(.service),
            text: device.name,
            description: displayURL,
            iconName: device.kind.iconName,
            groupHeader: groupHeader,
            isRemovable: false,
            keywordAction: nil,
            url: url,
        )
    }
}
