import AppKit
import SwiftUI

/// A desktop page scaled into a movable tab window: live and interactive while `isLive`,
/// otherwise its full-resolution snapshot. A page just taken live keeps the snapshot on top
/// until it paints.
struct FloatingTabPreview: View {
    let tab: Tab
    let viewportSize: CGSize
    /// Holds the page live. A card that is only peeked at shows its snapshot, so revealing
    /// the floating layer composites images and draws no pages.
    var isLive = true

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @State private var session = FloatingPreviewSession()
    @State private var livePage: WebPage?
    @State private var hasPainted = false
    @Environment(TableController.self) private var table

    private enum Layout {
        static let firstPaintFade: TimeInterval = 0.15
    }

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
            } else if isLive, let livePage, !isMainContent, livePage.ownerWindowID == session.id {
                FloatingPreviewViewport(
                    viewportSize: canvas.floatingPlacement(for: tab).region?.viewportSize ?? viewportSize,
                    region: canvas.floatingPlacement(for: tab).region,
                ) {
                    WebViewContainer(page: livePage)
                        .webViewOwnershipID(session.id)
                }
                .overlay {
                    if !hasPainted {
                        snapshotFace
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: Layout.firstPaintFade), value: hasPainted)
                .task(id: ObjectIdentifier(livePage)) {
                    hasPainted = false
                    await livePage.waitForPresentationUpdate()
                    guard !Task.isCancelled else { return }
                    hasPainted = true
                }
            } else {
                snapshotFace
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
        .onChange(of: isLive) { activate() }
        // A page another surface held when this one went live is taken as soon as it is free.
        .onChange(of: pagePool.existingPage(for: tab.activePage)?.ownerWindowID) {
            if isLive, !isMainContent, livePage?.ownerWindowID != session.id {
                activate()
            }
        }
        .onChange(of: livePage?.isLoading) { _, loading in
            if loading == true {
                canvas.verifiedRegionPages.removeValue(forKey: tab.activePage.id)
            }
        }
        .onDisappear { deactivate() }
    }

    /// The card's snapshot, or its favicon and title when it has none.
    @ViewBuilder
    private var snapshotFace: some View {
        if let image = table.snapshot(for: tab.id) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            PagePlaceholder(tab: tab)
                .task(id: tab.id) { table.requestStoredSnapshot(for: tab) }
        }
    }

    private func activate() {
        guard isLive || isMainContent else {
            if let page = livePage, page.ownerWindowID == session.id {
                deactivate()
                Task { await table.captureSnapshot(of: tab) }
            } else {
                deactivate()
            }
            return
        }
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
