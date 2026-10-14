import SwiftUI

/// The reload control's context menu: plain, without cache, without content blockers, and in
/// each other installed engine. The page card and the address field apply it to their reload buttons.
struct ReloadOptionsMenu: ViewModifier {
    let onReload: () -> Void
    let onReloadFromOrigin: () -> Void
    let onReloadWithoutContentBlockers: () -> Void
    let otherEngines: [EngineDescriptor]
    let onReloadInEngine: (EngineDescriptor) -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Reload", action: onReload)

            Divider()

            Button("Reload Without Cache", action: onReloadFromOrigin)
            Button("Reload Without Content Blockers", action: onReloadWithoutContentBlockers)

            if !otherEngines.isEmpty {
                Divider()

                ForEach(otherEngines, id: \.id) { engine in
                    Button("Reload in \(engine.displayName)") {
                        onReloadInEngine(engine)
                    }
                }
            }
        }
    }
}
