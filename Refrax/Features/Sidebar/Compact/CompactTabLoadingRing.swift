import SwiftUI

/// Circular progress ring overlay for loading tabs.
///
/// Isolated observation view: declares its own `WebPagePool` environment
/// so loading state changes only invalidate this ring, not the parent tab button.
struct CompactTabLoadingRing: View {
    @Environment(WebPagePool.self) private var pagePool

    let tab: Tab
    let size: CGFloat

    private var loadingState: (isLoading: Bool, progress: Double)? {
        let pages = tab.pages.compactMap { pagePool.existingPage(for: $0) }
        guard let page = pages.first(where: { $0.isLoading }) else { return nil }
        return (true, page.estimatedProgress)
    }

    var body: some View {
        if let state = loadingState, state.isLoading {
            Circle()
                .trim(from: 0, to: max(0.05, state.progress))
                .stroke(Color.appAccentColor, lineWidth: 2)
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.easeInOut(duration: 0.2), value: state.progress)
        }
    }
}
