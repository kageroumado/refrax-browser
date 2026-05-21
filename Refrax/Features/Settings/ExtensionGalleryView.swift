import SwiftUI

/// View for browsing and installing extensions from the curated gallery.
///
/// Displays extensions organized by category with links to web stores.
struct ExtensionGalleryView: View {
    @Environment(ExtensionManager.self) private var extensionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var gallery: GalleryResponse?
    @State private var selectedCategory: ExtensionCategory?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var error: (any Error)?

    @State private var installingExtensionID: String?
    @State private var installError: String?
    @State private var showInstallError = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            content
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            loadGallery()
        }
        .alert("Installation Failed", isPresented: $showInstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "Unknown error")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            Section {
                ForEach(availableCategories, id: \.self) { category in
                    Label(category.displayName, systemImage: category.icon)
                        .tag(category as ExtensionCategory?)
                }
            }

            Section {
                Button {
                    openURL(WebStoreURL.chromeWebStore)
                } label: {
                    HStack {
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "globe")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        Text("Chrome Web Store")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    openURL(WebStoreURL.firefoxAddons)
                } label: {
                    HStack {
                        Circle()
                            .fill(.orange.gradient)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        Text("Firefox Add-ons")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }

    private var availableCategories: [ExtensionCategory] {
        guard let gallery else { return [] }

        let categoryCounts = Dictionary(grouping: gallery.extensions, by: \.category)
            .mapValues(\.count)

        return ExtensionCategory.allCases
            .filter { categoryCounts[$0, default: 0] > 0 }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading extensions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView {
                Label("Failed to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") {
                    loadGallery()
                }
            }
        } else if let gallery {
            galleryContent(gallery)
        }
    }

    private func galleryContent(_ gallery: GalleryResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                // Search results or category view
                if !searchText.isEmpty {
                    searchResults(in: gallery)
                } else if let category = selectedCategory {
                    categoryView(category, in: gallery)
                } else {
                    allCategoriesView(in: gallery)
                }
            }
            .padding(24)
        }
        .searchable(text: $searchText, prompt: "Search extensions")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Manage Extensions", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var headerTitle: String {
        if !searchText.isEmpty {
            "Search Results"
        } else if let category = selectedCategory {
            category.displayName
        } else {
            "Popular Extensions"
        }
    }

    private var headerSubtitle: String {
        if !searchText.isEmpty {
            "Results for \"\(searchText)\""
        } else {
            "Refrax supports both Chrome and Firefox extensions. Click \"Get\" to install."
        }
    }

    // MARK: - Search Results

    private func searchResults(in gallery: GalleryResponse) -> some View {
        let results = gallery.extensions.filter { ext in
            let query = searchText.lowercased()
            return ext.name.lowercased().contains(query) ||
                ext.description.lowercased().contains(query) ||
                ext.tags.contains { $0.lowercased().contains(query) }
        }

        return Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                extensionGrid(results)
            }
        }
    }

    // MARK: - Category View

    private func categoryView(_ category: ExtensionCategory, in gallery: GalleryResponse) -> some View {
        let extensions = gallery.extensions
            .filter { $0.category == category }
            .sorted { $0.popularityRank < $1.popularityRank }

        return VStack(alignment: .leading, spacing: 16) {
            extensionGrid(extensions)
        }
    }

    // MARK: - All Categories View

    private func allCategoriesView(in gallery: GalleryResponse) -> some View {
        let groupedExtensions = Dictionary(grouping: gallery.extensions, by: \.category)

        return VStack(alignment: .leading, spacing: 32) {
            ForEach(availableCategories, id: \.self) { category in
                if let extensions = groupedExtensions[category], !extensions.isEmpty {
                    categorySection(
                        category: category,
                        extensions: extensions.sorted { $0.popularityRank < $1.popularityRank },
                    )
                }
            }
        }
    }

    private func categorySection(category: ExtensionCategory, extensions: [GalleryExtension]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(category.displayName, systemImage: category.icon)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if extensions.count > 4 {
                    Button("See All") {
                        selectedCategory = category
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccentColor)
                }
            }

            extensionGrid(Array(extensions.prefix(4)))
        }
    }

    // MARK: - Extension Grid

    private func extensionGrid(_ extensions: [GalleryExtension]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ],
            spacing: 16,
        ) {
            ForEach(extensions) { ext in
                GalleryExtensionCard(
                    extension_: ext,
                    isInstalling: installingExtensionID == ext.id,
                    isInstalled: isInstalled(ext),
                    onInstall: { installExtension(ext) },
                    onOpenStore: { openStore(for: ext) },
                )
            }
        }
    }

    // MARK: - Actions

    private func loadGallery() {
        isLoading = true
        error = nil

        do {
            gallery = try extensionManager.galleryService.fetchGallery()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func isInstalled(_ ext: GalleryExtension) -> Bool {
        extensionManager.installedExtensions.contains { installed in
            installed.displayName.lowercased() == ext.name.lowercased()
        }
    }

    private func installExtension(_ ext: GalleryExtension) {
        installingExtensionID = ext.id

        Task {
            do {
                // Get download URL
                guard let downloadURL = extensionManager.galleryService.downloadURL(for: ext) else {
                    throw GalleryError.downloadFailed(NSError(domain: "Gallery", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Could not determine download URL",
                    ]))
                }

                // Download the extension file
                let (localURL, _) = try await URLSession.shared.download(from: downloadURL)

                // Determine file extension and install
                let fileExtension = downloadURL.pathExtension.lowercased()
                let destinationURL: URL

                if fileExtension == "xpi" || fileExtension == "crx" {
                    destinationURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(fileExtension)
                } else {
                    // Assume XPI for Firefox, CRX for Chrome
                    let ext = switch ext.source {
                    case .firefox: "xpi"
                    case .chrome: "crx"
                    case .directDownload: "crx"
                    }
                    destinationURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                }

                try FileManager.default.moveItem(at: localURL, to: destinationURL)

                // Install from archive
                try await extensionManager.installFromArchive(destinationURL)

                // Clean up
                try? FileManager.default.removeItem(at: destinationURL)

            } catch {
                installError = error.localizedDescription
                showInstallError = true
            }

            installingExtensionID = nil
        }
    }

    private func openStore(for ext: GalleryExtension) {
        if let url = ext.source.storeURL {
            openURL(url)
        }
    }
}

// MARK: - Gallery Extension Card

/// Card displaying a single extension in the gallery.
struct GalleryExtensionCard: View {
    let extension_: GalleryExtension
    let isInstalling: Bool
    let isInstalled: Bool
    let onInstall: () -> Void
    let onOpenStore: () -> Void

    @State private var iconImage: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            extensionIcon
                .frame(width: 48, height: 48)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(extension_.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(extension_.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(extension_.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let version = extension_.version {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Action button
            actionButton
        }
        .padding(12)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .task {
            await loadIcon()
        }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInstalled {
            Text("Installed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if isInstalling {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 12)
        } else {
            Button("Get") {
                onInstall()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func loadIcon() async {
        guard let iconURL = extension_.iconURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: iconURL)
            if let image = NSImage(data: data) {
                iconImage = image
            }
        } catch {
            // Silently fail, use placeholder
        }
    }
}
