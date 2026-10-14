import AppKit
import SwiftUI

/// The window-wide layer the canvas appears in, above the browser and below Command Lens.
///
/// While the canvas is open it fills the whole window.
struct TabCanvasLayer: View {
    @Environment(TabCanvasManager.self) private var manager
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if manager.isActive {
                TabCanvasView()
            }
            if let hint = manager.hint {
                CanvasHintLabel(text: hint.text)
                    .padding(.bottom, manager.isActive ? Layout.hintAboveToolbar : Layout.hintBottomPadding)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: manager.hint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }

    private enum Layout {
        static let hintBottomPadding: CGFloat = 28
        static let hintAboveToolbar: CGFloat = 80
    }
}

/// A one-time hint floating above the bottom edge.
private struct CanvasHintLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
    }
}

/// The tab canvas: the desk, and the floating controls over it.
struct TabCanvasView: View {
    @Environment(TabCanvasManager.self) private var manager

    var body: some View {
        ZStack(alignment: .bottom) {
            TabCanvasBoard(
                tabs: manager.tabs,
                tileFrames: manager.tileFrames,
                snapshots: manager.snapshots,
                zones: manager.zones,
                magnets: manager.magnets,
                selectedTabIDs: manager.selectedTabIDs,
                zoomRequest: manager.zoomRequest,
                closeRequest: manager.closeRequest,
                tileSize: manager.tileSize,
                deskSize: manager.deskSize,
            )

            CanvasToolbar()
                .padding(.bottom, Layout.toolbarBottomPadding)
                .opacity(manager.isOpeningInteractively || manager.isPanningFromPage ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: manager.isOpeningInteractively || manager.isPanningFromPage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum Layout {
        static let toolbarBottomPadding: CGFloat = 20
    }
}

// MARK: - Toolbar

/// The space's tab count, actions on the current selection, plus fit-everything.
private struct CanvasToolbar: View {
    @Environment(TabCanvasManager.self) private var manager

    var body: some View {
        HStack(spacing: Layout.spacing) {
            toolbarButton("Back to Tab", systemImage: "arrow.down.right.and.arrow.up.left") { manager.close() }

            Divider().frame(height: Layout.dividerHeight)

            if manager.selectedTabIDs.isEmpty {
                Text(tabCount)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, Layout.spacing / 2)

                Divider().frame(height: Layout.dividerHeight)
            } else {
                Text("\(manager.selectedTabIDs.count) of \(tabCount) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.trailing, Layout.spacing / 2)

                toolbarButton("Zoom", systemImage: "arrow.up.left.and.arrow.down.right") { manager.zoomToSelection() }
                toolbarButton(manager.selectionIsCompact ? "Previews" : "Compact", systemImage: manager.selectionIsCompact ? "rectangle" : "rectangle.compress.vertical") { manager.toggleSelectedPreviews() }
                    .disabled(manager.isSettling)
                toolbarButton("Group", systemImage: "rectangle.dashed") { manager.groupSelected() }
                toolbarButton("Magnet", systemImage: "circle.hexagongrid.circle") { manager.makeMagnetFromSelected() }
                toolbarButton("Close", systemImage: "xmark.circle") { manager.closeSelected() }
                toolbarButton("Clear", systemImage: "lasso") { manager.clearSelection() }

                Divider().frame(height: Layout.dividerHeight)
            }

            toolbarButton("Zoom Out", systemImage: "minus.magnifyingglass") { manager.zoom(by: 1 / 1.2) }
                .help("Zoom out · Option-scroll")
            toolbarButton("Zoom In", systemImage: "plus.magnifyingglass") { manager.zoom(by: 1.2) }
                .help("Zoom in · Option-scroll")
            toolbarButton("Fit", systemImage: "square.grid.2x2") { manager.zoomToEverything() }
                .help("Fit every tab in view")
            FloatingArrangeButton(arrowEdge: .top)
                .buttonStyle(.plain)
                .font(.callout)
                .padding(.horizontal, Layout.buttonPadding)
                .padding(.vertical, Layout.buttonPadding / 2)
                .help("Arrange the floating tabs of this space")
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: Layout.shadowRadius, y: Layout.shadowY)
    }

    /// The space's tabs on the desk: "6 tabs".
    private var tabCount: String {
        let count = manager.tabs.count
        return "\(count) \(count == 1 ? "tab" : "tabs")"
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .padding(.horizontal, Layout.buttonPadding)
                .padding(.vertical, Layout.buttonPadding / 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private enum Layout {
        static let spacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 8
        static let buttonPadding: CGFloat = 8
        static let dividerHeight: CGFloat = 18
        static let shadowRadius: CGFloat = 20
        static let shadowY: CGFloat = 6
    }
}

// MARK: - Board Representable

/// Hosts the zoomable AppKit board.
private struct TabCanvasBoard: NSViewRepresentable {
    @Environment(TabCanvasManager.self) private var manager
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    let tabs: [Tab]
    let tileFrames: [Tab.ID: CGRect]
    let snapshots: [Tab.ID: NSImage]
    let zones: [CanvasZone]
    let magnets: [CanvasMagnet]
    let selectedTabIDs: Set<Tab.ID>
    let zoomRequest: CanvasZoomRequest?
    let closeRequest: Int?
    let tileSize: CGSize
    let deskSize: CGSize

    func makeNSView(context: Context) -> TabCanvasScrollView {
        let view = TabCanvasScrollView(deskSize: manager.deskSize)
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.onWillEnter = { [weak manager] tab in manager?.prepareToEnter(tab) }
        view.onDismiss = { [weak manager] in manager?.dismiss(activating: nil) }
        view.onSettle = { [weak manager] frames in manager?.settleTiles(frames) }
        view.onTileDropped = { [weak manager] tabID in manager?.finishTileDrag(tabID) }
        view.onZoneMoved = { [weak manager] groupID, delta in manager?.moveZone(groupID, by: delta) }
        view.onMagnetMoved = { [weak manager] groupID, delta in manager?.moveMagnet(groupID, by: delta) }
        view.onMagnetActivated = { [weak manager] groupID in manager?.attract(groupID) }
        view.onLasso = { [weak manager] tabIDs in manager?.select(tabIDs) }
        view.onClearSelection = { [weak manager] in manager?.clearSelection() }
        view.onTogglePreview = { [weak manager] id, frame in manager?.togglePreview(id, at: frame) }
        view.onCameraChanged = { [weak manager] camera in manager?.updateTableCamera(camera) }
        manager.board = view
        reload(view)
        context.coordinator.lastZoomSerial = zoomRequest?.serial
        context.coordinator.lastCloseRequest = closeRequest
        view.livePageFrameInWindow = manager.livePageFrame
        if manager.isOpeningInteractively {
            view.beginOpening(focusedTile: manager.focusedTileFrame, desk: manager.deskBounds, from: manager.openingCameraFrame)
            view.setOpeningScale(manager.openingScale)
        } else {
            view.showTable(
                at: manager.openingCameraFrame ?? manager.floatingArea,
                trackingTarget: manager.isPanningFromPage,
                fitting: manager.openingFitRect,
            )
            view.pan(by: manager.pendingPan)
            if let zoom = manager.pendingCameraZoom {
                manager.pendingCameraZoom = nil
                view.zoom(by: zoom.factor, aboutWindowPoint: zoom.point)
            }
        }
        return view
    }

    func updateNSView(_ view: TabCanvasScrollView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        reload(view)
        if let zoomRequest, zoomRequest.serial != context.coordinator.lastZoomSerial {
            context.coordinator.lastZoomSerial = zoomRequest.serial
            view.fly(toFit: zoomRequest.rect)
        }
        if closeRequest != context.coordinator.lastCloseRequest {
            context.coordinator.lastCloseRequest = closeRequest
            view.dismissZoomingIntoFocusedTile()
        }
    }

    private func reload(_ view: TabCanvasScrollView) {
        view.impactSoundsEnabled = settings.canvasImpactSounds
        view.reload(CanvasBoardContent(
            tabs: tabs,
            frames: tileFrames,
            placements: Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, manager.tablePlacement(for: $0)) }),
            snapshots: snapshots,
            zones: zones,
            magnets: magnets,
            selectedTabIDs: selectedTabIDs,
            focusedTabID: manager.focusedTabID,
            tileSize: tileSize,
            deskSize: deskSize,
        ))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastZoomSerial: Int?
        var lastCloseRequest: Int?
    }
}

/// Everything the board needs to draw one state.
struct CanvasBoardContent {
    let tabs: [Tab]
    let frames: [Tab.ID: CGRect]
    var placements: [Tab.ID: FloatingTabPlacement] = [:]
    let snapshots: [Tab.ID: NSImage]
    let zones: [CanvasZone]
    let magnets: [CanvasMagnet]
    let selectedTabIDs: Set<Tab.ID>
    let focusedTabID: Tab.ID?
    let tileSize: CGSize
    let deskSize: CGSize
}
