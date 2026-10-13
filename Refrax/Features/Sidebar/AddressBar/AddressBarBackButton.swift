import AppKit
import SwiftUI

/// Back navigation button that manages its own state and actions.
///
/// Takes `canGoBack` as an explicit parameter so SwiftUI can detect when
/// navigation state changes and re-render the button appropriately.
struct AddressBarBackButton: View {
    let webPage: WebPage?
    let canGoBack: Bool

    var targetSize = CGSize(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
    var highlightsOnHover = true
    var symbolWeight: Font.Weight = .medium

    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.appearsActive) private var appearsActive

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                windowState.showDetailTray(.backForward)
            } else {
                webPage?.goBack()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: symbolWeight))
                .foregroundStyle(canGoBack ? (appearsActive ? (highlightsOnHover && isHovered ? .primary : .secondary) : .tertiary) : .quaternary)
                .frame(width: targetSize.width, height: targetSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canGoBack)
        .onHover { if highlightsOnHover { isHovered = $0 } }
        .contextMenu { backContextMenu }
        .overlay {
            if canGoBack {
                MiddleClickHandler {
                    if let backItem = webPage?.backList.last {
                        tabManager.createTab(url: backItem.url, makeActive: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backContextMenu: some View {
        if let backList = webPage?.backList, !backList.isEmpty {
            ForEach(backList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }
}

/// Forward navigation button that manages its own state and actions.
///
/// Takes `canGoForward` as an explicit parameter so SwiftUI can detect when
/// navigation state changes and re-render the button appropriately.
struct AddressBarForwardButton: View {
    let webPage: WebPage?
    let canGoForward: Bool

    var targetSize = CGSize(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
    var highlightsOnHover = true
    var symbolWeight: Font.Weight = .medium

    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.appearsActive) private var appearsActive

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                windowState.showDetailTray(.backForward)
            } else {
                webPage?.goForward()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: symbolWeight))
                .foregroundStyle(canGoForward ? (appearsActive ? (highlightsOnHover && isHovered ? .primary : .secondary) : .tertiary) : .quaternary)
                .frame(width: targetSize.width, height: targetSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canGoForward)
        .onHover { if highlightsOnHover { isHovered = $0 } }
        .frame(width: canGoForward ? targetSize.width : 0)
        .opacity(canGoForward ? 1 : 0)
        .clipped()
        .contextMenu { forwardContextMenu }
        .overlay {
            if canGoForward {
                MiddleClickHandler {
                    if let forwardItem = webPage?.forwardList.first {
                        tabManager.createTab(url: forwardItem.url, makeActive: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var forwardContextMenu: some View {
        if let forwardList = webPage?.forwardList, !forwardList.isEmpty {
            ForEach(forwardList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }
}
