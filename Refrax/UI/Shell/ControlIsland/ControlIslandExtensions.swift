import SwiftUI

/// The Extensions popover from the rail: each extension's action for the active tab, with its
/// icon, title and badge. Clicking one performs it, and its popup opens beside the rail.
struct ControlIslandExtensions: View {
    @Binding var isPresented: Bool
    /// The rail row the popover hangs from, in the window's SwiftUI global coordinates.
    let anchor: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(ExtensionManager.self) private var extensions

    private enum Layout {
        static let width: CGFloat = 280
        static let maximumHeight: CGFloat = 420
        static let padding: CGFloat = 8
        static let spacing: CGFloat = 2
        static let iconSize: CGFloat = 18
        static let rowPadding: CGFloat = 6
    }

    var body: some View {
        let entries = extensions.actionEntries(for: windowState.activeTab)
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text("Extensions")
                .font(.headline)
                .padding(Layout.rowPadding)
            ScrollView {
                VStack(spacing: Layout.spacing) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .frame(maxHeight: Layout.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            extensions.markActionBadgesRead(in: windowState.activeTab)
        }
    }

    private func row(_ entry: ExtensionActionEntry) -> some View {
        Button {
            isPresented = false
            extensions.performAction(
                contextID: entry.id,
                in: windowState.activeTab,
                anchor: ActionPopupAnchor(window: windowState.window, rect: anchor),
            )
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let icon = entry.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                Text(entry.appearance.label.isEmpty ? entry.name : entry.appearance.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !entry.appearance.badgeText.isEmpty {
                    ExtensionBadge(text: entry.appearance.badgeText)
                }
            }
        }
        .buttonStyle(.pageMenuRow)
        .disabled(!entry.appearance.isEnabled)
        .help(entry.name)
    }
}

/// The rail's Extensions row: a puzzle piece, with a dot while an action shows a badge the
/// user has not seen. It opens ``ControlIslandExtensions``.
struct ControlIslandExtensionsControl: View {
    let item: ControlIslandItem
    let opensLeft: Bool
    @Environment(WindowState.self) private var windowState
    @Environment(ExtensionManager.self) private var extensions
    @State private var isPresented = false
    @State private var rowFrame = CGRect.zero

    private enum Layout {
        static let dotSize: CGFloat = 6
    }

    var body: some View {
        let showsDot = extensions.hasUnreadActionBadge(in: windowState.activeTab)
        Button {
            isPresented.toggle()
        } label: {
            ControlIslandRow {
                Image(systemName: item.symbol)
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle()
                                .fill(Color.appAccentColor)
                                .frame(width: Layout.dotSize, height: Layout.dotSize)
                                .offset(x: Layout.dotSize / 2, y: -Layout.dotSize / 2)
                        }
                    }
            }
        }
        // The row appears only while an extension has an action: a focusable view that comes
        // and goes beside the window's AppKit views and the page makes SwiftUI rebuild its
        // key-view loop, a walk that can spin forever, so it stays out of that loop.
        .focusable(false)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrame = $0 }
        .popover(isPresented: $isPresented, arrowEdge: opensLeft ? .leading : .trailing) {
            ControlIslandExtensions(isPresented: $isPresented, anchor: rowFrame)
                .readablePopoverBackground()
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(showsDot ? "New badge" : "")
        .railHelp("Extensions")
    }
}

/// An extension's badge text in a small capsule, as toolbars show it.
struct ExtensionBadge: View {
    let text: String

    private enum Layout {
        static let fontSize: CGFloat = 10
        static let horizontalPadding: CGFloat = 5
        static let verticalPadding: CGFloat = 1
    }

    var body: some View {
        Text(text)
            .font(.system(size: Layout.fontSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(Capsule().fill(Color.appAccentColor))
            .accessibilityLabel("Badge \(text)")
    }
}
