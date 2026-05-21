import Foundation

// MARK: - Position Normalization

extension TabManager {
    /// Normalizes positions for tabs and groups to maintain visual order.
    ///
    /// Uses a hierarchical position scheme:
    /// - Root level: billions (1_000_000_000 * index)
    /// - In group: millions (base + 1_000_000 * offset)
    /// - In nested group: thousands (base + 1_000 * offset)
    ///
    /// - Parameter space: Space to normalize. If nil, uses active window's space.
    func normalizePositions(in space: Space? = nil) {
        let targetSpace = space ?? activeWindowState?.activeSpace
        guard let targetSpace else { return }

        positioner.normalize(space: targetSpace, force: true)
    }
}

// MARK: - Persistence

extension TabManager {
    /// Creates a temporary space for first-frame rendering (no DB operations).
    ///
    /// Caller must call `state.clearSpaces()` before `restoreFromPersistence()`
    /// to replace this temporary space with persisted data.
    func createTemporarySpace() -> Space {
        spaceManager.makeDefaultSpace()
    }

    /// Restores spaces from persistence on app launch.
    ///
    /// - Returns: The default space to show in new windows.
    @discardableResult
    func restoreFromPersistence() -> Space {
        spaceManager.restoreFromPersistence()

        // Disabled the default content setup as the debug build now uses on-disk persistence.
//        #if DEBUG
//            // In debug builds, set up test content on first launch.
//            // Deferred to avoid blocking startup.
//            // Uses [weak self] to avoid crash during test teardown when
//            // unowned references (spaceManager) are deallocated first.
//            if state.spaces.count == 1, state.spaces.first?.tabs.isEmpty == true {
//                DispatchQueue.main.async { [weak self] in
//                    self?.setupDefaultContent()
//                }
//            }
//        #endif
    }

    /// Initializes a window with a space.
    ///
    /// - Parameters:
    ///   - windowState: The window state to initialize.
    ///   - space: The space to show. If nil, uses the first space.
    func initializeWindow(_ windowState: WindowState, with space: Space? = nil) {
        let targetSpace = space ?? state.spaces.first
        guard let targetSpace else {
            Logger.error("Cannot initialize window: no spaces", category: Logger.tabs)
            return
        }

        // Just switch to the space - don't select a tab or create WebPages.
        // The user will select a tab manually, which triggers lazy WebPage creation.
        // This avoids blocking app launch with GPU/OpenGL initialization.
        // Use sync version during initialization - locked spaces remain locked until user interaction.
        spaceManager.switchToSpaceSync(targetSpace, for: windowState, restoreActiveTab: false)
    }

    /// Saves space state.
    func saveSpaceState(_ space: Space) {
        spaceManager.saveSpaceState(space, windowState: nil)
    }

    /// Saves immediately (use sparingly).
    func saveImmediately() async {
        await state.saveImmediately()
    }

    /// Schedules a debounced save.
    ///
    /// Delegates to `BrowserState.scheduleSave()` for centralized save management.
    func scheduleSave() {
        state.scheduleSave()
    }
}

// MARK: - Helpers

extension TabManager {
    /// Gets copyable URL for a tab.
    func copyableURL(for tab: Tab) -> String {
        tab.activePage.url.absoluteString
    }

    #if DEBUG
        /// Sets up default content for first launch with comprehensive test data.
        func setupDefaultContent() {
            guard let space = state.spaces.first, space.tabs.isEmpty else { return }

            spaceManager.ensureLoaded(space)

            // MARK: - Pinned Tabs

            let audioTest = createTab(
                url: URL.staticRequired("https://webbrowsertools.com/audio-test/"),
                in: space,
                isPinned: true,
                makeActive: false,
            )
            audioTest.customName = "Audio"

            createTab(
                url: URL.staticRequired("https://github.com/"),
                in: space,
                isPinned: true,
                makeActive: false,
            )

            // MARK: - Wikipedia Deep Dives Group

            let wikiGroup = try? groupManager.createGroup(
                in: space,
                name: "Wikipedia Rabbit Hole",
                color: GroupColor.emerald.rawValue,
                iconName: "book.fill",
            )

            if let group = wikiGroup {
                let wikiArticles = [
                    "https://en.wikipedia.org/wiki/Quine_(computing)",
                    "https://en.wikipedia.org/wiki/Turing_completeness",
                    "https://en.wikipedia.org/wiki/Lambda_calculus",
                    "https://en.wikipedia.org/wiki/Kolmogorov_complexity",
                    "https://en.wikipedia.org/wiki/G%C3%B6del%27s_incompleteness_theorems",
                    "https://en.wikipedia.org/wiki/Halting_problem",
                    "https://en.wikipedia.org/wiki/Church%E2%80%93Turing_thesis",
                ]
                for urlString in wikiArticles {
                    guard let url = URL(string: urlString) else { continue }
                    createTab(url: url, in: space, groupID: group.id, makeActive: false)
                }
            }

            // MARK: - Browser Testing Group

            let testGroup = try? groupManager.createGroup(
                in: space,
                name: "Browser Tests",
                color: GroupColor.neon.rawValue,
                iconName: "checkmark.shield.fill",
            )

            if let group = testGroup {
                let testSites = [
                    "https://html5test.co/",
                    "https://browserbench.org/Speedometer3.1/",
                    "https://browserleaks.com/webrtc",
                    "https://fill.dev/form/login-simple",
                    "https://caniuse.com/",
                ]
                for urlString in testSites {
                    guard let url = URL(string: urlString) else { continue }
                    createTab(url: url, in: space, groupID: group.id, makeActive: false)
                }
            }

            // MARK: - Science & Nature Group

            let scienceGroup = try? groupManager.createGroup(
                in: space,
                name: "Science",
                color: GroupColor.mahogany.rawValue,
                iconName: "atom",
            )

            if let group = scienceGroup {
                let scienceArticles = [
                    "https://en.wikipedia.org/wiki/Black_hole",
                    "https://en.wikipedia.org/wiki/Quantum_entanglement",
                    "https://en.wikipedia.org/wiki/CRISPR_gene_editing",
                    "https://en.wikipedia.org/wiki/Fermi_paradox",
                    "https://en.wikipedia.org/wiki/Emergence",
                ]
                for urlString in scienceArticles {
                    guard let url = URL(string: urlString) else { continue }
                    createTab(url: url, in: space, groupID: group.id, makeActive: false)
                }
            }

            // MARK: - Music & Art Group

            let artGroup = try? groupManager.createGroup(
                in: space,
                name: "Music & Art",
                color: GroupColor.orchid.rawValue,
                iconName: "paintpalette.fill",
            )

            if let group = artGroup {
                let artSites = [
                    "https://en.wikipedia.org/wiki/Baroque_music",
                    "https://en.wikipedia.org/wiki/Impressionism",
                    "https://en.wikipedia.org/wiki/Synthwave",
                    "https://www.youtube.com/",
                    "https://bandcamp.com/",
                ]
                for urlString in artSites {
                    guard let url = URL(string: urlString) else { continue }
                    createTab(url: url, in: space, groupID: group.id, makeActive: false)
                }
            }

            // MARK: - Ungrouped Tabs

            let ungroupedSites = [
                "https://www.google.com/",
                "https://www.apple.com/",
                "https://news.ycombinator.com/",
                "https://lobste.rs/",
                "https://www.reddit.com/r/programming/",
                "https://twitter.com/",
                "https://en.wikipedia.org/wiki/Esoteric_programming_language",
                "https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life",
            ]

            for urlString in ungroupedSites {
                guard let url = URL(string: urlString) else { continue }
                createTab(
                    url: url,
                    in: space,
                    makeActive: false,
                )
            }

            // MARK: - Reference Pane

            addReferenceTab(
                url: URL.staticRequired("https://developer.apple.com/documentation/webkit"),
                title: "WebKit Docs",
                in: space,
            )

            // MARK: - Bookmarks & Favorites

            setupDefaultBookmarks()

            Logger.info("Default development test content created", category: Logger.tabs)
        }

        /// Sets up default bookmarks, folders, and favorites.
        private func setupDefaultBookmarks() {
            // MARK: - App Shortcuts

            bookmarksManager.addAppShortcut(.downloads)
            bookmarksManager.addAppShortcut(.bookmarks)

            // MARK: - Favorite Bookmarks

            // Live favorites (persistent tabs)
            bookmarksManager.createBookmark(
                url: URL.staticRequired("https://en.wikipedia.org/wiki/Recursion"),
                title: "Recursion",
                isFavorite: true,
                favoriteMode: .liveFavorite,
            )

            bookmarksManager.createBookmark(
                url: URL.staticRequired("https://en.wikipedia.org/wiki/Strange_loop"),
                title: "Strange Loop",
                isFavorite: true,
                favoriteMode: .liveFavorite,
            )

            // Shortcut favorites (navigate current tab)
            bookmarksManager.createBookmark(
                url: URL.staticRequired("https://news.ycombinator.com/"),
                title: "Hacker News",
                isFavorite: true,
                favoriteMode: .shortcut,
            )

            bookmarksManager.createBookmark(
                url: URL.staticRequired("https://lobste.rs/"),
                title: "Lobsters",
                isFavorite: true,
                favoriteMode: .shortcut,
            )

            // MARK: - Bookmark Folders

            // Programming folder with subfolders
            let programmingFolder = try? bookmarksManager.createFolder(
                name: "Programming",
                color: GroupColor.steel.rawValue,
                iconName: "chevron.left.forwardslash.chevron.right",
            )

            if let programming = programmingFolder {
                // Languages subfolder
                let languagesFolder = try? bookmarksManager.createFolder(
                    name: "Languages",
                    color: GroupColor.neon.rawValue,
                    iconName: "textformat",
                    parent: programming,
                )

                if let languages = languagesFolder {
                    // Nested: Functional Languages
                    let functionalFolder = try? bookmarksManager.createFolder(
                        name: "Functional",
                        color: GroupColor.violet.rawValue,
                        iconName: "function",
                        parent: languages,
                    )

                    if let functional = functionalFolder {
                        bookmarksManager.createBookmark(
                            url: URL.staticRequired("https://www.haskell.org/"),
                            title: "Haskell",
                            folder: functional,
                        )
                        bookmarksManager.createBookmark(
                            url: URL.staticRequired("https://ocaml.org/"),
                            title: "OCaml",
                            folder: functional,
                        )
                        bookmarksManager.createBookmark(
                            url: URL.staticRequired("https://elixir-lang.org/"),
                            title: "Elixir",
                            folder: functional,
                        )
                    }

                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://www.rust-lang.org/"),
                        title: "Rust",
                        folder: languages,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://swift.org/"),
                        title: "Swift",
                        folder: languages,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://go.dev/"),
                        title: "Go",
                        folder: languages,
                    )
                }

                // Frameworks subfolder
                let frameworksFolder = try? bookmarksManager.createFolder(
                    name: "Frameworks",
                    color: GroupColor.mahogany.rawValue,
                    iconName: "cube.fill",
                    parent: programming,
                )

                if let frameworks = frameworksFolder {
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://developer.apple.com/xcode/swiftui/"),
                        title: "SwiftUI",
                        folder: frameworks,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://react.dev/"),
                        title: "React",
                        folder: frameworks,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://vuejs.org/"),
                        title: "Vue.js",
                        folder: frameworks,
                    )
                }

                // Add Programming folder to favorites
                bookmarksManager.addFolderToFavorites(programming)
            }

            // Reference folder (not favorited)
            let referenceFolder = try? bookmarksManager.createFolder(
                name: "Reference",
                color: GroupColor.emerald.rawValue,
                iconName: "book.closed.fill",
            )

            if let reference = referenceFolder {
                let docsFolder = try? bookmarksManager.createFolder(
                    name: "Documentation",
                    color: GroupColor.emerald.rawValue,
                    iconName: "doc.text.fill",
                    parent: reference,
                )

                if let docs = docsFolder {
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://developer.apple.com/documentation/"),
                        title: "Apple Developer Docs",
                        folder: docs,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://docs.swift.org/swift-book/"),
                        title: "The Swift Book",
                        folder: docs,
                    )
                    bookmarksManager.createBookmark(
                        url: URL.staticRequired("https://devdocs.io/"),
                        title: "DevDocs",
                        folder: docs,
                    )
                }

                bookmarksManager.createBookmark(
                    url: URL.staticRequired("https://en.wikipedia.org/"),
                    title: "Wikipedia",
                    folder: reference,
                )
                bookmarksManager.createBookmark(
                    url: URL.staticRequired("https://stackoverflow.com/"),
                    title: "Stack Overflow",
                    folder: reference,
                )
            }

            // Interesting Articles folder
            let articlesFolder = try? bookmarksManager.createFolder(
                name: "Interesting Articles",
                color: GroupColor.orchid.rawValue,
                iconName: "newspaper.fill",
            )

            if let articles = articlesFolder {
                bookmarksManager.createBookmark(
                    url: URL.staticRequired("https://en.wikipedia.org/wiki/Worse_is_better"),
                    title: "Worse is Better",
                    folder: articles,
                )
                bookmarksManager.createBookmark(
                    url: URL.staticRequired("https://en.wikipedia.org/wiki/The_Cathedral_and_the_Bazaar"),
                    title: "Cathedral and the Bazaar",
                    folder: articles,
                )
                bookmarksManager.createBookmark(
                    url: URL.staticRequired("https://en.wikipedia.org/wiki/Greenspun%27s_tenth_rule"),
                    title: "Greenspun's Tenth Rule",
                    folder: articles,
                )
            }

            Logger.info("Default bookmarks and favorites created", category: Logger.data)
        }
    #endif
}

// MARK: - Memory Warning

extension TabManager {
    func handleMemoryWarning() {
        pagePool.handleMemoryWarning()
    }
}
