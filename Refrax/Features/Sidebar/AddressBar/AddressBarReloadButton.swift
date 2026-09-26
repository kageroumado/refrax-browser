import SwiftUI

struct AddressBarReloadButton: View {
    let isLoading: Bool
    let onReload: () -> Void
    let onReloadFromOrigin: () -> Void
    let onReloadWithoutContentBlockers: () -> Void
    /// Engines the page could move to: every installed one except its current engine.
    let otherEngines: [EngineDescriptor]
    let onReloadInEngine: (EngineDescriptor) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onReload) {
            Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(isLoading ? "addressbar-stop" : "addressbar-reload")
        .accessibilityLabel(isLoading ? "Stop loading" : "Reload page")
        .contextMenu {
            Button("Reload") {
                onReload()
            }
            
            Divider()
            
            Button("Reload Without Cache") {
                onReloadFromOrigin()
            }
            
            Button("Reload Without Content Blockers") {
                onReloadWithoutContentBlockers()
            }

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
