import SwiftUI

/// Displays a link URL preview at the bottom-left of a web view container.
///
/// This view appears when the user hovers over a link in a web page, showing
/// the destination URL. The preview is styled with a liquid glass capsule and
/// truncates long URLs with middle ellipsis. Technical portions of the URL
/// (protocol prefixes and `www.`) are dimmed for improved readability.
///
/// ## Usage
///
/// ```swift
/// ZStack(alignment: .bottomLeading) {
///     WebView(page)
///
///     LinkHoverPreviewView(url: $hoveredLinkURL)
///         .padding(8)
/// }
/// ```
struct LinkHoverPreviewView: View {
    /// Binding to the URL currently being hovered, or nil when no link is hovered.
    @Binding var url: URL?

    private enum Constants {
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let maxWidth: CGFloat = 400
        static let fontSize: CGFloat = 12
        static let animationDuration: Double = 0.15
    }

    /// Matches protocol prefixes (e.g., `https://`) and `www.` for dimming.
    private static let technicalPartsRegex = /^[a-z][a-z0-9+.-]*:\/\/|www\./

    var body: some View {
        Group {
            if url != nil {
                contentView
            }
        }
    }

    private var contentView: some View {
        ViewThatFits(in: .horizontal) {
            urlText
                .fixedSize(horizontal: true, vertical: false)

            urlText
                .frame(maxWidth: Constants.maxWidth, alignment: .leading)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .clipShape(Capsule())
        .glassEffect(.regular, in: Capsule())
    }

    private var urlText: some View {
        Text(formattedURL)
            .font(.system(size: Constants.fontSize))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var formattedURL: AttributedString {
        guard let urlString = url?.absoluteString else {
            return AttributedString()
        }

        var attributed = AttributedString(urlString)
        attributed.foregroundColor = .secondary

        for match in urlString.matches(of: Self.technicalPartsRegex) {
            let start = attributed.index(
                attributed.startIndex,
                offsetByCharacters: urlString.distance(from: urlString.startIndex, to: match.range.lowerBound),
            )
            let end = attributed.index(
                attributed.startIndex,
                offsetByCharacters: urlString.distance(from: urlString.startIndex, to: match.range.upperBound),
            )
            attributed[start ..< end].foregroundColor = Color.secondary.opacity(0.75)
        }

        return attributed
    }
}
