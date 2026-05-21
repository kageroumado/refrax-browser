import Foundation
import WebKit

extension WebPage {
    /// An observable representation of a webpage's previously loaded resources.
    ///
    /// This type can be used to facilitate navigating to prior or subsequent loaded resources
    /// and for observing when new entries get added or removed.
    ///
    /// In this example, the back-forward list is used to create a SwiftUI View to facilitate navigating to
    /// previous or next items:
    ///
    /// ```swift
    /// private struct BackForwardMenuView: View {
    ///     struct LabelConfiguration {
    ///         let text: String
    ///         let systemImage: String
    ///     }
    ///
    ///     let list: [WebPage.BackForwardList.Item]
    ///     let label: LabelConfiguration
    ///     let navigateToItem: (WebPage.BackForwardList.Item) -> Void
    ///
    ///     var body: some View {
    ///         Menu {
    ///             ForEach(list) { item in
    ///                 Button(item.title ?? item.url.absoluteString) {
    ///                     navigateToItem(item)
    ///                 }
    ///             }
    ///         } label: {
    ///             Label(label.text, systemImage: label.systemImage)
    ///                 .labelStyle(.iconOnly)
    ///         } primaryAction: {
    ///             navigateToItem(list.first!)
    ///         }
    ///         .disabled(list.isEmpty)
    ///     }
    /// }
    /// ```
    struct BackForwardList {
        init(_ wrapped: WKBackForwardList? = nil) {
            self.wrapped = wrapped
        }

        /// The array of items that precede the current item.
        ///
        /// The items are in the order in which the page originally visited them.
        var backList: [Item] {
            wrapped?.backList.map(Item.init(_:)) ?? []
        }

        /// The current item.
        ///
        /// When the webpage has not loaded any resources, this value will be `nil`.
        var currentItem: Item? {
            wrapped?.currentItem.map(Item.init(_:))
        }

        /// The array of items that follow the current item.
        ///
        /// The items are in the order in which they were originally visited.
        var forwardList: [Item] {
            wrapped?.forwardList.map(Item.init(_:)) ?? []
        }

        private var wrapped: WKBackForwardList?

        /// Accesses the item at the relative offset from the current item.
        ///
        /// - Parameter index: The offset of the desired item from the current item. Specify `0` for the current item,
        /// `-1` for the immediately preceding item, `1` for the immediately following item, and so on.
        /// - Returns: The item at the specified offset from the current item, or `nil` if the index exceeds the limits of the list.
        subscript(_ index: Int) -> Item? {
            wrapped?.item(at: index).map(Item.init(_:))
        }

        // MARK: - Additional Convenience (Refrax extensions)

        /// Whether there are items in the back list.
        var canGoBack: Bool {
            !backList.isEmpty
        }

        /// Whether there are items in the forward list.
        var canGoForward: Bool {
            !forwardList.isEmpty
        }

        /// The total number of items in the list.
        var count: Int {
            backList.count + (currentItem != nil ? 1 : 0) + forwardList.count
        }

        /// All items in the list, in order from oldest to newest.
        var allItems: [Item] {
            backList + (currentItem.map { [$0] } ?? []) + forwardList
        }

    }
}

// MARK: - Back-Forward List Item

extension WebPage.BackForwardList {
    /// A representation of a resource that a webpage previously visited.
    ///
    /// Two items with equal titles, urls, and initial urls may not necessarily be equal to one another.
    struct Item: Equatable, Identifiable, Sendable {
        /// An opaque type representing the identifier for an item.
        struct ID: Hashable, Sendable {
            private let value = UUID()
        }

        init(_ wrapped: WKBackForwardListItem) {
            self.wrapped = wrapped

            self.title = wrapped.title
            self.url = wrapped.url
            self.initialURL = wrapped.initialURL
        }

        /// The unique identifier for the item.
        let id: ID = .init()

        /// The title of the page this item represents.
        ///
        /// If the resource this item represents does not have a title specified, this value will be `nil`.
        let title: String?

        /// The url of the page this item represents, after having resolved all redirects.
        let url: URL

        /// The source URL that originally asked to load the resource.
        let initialURL: URL

        let wrapped: WKBackForwardListItem
    }
}
