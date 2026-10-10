import AppKit
import SwiftUI

/// The tab canvas overlay: covers the content area while `TabCanvasManager.isActive`.
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
                tileSize: manager.tileSize,
                deskSize: manager.deskSize,
            )

            CanvasToolbar()
                .padding(.bottom, Layout.toolbarBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum Layout {
        static let toolbarBottomPadding: CGFloat = 20
    }
}

// MARK: - Toolbar

/// Actions on the current selection, plus fit-everything.
private struct CanvasToolbar: View {
    @Environment(TabCanvasManager.self) private var manager

    var body: some View {
        HStack(spacing: Layout.spacing) {
            if !manager.selectedTabIDs.isEmpty {
                Text("\(manager.selectedTabIDs.count) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, Layout.spacing / 2)

                toolbarButton("Zoom", systemImage: "arrow.up.left.and.arrow.down.right") { manager.zoomToSelection() }
                toolbarButton("Group", systemImage: "rectangle.dashed") { manager.groupSelected() }
                toolbarButton("Magnet", systemImage: "circle.hexagongrid.circle") { manager.makeMagnetFromSelected() }
                toolbarButton("Close", systemImage: "xmark.circle") { manager.closeSelected() }
                toolbarButton("Clear", systemImage: "lasso") { manager.clearSelection() }

                Divider().frame(height: Layout.dividerHeight)
            }

            toolbarButton("Fit", systemImage: "square.grid.2x2") { manager.zoomToEverything() }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: Layout.shadowRadius, y: Layout.shadowY)
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

    let tabs: [Tab]
    let tileFrames: [Tab.ID: CGRect]
    let snapshots: [Tab.ID: NSImage]
    let zones: [CanvasZone]
    let magnets: [CanvasMagnet]
    let selectedTabIDs: Set<Tab.ID>
    let zoomRequest: CanvasZoomRequest?
    let tileSize: CGSize
    let deskSize: CGSize

    func makeNSView(context: Context) -> TabCanvasScrollView {
        let view = TabCanvasScrollView(deskSize: manager.deskSize)
        view.onActivate = { [weak manager] tab in manager?.dismiss(activating: tab) }
        view.onDismiss = { [weak manager] in manager?.dismiss(activating: nil) }
        view.onSettle = { [weak manager] frames in manager?.settleTiles(frames) }
        view.onTileDropped = { [weak manager] tabID in manager?.finishTileDrag(tabID) }
        view.onTileFellOffDesk = { [weak manager] tabID in manager?.tileFellOffDesk(tabID) }
        view.onZoneMoved = { [weak manager] groupID, delta in manager?.moveZone(groupID, by: delta) }
        view.onMagnetMoved = { [weak manager] groupID, delta in manager?.moveMagnet(groupID, by: delta) }
        view.onMagnetActivated = { [weak manager] groupID in manager?.attract(groupID) }
        view.onLasso = { [weak manager] tabIDs in manager?.select(tabIDs) }
        view.onClearSelection = { [weak manager] in manager?.clearSelection() }
        manager.board = view
        reload(view)
        context.coordinator.lastZoomSerial = zoomRequest?.serial
        view.zoomOutFromFocusedTile(manager.focusedTileFrame, toFit: manager.tilesBounds)
        return view
    }

    func updateNSView(_ view: TabCanvasScrollView, context: Context) {
        reload(view)
        if let zoomRequest, zoomRequest.serial != context.coordinator.lastZoomSerial {
            context.coordinator.lastZoomSerial = zoomRequest.serial
            view.fly(toFit: zoomRequest.rect)
        }
    }

    private func reload(_ view: TabCanvasScrollView) {
        view.reload(CanvasBoardContent(
            tabs: tabs,
            frames: tileFrames,
            snapshots: snapshots,
            zones: zones,
            magnets: magnets,
            selectedTabIDs: selectedTabIDs,
            tileSize: tileSize,
            deskSize: deskSize,
        ))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastZoomSerial: Int?
    }
}

/// Everything the board needs to draw one state.
struct CanvasBoardContent {
    let tabs: [Tab]
    let frames: [Tab.ID: CGRect]
    let snapshots: [Tab.ID: NSImage]
    let zones: [CanvasZone]
    let magnets: [CanvasMagnet]
    let selectedTabIDs: Set<Tab.ID>
    let tileSize: CGSize
    let deskSize: CGSize
}
