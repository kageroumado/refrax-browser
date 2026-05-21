import SwiftUI

/// A container that adapts sheet height based on content and available window space.
///
/// Behavior:
/// - Measures the content's natural height using a hidden measurement view
/// - Compares with available window height minus vertical margins
/// - Uses the smaller of the two (content doesn't grow beyond its needs)
/// - Shows scrollable content only when content exceeds available space
/// - Enforces a minimum height even if window is very small
///
/// ## Usage
///
/// ```swift
/// AdaptiveSheetContainer(minHeight: 300, verticalMargin: 100) {
///     // Header (fixed)
///     Text("Title")
/// } content: {
///     // Scrollable content
///     Form { ... }
/// } footer: {
///     // Footer (fixed)
///     HStack { Button("Cancel") { } }
/// }
/// ```
struct AdaptiveSheetContainer<Header: View, Content: View, Footer: View>: View {
    let minHeight: CGFloat
    let verticalMargin: CGFloat

    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var windowHeight: CGFloat = 800

    init(
        minHeight: CGFloat = 300,
        verticalMargin: CGFloat = 100,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer,
    ) {
        self.minHeight = minHeight
        self.verticalMargin = verticalMargin
        self.header = header
        self.content = content
        self.footer = footer
    }

    private var totalContentHeight: CGFloat {
        headerHeight + contentHeight + footerHeight
    }

    private var availableHeight: CGFloat {
        max(minHeight, windowHeight - (verticalMargin * 2))
    }

    private var needsScroll: Bool {
        totalContentHeight > availableHeight
    }

    private var sheetHeight: CGFloat {
        if needsScroll {
            availableHeight
        } else {
            max(minHeight, totalContentHeight)
        }
    }

    var body: some View {
        ZStack {
            measurementView

            VStack(spacing: 0) {
                header()
                    .background(SizeReader(size: $headerHeight, dimension: .height))

                if needsScroll {
                    ScrollView {
                        content()
                    }
                } else {
                    content()
                }

                footer()
                    .background(SizeReader(size: $footerHeight, dimension: .height))
            }
            .frame(height: sheetHeight)
        }
        .onAppear {
            updateWindowHeight()
        }
    }

    /// Hidden view that measures the natural content height.
    private var measurementView: some View {
        VStack(spacing: 0) {
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(SizeReader(size: $contentHeight, dimension: .height))
        .hidden()
    }

    private func updateWindowHeight() {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            windowHeight = window.frame.height
        }
    }
}

// MARK: - Size Reader

private enum SizeDimension {
    case width
    case height
}

private struct SizeReader: View {
    @Binding var size: CGFloat
    let dimension: SizeDimension

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    updateSize(from: geometry)
                }
                .onChange(of: geometry.size) { _, _ in
                    updateSize(from: geometry)
                }
        }
    }

    private func updateSize(from geometry: GeometryProxy) {
        let value = dimension == .height ? geometry.size.height : geometry.size.width
        if size != value {
            size = value
        }
    }
}

// MARK: - Convenience Initializers

extension AdaptiveSheetContainer where Header == EmptyView {
    init(
        minHeight: CGFloat = 300,
        verticalMargin: CGFloat = 100,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer,
    ) {
        self.init(
            minHeight: minHeight,
            verticalMargin: verticalMargin,
            header: { EmptyView() },
            content: content,
            footer: footer,
        )
    }
}

extension AdaptiveSheetContainer where Footer == EmptyView {
    init(
        minHeight: CGFloat = 300,
        verticalMargin: CGFloat = 100,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(
            minHeight: minHeight,
            verticalMargin: verticalMargin,
            header: header,
            content: content,
            footer: { EmptyView() },
        )
    }
}

extension AdaptiveSheetContainer where Header == EmptyView, Footer == EmptyView {
    init(
        minHeight: CGFloat = 300,
        verticalMargin: CGFloat = 100,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(
            minHeight: minHeight,
            verticalMargin: verticalMargin,
            header: { EmptyView() },
            content: content,
            footer: { EmptyView() },
        )
    }
}
