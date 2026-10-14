import AppKit
import SwiftUI

extension RefraxWindowController {
    /// Keeps browser controls reachable above transient lenses and the recent-tab picker.
    func setupControlIslandLayer(contentView: NSView) {
        let controls = FloatingTabsHostingView(rootView: ControlIslandLayer().refraxEnvironment(environment))
        controls.sizingOptions = []
        controls.controlState = { [weak windowState] in windowState?.controlIsland }
        controls.hitRegions = { [weak controls, weak windowState, weak tabCanvasManager] in
            guard tabCanvasManager?.showsFloatingControls == true else { return [] }
            if tabCanvasManager?.regionSelection != nil, let controls {
                return [controls.bounds]
            }
            return windowState?.controlIsland.hitRegions ?? []
        }
        contentView.addSubview(controls)
        controls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controls.topAnchor.constraint(equalTo: contentView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}
