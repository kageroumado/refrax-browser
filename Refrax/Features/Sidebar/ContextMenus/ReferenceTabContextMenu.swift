import AppKit
import SwiftUI

// MARK: - Reference Tab Context Menu

extension SidebarContextMenus {
    /// Context menu for a reference tab in the reference pane.
    ///
    /// Reference tabs have a simpler set of options compared to main tabs:
    /// - Reload
    /// - Duplicate
    /// - Copy/Share
    /// - Move to Sidebar
    /// - Close operations
    struct ReferenceTab: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(WebPagePool.self) private var pagePool
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator
        @SwiftUI.Environment(WindowState.self) private var windowState

        let tab: Refrax.Tab

        private var existingWebPage: WebPage? {
            pagePool.existingPage(for: tab.activePage)
        }

        /// Reference tabs in the current space.
        private var referenceTabs: [Refrax.Tab] {
            windowState.activeSpace?.referenceTabs ?? []
        }

        /// Index of this tab in reference tabs.
        private var tabIndex: Int? {
            referenceTabs.firstIndex(where: { $0.id == tab.id })
        }

        /// Reference tabs above this tab.
        private var tabsAbove: [Refrax.Tab] {
            guard let index = tabIndex, index > 0 else { return [] }
            return Array(referenceTabs[..<index])
        }

        /// Reference tabs below this tab.
        private var tabsBelow: [Refrax.Tab] {
            guard let index = tabIndex, index < referenceTabs.count - 1 else { return [] }
            return Array(referenceTabs[(index + 1)...])
        }

        /// Other reference tabs (all except this one).
        private var otherTabs: [Refrax.Tab] {
            referenceTabs.filter { $0.id != tab.id }
        }

        var body: some View {
            // MARK: Reload

            if existingWebPage != nil {
                Button {
                    _ = existingWebPage?.reload()
                } label: {
                    Label("Reload", systemImage: ContextMenuIcon.reload.systemName)
                }
            }

            Button {
                tabManager.duplicateReferenceTab(tab)
            } label: {
                Label("Duplicate", systemImage: ContextMenuIcon.duplicateTab.systemName)
            }
            .disabled(referenceTabs.count >= 4)

            Divider()

            // MARK: Copy/Share

            Button {
                let url = tabManager.copyableURL(for: tab)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: {
                Label("Copy URL", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let url = tabManager.copyableURL(for: tab)
                let title = tab.displayTitle
                let markdown = "[\(title)](\(url))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy URL as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let cleanURL = URL(string: tabManager.copyableURL(for: tab)) ?? tab.activePage.url
                sharingCoordinator.shareURL(cleanURL, title: tab.displayTitle)
            } label: {
                Label("Share...", systemImage: ContextMenuIcon.share.systemName)
            }

            Divider()

            // MARK: Organization

            Button {
                tabManager.moveReferenceTabToMainArea(tab, makeActive: true)
            } label: {
                Label("Move to Sidebar", systemImage: ContextMenuIcon.moveToSidebar.systemName)
            }

            Divider()

            // MARK: Close

            Button {
                tabManager.closeReferenceTab(tab)
            } label: {
                Label("Close", systemImage: ContextMenuIcon.close.systemName)
            }

            // Close Other Tabs
            if !otherTabs.isEmpty {
                Button {
                    for otherTab in otherTabs {
                        tabManager.closeReferenceTab(otherTab)
                    }
                } label: {
                    Label("Close Other Tabs", systemImage: ContextMenuIcon.close.systemName)
                }
            }

            // Close Tabs Above
            if !tabsAbove.isEmpty {
                Button {
                    for otherTab in tabsAbove {
                        tabManager.closeReferenceTab(otherTab)
                    }
                } label: {
                    Label("Close Tabs Above", systemImage: ContextMenuIcon.close.systemName)
                }
            }

            // Close Tabs Below
            if !tabsBelow.isEmpty {
                Button {
                    for otherTab in tabsBelow {
                        tabManager.closeReferenceTab(otherTab)
                    }
                } label: {
                    Label("Close Tabs Below", systemImage: ContextMenuIcon.close.systemName)
                }
            }
        }
    }
}
