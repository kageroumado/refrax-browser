import SwiftUI

/// Frames the live desktop page without changing the site's layout.
struct FloatingRegionSelector: View {
    let selection: FloatingRegionSelection
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @State private var rect: CGRect = .zero
    @State private var dragStart: CGRect?
    @FocusState private var frameFocused: Bool

    private var page: CGRect { CGRect(origin: .zero, size: selection.viewportSize) }
    private var selectionInWindow: CGRect { rect.offsetBy(dx: selection.pageFrame.minX, dy: selection.pageFrame.minY) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(selectionInWindow)
                }
                .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        let start = CGPoint(x: value.startLocation.x - selection.pageFrame.minX, y: value.startLocation.y - selection.pageFrame.minY)
                        let end = CGPoint(x: value.location.x - selection.pageFrame.minX, y: value.location.y - selection.pageFrame.minY)
                        rect = selection.boundedRect(from: start, to: end)
                    })
                Rectangle().strokeBorder(.white, lineWidth: 2)
                    .background(.clear).contentShape(Rectangle())
                    .frame(width: max(1, rect.width), height: max(1, rect.height))
                    .overlay(alignment: .bottomTrailing) { resizeHandle }
                    .offset(x: selectionInWindow.minX, y: selectionInWindow.minY)
                    .gesture(DragGesture().onChanged { value in
                        let start = dragStart ?? rect
                        dragStart = start
                        rect.origin = CGPoint(x: min(max(0, start.minX + value.translation.width), page.width - rect.width),
                                              y: min(max(0, start.minY + value.translation.height), page.height - rect.height))
                    }.onEnded { _ in dragStart = nil })
                    .focusable().focused($frameFocused)
                    .accessibilityLabel("Region for \(selection.tab.displayTitle). Arrow keys move; Shift and arrows resize.")
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                        adjust(press.key, resizing: press.modifiers.contains(.shift))
                        return .handled
                    }
                VStack(spacing: 10) {
                    Text("Keep part of \(selection.tab.activePage.url.host ?? selection.tab.displayTitle)").font(.headline)
                    Text("Experimental live viewport · Changes to this page may require reframing.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = canvas.regionSelectionError { Text(error).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Cancel") { canvas.cancelRegionSelection() }.keyboardShortcut(.cancelAction)
                        Button("Whole Page") {
                            canvas.keepWholePage(selection.tab)
                        }
                        Button(windowState.pageVisit.destination.map { "Keep beside \($0.title)" } ?? "Keep Visible") {
                            canvas.keepRegion(rect)
                        }.buttonStyle(.borderedProminent).disabled(rect.width < 32 || rect.height < 32)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16).glassEffect(.regular, in: .rect(cornerRadius: 18))
                .frame(maxWidth: min(600, geometry.size.width - 32))
                .position(x: geometry.size.width / 2, y: min(geometry.size.height - 70, 90))
            }
            .onChange(of: geometry.size) { canvas.cancelRegionSelection() }
        }
        .onAppear {
            if let saved = canvas.floatingPlacement(for: selection.tab).region?.rect, page.contains(saved) {
                rect = saved
            } else {
                rect = page.insetBy(dx: page.width * 0.25, dy: page.height * 0.3)
            }
            frameFocused = true
        }
        .onChange(of: windowState.activeTabID) { canvas.cancelRegionSelection() }
        .onChange(of: windowState.isSpaceLocked) { canvas.cancelRegionSelection() }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .padding(8).background(.regularMaterial, in: Circle()).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                rect.size = CGSize(width: min(page.width - rect.minX, max(32, start.width + value.translation.width)),
                                   height: min(page.height - rect.minY, max(32, start.height + value.translation.height)))
            }.onEnded { _ in dragStart = nil })
            .accessibilityLabel("Resize region")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 10 : -10
                rect.size = CGSize(width: min(page.width - rect.minX, max(32, rect.width + delta)),
                                   height: min(page.height - rect.minY, max(32, rect.height + delta)))
            }
    }

    private func adjust(_ key: KeyEquivalent, resizing: Bool) {
        let dx: CGFloat = key == .leftArrow ? -10 : (key == .rightArrow ? 10 : 0)
        let dy: CGFloat = key == .upArrow ? -10 : (key == .downArrow ? 10 : 0)
        if resizing {
            rect.size = CGSize(width: min(page.width - rect.minX, max(32, rect.width + dx)),
                               height: min(page.height - rect.minY, max(32, rect.height + dy)))
        } else {
            rect.origin = CGPoint(x: min(max(0, rect.minX + dx), page.width - rect.width),
                                  y: min(max(0, rect.minY + dy), page.height - rect.height))
        }
    }
}
