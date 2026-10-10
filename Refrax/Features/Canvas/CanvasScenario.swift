import AppKit
import Foundation

/// Preset boards for developing the canvas: a fresh space with lab pages laid out
/// in a known arrangement, so a behavior can be tried against the same setup every time.
///
/// Lab pages are `data:` URLs that render a colored page with a topic and a number;
/// their titles are `Topic · n`, which ``CanvasSimilarity`` reads as the topic.
enum CanvasScenario: String, CaseIterable, Sendable {
    /// Twelve tiles in a tidy grid.
    case grid
    /// Six tiles in three overlapping pairs.
    case overlap
    /// Five tiles inside one zone.
    case zone
    /// Three topics scattered across the desk, for lasso and magnets.
    case topics
    /// Sixty tiles packed edge to edge.
    case crowd
    /// Two hundred tabs that have never been on the desk, which sizes itself to hold
    /// them. Their pages are not loaded, so the tiles show placeholders.
    case unplaced

    var title: String {
        switch self {
        case .grid: "Grid of 12"
        case .overlap: "Overlapping pairs"
        case .zone: "One zone of 5"
        case .topics: "Three scattered topics"
        case .crowd: "Crowd of 60"
        case .unplaced: "200 new tabs"
        }
    }

    private enum Palette {
        static let colors = ["#5B7CFA", "#E2607A", "#3EB489", "#F2A93B", "#9B6BE0", "#2BB3C0"]
    }

    /// Builds the scenario in a new space, switches to it, and opens the canvas.
    @MainActor
    static func load(
        _ scenario: CanvasScenario,
        tabManager: TabManager,
        spaceManager: SpaceManager,
        groupManager: TabGroupManager,
        windowState: WindowState,
        canvas: TabCanvasManager,
    ) {
        // The board shows one space; it reopens on the new one below.
        canvas.dismiss(activating: nil)
        let space = spaceManager.createSpace(name: "Lab · \(scenario.title)", iconName: "flask")
        spaceManager.switchToSpaceSync(space, for: windowState)

        let tileSize = TabCanvasManager.Layout.defaultTileSize
        let gap = TabCanvasManager.Layout.gap
        let step = CGSize(width: tileSize.width + gap, height: tileSize.height + gap * 1.5)

        func makeTab(topic: String, number: Int, colorIndex: Int, frame: CGRect?, load: Bool = true) -> Tab {
            let url = labPageURL(topic: topic, number: number, color: Palette.colors[colorIndex % Palette.colors.count])
            let tab = tabManager.createTab(url: url, in: space, makeActive: false, loadImmediately: load, insertionStrategy: .append)
            tab.boardFrame = frame
            return tab
        }

        func gridFrame(_ index: Int, columns: Int, origin: CGPoint = CGPoint(x: 120, y: 120)) -> CGRect {
            CGRect(
                x: origin.x + CGFloat(index % columns) * step.width,
                y: origin.y + CGFloat(index / columns) * step.height,
                width: tileSize.width,
                height: tileSize.height,
            )
        }

        var tabs: [Tab] = []
        switch scenario {
        case .grid:
            for index in 0..<12 {
                tabs.append(makeTab(topic: "Grid", number: index + 1, colorIndex: 0, frame: gridFrame(index, columns: 4)))
            }

        case .overlap:
            for pair in 0..<3 {
                let base = gridFrame(pair, columns: 3)
                tabs.append(makeTab(topic: "Under", number: pair + 1, colorIndex: 1, frame: base))
                tabs.append(makeTab(topic: "Over", number: pair + 1, colorIndex: 2, frame: base.offsetBy(dx: tileSize.width / 2, dy: tileSize.height / 2)))
            }

        case .zone:
            for index in 0..<5 {
                tabs.append(makeTab(topic: "Zone", number: index + 1, colorIndex: 3, frame: gridFrame(index, columns: 3, origin: CGPoint(x: 200, y: 200))))
            }
            if let group = try? groupManager.createGroup(in: space, name: "Reading", color: GroupColor.avocado.rawValue) {
                for tab in tabs {
                    groupManager.moveTabToGroup(tab, group: group, in: space)
                }
            }

        case .topics:
            var generator = SeededGenerator(seed: 7)
            let desk = TabCanvasManager.Layout.minimumDeskSize
            for (topicIndex, topic) in ["Physics", "Chemistry", "Music"].enumerated() {
                for number in 1...4 {
                    let frame = CGRect(
                        x: CGFloat.random(in: 60...(desk.width - tileSize.width - 60), using: &generator),
                        y: CGFloat.random(in: 60...(desk.height - tileSize.height - 60), using: &generator),
                        width: tileSize.width,
                        height: tileSize.height,
                    )
                    tabs.append(makeTab(topic: topic, number: number, colorIndex: topicIndex + 3, frame: frame))
                }
            }

        case .crowd:
            for index in 0..<60 {
                tabs.append(makeTab(topic: "Crowd", number: index + 1, colorIndex: index % Palette.colors.count, frame: gridFrame(index, columns: 8, origin: CGPoint(x: 40, y: 40))))
            }

        case .unplaced:
            for index in 0..<200 {
                tabs.append(makeTab(topic: "New", number: index + 1, colorIndex: index % Palette.colors.count, frame: nil, load: false))
            }
        }

        if let first = tabs.first {
            tabManager.setActiveTab(first, in: windowState)
        }
        tabManager.state.scheduleSave()

        // Give the lab pages a moment to render before their first snapshot.
        Task(name: "Open lab canvas") {
            try? await Task.sleep(for: .seconds(1))
            canvas.show()
        }
    }

    /// A self-contained page: colored background, the topic as a heading, the number large.
    private static func labPageURL(topic: String, number: Int, color: String) -> URL {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(topic) · \(number)</title>
        <style>html,body{margin:0;height:100%;background:\(color);color:#fff;font-family:-apple-system,system-ui;\
        display:flex;flex-direction:column;align-items:center;justify-content:center}\
        h1{font-size:56px;margin:0;font-weight:600}p{font-size:200px;margin:0;font-weight:200;line-height:1}</style></head>
        <body><h1>\(topic)</h1><p>\(number)</p></body></html>
        """
        let encoded = html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "data:text/html;charset=utf-8,\(encoded)")!
    }
}

/// Deterministic random numbers, so a scattered scenario is the same every time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
