import SwiftUI

/// The reload control's context menu: plain, without cache, without content blockers, in each
/// other installed engine, and the site rule for the page's host. The page card and the address
/// field apply it to their reload buttons.
struct ReloadOptionsMenu: ViewModifier {
    @Environment(EngineRegistry.self) private var engineRegistry

    let onReload: () -> Void
    let onReloadFromOrigin: () -> Void
    let onReloadWithoutContentBlockers: () -> Void
    let otherEngines: [EngineDescriptor]
    let onReloadInEngine: (EngineDescriptor) -> Void
    /// The site rule changes for the page, computed as the menu opens.
    let siteRuleActions: () -> [SiteEngineRuleAction]
    let onSiteRuleAction: (SiteEngineRuleAction) -> Void

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

                ForEach(siteRuleActions(), id: \.self) { action in
                    Button(action.title(registry: engineRegistry)) {
                        onSiteRuleAction(action)
                    }
                }
            }
        }
    }
}
