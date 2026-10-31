import AppKit
import SwiftUI

/// The engine's latest find-in-page result (``PageEvent/findResultChanged(matches:activeMatch:isFinal:)``).
struct EngineFindResult: Equatable {
    let matches: Int
    /// 1-based; 0 when nothing is selected.
    let activeMatch: Int
    let isFinal: Bool
}

/// Displays an engine page's view.
///
/// The page owns its view; this host only re-parents it, so the page's
/// rendering state survives SwiftUI rebuilding the surrounding hierarchy.
/// Find in page (the Find menu, ⌘F, ⌘G) runs in a find bar above the page for
/// engines declaring ``EngineCapabilities/findInPage``.
struct EngineContentView: NSViewRepresentable {
    let page: any EnginePage
    /// The Refrax page showing it, whose find results the find bar shows.
    var owner: WebPage?

    func makeNSView(context _: Context) -> EngineHostView {
        let host = EngineHostView()
        host.attach(page.view)
        host.page = page
        return host
    }

    func updateNSView(_ host: EngineHostView, context _: Context) {
        host.attach(page.view)
        host.page = page
        host.owner = owner
        host.showFindResult(owner?.engineFindResult)
    }

    static func dismantleNSView(_ host: EngineHostView, coordinator _: ()) {
        host.detach()
    }
}

/// A container that keeps a single engine view filling its bounds, below the find bar when
/// that is open.
final class EngineHostView: NSView {
    private weak var hostedView: NSView?
    weak var page: (any EnginePage)?
    weak var owner: WebPage?
    private var findBar: EngineFindBar?

    override var isFlipped: Bool {
        true
    }

    func attach(_ view: NSView) {
        guard hostedView !== view || view.superview !== self else { return }
        detach()
        view.frame = contentFrame
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: .below, relativeTo: findBar)
        hostedView = view
    }

    func detach() {
        guard let hostedView, hostedView.superview === self else { return }
        hostedView.removeFromSuperview()
        self.hostedView = nil
    }

    private var contentFrame: NSRect {
        guard let findBar else { return bounds }
        let height = findBar.fittingSize.height
        return NSRect(x: 0, y: height, width: bounds.width, height: max(bounds.height - height, 0))
    }

    override func layout() {
        super.layout()
        if let findBar {
            findBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: findBar.fittingSize.height)
        }
        hostedView?.frame = contentFrame
    }

    // MARK: Find in page

    private var findsInPage: Bool {
        page?.engine.capabilities.contains(.findInPage) == true
    }

    func showFindResult(_ result: EngineFindResult?) {
        findBar?.show(result)
    }

    private func showFindBar() {
        if findBar == nil {
            let bar = EngineFindBar()
            bar.onSearch = { [weak self] text, forward, findNext in
                self?.find(text, forward: forward, findNext: findNext)
            }
            bar.onClose = { [weak self] in self?.hideFindBar() }
            addSubview(bar)
            findBar = bar
            needsLayout = true
        }
        findBar?.focus()
    }

    private func hideFindBar() {
        guard let findBar else { return }
        findBar.removeFromSuperview()
        self.findBar = nil
        owner?.hideFindUI()
        needsLayout = true
        if let hostedView {
            window?.makeFirstResponder(hostedView)
        }
    }

    private func find(_ text: String, forward: Bool, findNext: Bool) {
        page?.perform(.find(query: FindQuery(text: text, forward: forward, matchCase: false, findNext: findNext)))
    }

    /// The Find menu's items (``NSTextFinder/Action`` tags), reached through the responder chain
    /// from the page's view.
    @objc(performFindPanelAction:)
    func performFindPanelAction(_ sender: Any?) {
        guard findsInPage, let item = sender as? NSMenuItem, let action = NSTextFinder.Action(rawValue: item.tag) else { return }
        switch action {
        case .showFindInterface:
            showFindBar()
        case .nextMatch, .previousMatch:
            guard let findBar, !findBar.text.isEmpty else {
                showFindBar()
                return
            }
            find(findBar.text, forward: action == .nextMatch, findNext: true)
        case .hideFindInterface:
            hideFindBar()
        default:
            break
        }
    }

}

extension EngineHostView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performFindPanelAction(_:)), findsInPage,
              let action = NSTextFinder.Action(rawValue: item.tag)
        else { return false }
        return [.showFindInterface, .nextMatch, .previousMatch, .hideFindInterface].contains(action)
    }
}

/// The bar find in page shows over an engine page: a search field, the result, previous and
/// next, and Done. Searches as the text changes.
final class EngineFindBar: NSVisualEffectView, NSSearchFieldDelegate {
    var onSearch: ((_ text: String, _ forward: Bool, _ findNext: Bool) -> Void)?
    var onClose: (() -> Void)?

    private let field = NSSearchField()
    private let result = NSTextField(labelWithString: "")
    private let steps = NSSegmentedControl(
        images: [
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: String(localized: "Previous")) ?? NSImage(),
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: String(localized: "Next")) ?? NSImage(),
        ],
        trackingMode: .momentary,
        target: nil,
        action: nil,
    )
    private let done = NSButton(title: String(localized: "Done"), target: nil, action: nil)

    var text: String {
        field.stringValue
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow
        field.delegate = self
        field.placeholderString = String(localized: "Find in Page")
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(searchFieldDidSubmit(_:))
        result.textColor = .secondaryLabelColor
        result.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        steps.target = self
        steps.action = #selector(step(_:))
        steps.controlSize = .small
        done.target = self
        done.action = #selector(close(_:))
        done.controlSize = .small
        done.bezelStyle = .push

        let stack = NSStackView(views: [field, result, steps, done])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalToConstant: 240),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    func show(_ value: EngineFindResult?) {
        guard let value, !field.stringValue.isEmpty else {
            result.stringValue = ""
            return
        }
        result.stringValue = value.matches == 0
            ? String(localized: "No matches")
            : String(localized: "\(value.activeMatch) of \(value.matches)")
    }

    func controlTextDidChange(_: Notification) {
        onSearch?(field.stringValue, true, false)
    }

    @objc private func searchFieldDidSubmit(_: Any?) {
        guard !field.stringValue.isEmpty else { return }
        let backward = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        onSearch?(field.stringValue, !backward, true)
    }

    @objc private func step(_ sender: NSSegmentedControl) {
        guard !field.stringValue.isEmpty else { return }
        onSearch?(field.stringValue, sender.selectedSegment == 1, true)
    }

    @objc private func close(_: Any?) {
        onClose?()
    }

    override func cancelOperation(_: Any?) {
        onClose?()
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(cancelOperation(_:)) else { return false }
        onClose?()
        return true
    }
}
