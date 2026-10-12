import Foundation

/// Offers the tour's tutorial page while a tour step asks for a page, whatever is typed.
///
/// The tour names the page in its instruction card; this provider puts that page at the
/// top of the lens so Return opens it. With nothing typed the page is the only suggestion
/// and is preselected; with text typed it follows the search row, so typing still searches.
struct TourSuggestionProvider: CommandLensSuggestionProvider {
    let id = "tour"
    let priority = 0
    let groupHeader: String? = nil
    let maxSuggestions = 1

    private let tour: FloatingTourManager

    init(tour: FloatingTourManager) {
        self.tour = tour
    }

    /// The lens asks on the main actor, where the tour lives.
    func shouldProvide(for _: SuggestionContext) -> Bool {
        MainActor.assumeIsolated { tour.requestedPage != nil }
    }

    func suggestions(for _: SuggestionContext) async -> [CommandLensSuggestion] {
        guard let page = tour.requestedPage else { return [] }
        return [CommandLensSuggestion(
            type: .tutorialPage(page),
            text: "\(page.title) · tutorial page",
            description: "A local page to practice on",
            iconName: page.symbol,
            groupHeader: groupHeader,
            isRemovable: false,
            keywordAction: nil,
            url: page.url,
        )]
    }
}
