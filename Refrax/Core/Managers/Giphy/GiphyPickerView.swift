import SwiftUI

/// A picker view for searching and selecting GIFs from Giphy.
///
/// Displays a search field and a grid of animated GIF previews.
/// Selecting a GIF calls the `onSelect` callback.
struct GiphyPickerView: View {
    /// Called when a GIF is selected.
    let onSelect: (GiphyGIF) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manager = GiphyManager()
    @State private var searchText = ""

    private enum Layout {
        static let width: CGFloat = 400
        static let height: CGFloat = 450
        static let columns = 3
        static let spacing: CGFloat = 8
        static let previewHeight: CGFloat = 100
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
        .task {
            await manager.loadTrending()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Insert GIF")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 12) {
            searchField
            gifGrid
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search GIFs...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await manager.search(searchText) }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await manager.search("") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var gifGrid: some View {
        if manager.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = manager.errorMessage {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if manager.searchResults.isEmpty {
            ContentUnavailableView {
                Label("No GIFs Found", systemImage: "photo")
            } description: {
                Text("Try a different search term")
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Layout.spacing), count: Layout.columns),
                    spacing: Layout.spacing,
                ) {
                    ForEach(manager.searchResults) { gif in
                        GiphyGridItem(gif: gif) {
                            onSelect(gif)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Link(destination: URL.staticRequired("https://giphy.com")) {
                HStack(spacing: 4) {
                    Text("Powered by")
                        .foregroundStyle(.secondary)
                    Text("GIPHY")
                        .fontWeight(.semibold)
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Grid Item

private struct GiphyGridItem: View {
    let gif: GiphyGIF
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: gif.previewURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(isHovered ? 0.5 : 0), lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(gif.title)
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    GiphyPickerView { gif in
        print("Selected: \(gif.title)")
    }
}
