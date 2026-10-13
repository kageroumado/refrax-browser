import AppKit
import SwiftUI

/// A live desktop page scaled into a movable tab window.
struct FloatingTabPreview: View {
    let tab: Tab
    let viewportSize: CGSize

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @State private var session = FloatingPreviewSession()
    @State private var livePage: WebPage?

    private var isMainContent: Bool {
        tab.id == windowState.activeTabID
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let region = canvas.floatingPlacement(for: tab).region,
               !region.isValid || region.sourceURL != tab.activePage.url || (canvas.verifiedRegionPages[tab.activePage.id] == nil || canvas.verifiedRegionPages[tab.activePage.id] != livePage?.documentRevision) {
                VStack(spacing: 8) {
                    Label("Check saved region", systemImage: "crop")
                    Text("Confirm the region on the current page.").font(.caption).foregroundStyle(.secondary)
                    Button("Adjust Region…") { canvas.beginRegionSelection(for: tab) }
                    Button("Open Full Page") { canvas.openFloatingTab(tab) }
                }.padding(12)
            } else if let livePage, !isMainContent, livePage.ownerWindowID == session.id {
                FloatingPreviewViewport(viewportSize: canvas.floatingPlacement(for: tab).region?.viewportSize ?? viewportSize,
                                        region: canvas.floatingPlacement(for: tab).region) {
                    WebViewContainer(page: livePage)
                        .webViewOwnershipID(session.id)
                }
            } else if let image = canvas.snapshots[tab.id] {
                Image(nsImage: image).resizable().scaledToFit()
                    .overlay(alignment: .bottom) {
                        Text("Preview · Open tab to interact")
                            .font(.caption)
                            .padding(8)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8)
                    }
            } else {
                Label("Open tab to view", systemImage: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: tab.activePage.id) { activate() }
        .task(id: livePage?.documentRevision) {
            guard let livePage, canvas.floatingPlacement(for: tab).region != nil else { return }
            while !Task.isCancelled {
                if canvas.verifiedRegionPages[tab.activePage.id] != nil,
                   await FloatingRegionAnchor.remainsValid(on: livePage) == false {
                    canvas.verifiedRegionPages.removeValue(forKey: tab.activePage.id)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: isMainContent) { activate() }
        .onChange(of: livePage?.isLoading) { _, loading in
            if loading == true { canvas.verifiedRegionPages.removeValue(forKey: tab.activePage.id) }
        }
        .onDisappear { deactivate() }
    }

    private func activate() {
        guard let page = pagePool.page(for: tab.activePage) else { return }
        deactivate()
        if isMainContent {
            livePage = page
        } else if session.acquire(page, windowID: ObjectIdentifier(windowState)) {
            livePage = page
        }
    }

    private func deactivate() {
        session.release()
        livePage = nil
    }
}
