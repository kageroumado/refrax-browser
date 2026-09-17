import SwiftUI

/// A map of the local network: the router in the middle, every advertised device around it.
///
/// Styled like the sidebar's Keyboard Shortcuts card: one glass bubble with a headline label.
struct LocalDevicesView: View {
    let model: LocalDevicesModel

    private enum Layout {
        static let padding: CGFloat = 16
        static let cornerRadius: CGFloat = 16
        static let windowInset: CGFloat = 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            LocalDevicesMapView(
                gateway: model.snapshot.gateway,
                gatewayDevice: model.snapshot.gatewayDevice,
                devices: model.snapshot.devices.filter { $0.kind != .router },
                isRefreshing: model.isRefreshing,
                onOpen: model.open,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(Layout.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cornerRadius))
        .padding(Layout.windowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack {
            Label("Local Devices", systemImage: "network")
                .font(.headline)

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .disabled(model.isRefreshing)
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var footerText: String {
        let count = model.snapshot.devices.count
        let devices = count == 1 ? "1 device" : "\(count) devices"
        return "\(devices) found over Bonjour · click one to open its web interface"
    }
}

/// Lays the router out in the center and the devices on rings around it.
///
/// Each ring holds as many nodes as its circumference fits without overlap, so a large network
/// grows outward and the map scrolls rather than crowding; a small one centers in the window.
private struct LocalDevicesMapView: View {
    let gateway: LocalNetworkGateway?
    let gatewayDevice: LocalNetworkDevice?
    let devices: [LocalNetworkDevice]
    let isRefreshing: Bool
    let onOpen: (LocalNetworkDevice) -> Void

    private enum Layout {
        static let nodeWidth: CGFloat = 124
        static let nodeHeight: CGFloat = 96
        static let gatewayClearance: CGFloat = 150
        static let ringSpacing: CGFloat = 108
        static let margin: CGFloat = 12
        static let nodeGap: CGFloat = 16
    }

    var body: some View {
        GeometryReader { viewport in
            let plan = RingPlan(count: devices.count)
            let size = CGSize(
                width: max(viewport.size.width, plan.diameter),
                height: max(viewport.size.height, plan.diameter),
            )
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let positions = plan.positions(around: center)

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack {
                    Path { path in
                        for position in positions {
                            path.move(to: center)
                            path.addLine(to: position)
                        }
                    }
                    .stroke(.secondary.opacity(0.25), lineWidth: 1)

                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        DeviceNode(device: device, onOpen: onOpen)
                            .frame(width: Layout.nodeWidth)
                            .position(positions[index])
                    }

                    gatewayNode
                        .position(center)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    @ViewBuilder
    private var gatewayNode: some View {
        if let gateway {
            GatewayNode(gateway: gateway, device: gatewayDevice, onOpen: onOpen)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .circle)
                Text(isRefreshing ? "Looking for the router…" : "Router unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Ring radii and per-ring counts for a number of nodes.
    private struct RingPlan {
        let rings: [(radius: CGFloat, count: Int)]

        init(count: Int) {
            var rings: [(radius: CGFloat, count: Int)] = []
            var remaining = count
            var radius = Layout.gatewayClearance
            while remaining > 0 {
                let capacity = max(1, Int((2 * .pi * radius) / (Layout.nodeWidth + Layout.nodeGap)))
                let placed = min(remaining, capacity)
                rings.append((radius, placed))
                remaining -= placed
                radius += Layout.ringSpacing
            }
            self.rings = rings
        }

        /// Diameter of the whole map including the outermost nodes.
        var diameter: CGFloat {
            guard let outer = rings.last else { return Layout.gatewayClearance * 2 }
            return (outer.radius + Layout.nodeHeight / 2 + Layout.margin) * 2
        }

        /// Nodes on each ring start at the top; odd rings rotate by half a slot so their nodes
        /// sit between the ring inside them.
        func positions(around center: CGPoint) -> [CGPoint] {
            var positions: [CGPoint] = []
            for (index, ring) in rings.enumerated() {
                let slot = 2 * CGFloat.pi / CGFloat(ring.count)
                let start = -CGFloat.pi / 2 + (index.isMultiple(of: 2) ? 0 : slot / 2)
                for item in 0 ..< ring.count {
                    let angle = start + CGFloat(item) * slot
                    positions.append(CGPoint(x: center.x + cos(angle) * ring.radius, y: center.y + sin(angle) * ring.radius))
                }
            }
            return positions
        }
    }
}

private struct GatewayNode: View {
    let gateway: LocalNetworkGateway
    let device: LocalNetworkDevice?
    let onOpen: (LocalNetworkDevice) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onOpen(device ?? LocalNetworkDevice(host: gateway.address, address: gateway.address, name: gateway.address, services: [], kind: .router))
        } label: {
            VStack(spacing: 4) {
                Image(systemName: LocalNetworkDeviceKind.router.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.tint(tint), in: .circle)

                Text(device?.name ?? gateway.address)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Opens \(device?.webService?.displayURL ?? gateway.address)")
    }

    private var tint: Color {
        isHovering ? Color.appAccentColor.opacity(0.35) : Color.appAccentColor.opacity(0.15)
    }

    private var detail: String {
        [device != nil ? gateway.address : nil, gateway.interfaceName]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

private struct DeviceNode: View {
    let device: LocalNetworkDevice
    let onOpen: (LocalNetworkDevice) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onOpen(device)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: device.kind.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(isHovering ? Color.appAccentColor.opacity(0.3) : .clear), in: .circle)

                Text(device.name)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)

                Text(device.address ?? device.host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }

    private var helpText: String {
        if let displayURL = device.webService?.displayURL {
            return "Opens \(displayURL)"
        }
        return "Advertises \(device.serviceTypes.joined(separator: ", ")) · tries http://\(device.address ?? device.host)"
    }
}
