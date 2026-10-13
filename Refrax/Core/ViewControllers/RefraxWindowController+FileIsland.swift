import AppKit
import SwiftUI

extension RefraxWindowController {
    /// Adds the File Island above the Control Island, and over everything the window's drop
    /// surface for files, images, text, and links.
    func setupFileIslandLayer(contentView: NSView) {
        let island = FileIslandHostingView(rootView: FileIslandLayer().refraxEnvironment(environment))
        island.sizingOptions = []
        island.state = { [weak windowState] in windowState?.fileIsland }
        fillContentView(contentView, with: island)

        let drops = FileIslandDropView()
        drops.state = { [weak windowState] in windowState?.fileIsland }
        drops.isActive = { [weak tabCanvasManager] in
            guard let tabCanvasManager else { return false }
            return tabCanvasManager.showsFloatingControls && tabCanvasManager.regionSelection == nil
        }
        drops.reservedRegions = { [weak windowState] in windowState?.controlIsland.hitRegions ?? [] }
        drops.keep = { [weak shelf = environment.shelfManager] drop in
            Task(name: "Keep drop on the shelf") { await shelf?.add(drop) }
        }
        drops.openLink = { [weak self] url in
            guard let self else { return }
            FileIslandActions.openLink(url, tabs: tabManager, in: windowState)
        }
        fillContentView(contentView, with: drops)
    }

    /// Shows the File Island's full lists in the floating layout, or the downloads tray beside the sidebar.
    func showDownloads() {
        if tabCanvasManager.showsFloatingControls {
            windowState.fileIsland.showAll()
        } else {
            windowState.toggleDetailTray(.downloads)
        }
    }

    private func fillContentView(_ contentView: NSView, with view: NSView) {
        contentView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}
