import SwiftUI
import WidgetKit

// MARK: - Currently Reading Widget

/// Widget displaying the currently active tab.
///
/// Shows the page title, domain, and favicon for quick reference.
struct CurrentlyReadingWidget: Widget {
    let kind = "CurrentlyReadingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentlyReadingProvider()) { entry in
            CurrentlyReadingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Currently Reading")
        .description("See what page you're currently viewing in Refrax.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Entry

struct CurrentlyReadingEntry: TimelineEntry {
    let date: Date
    let currentTab: CurrentTabData?
    let recentSpaces: [SpaceSummary]
}

// MARK: - Timeline Provider

struct CurrentlyReadingProvider: TimelineProvider {
    func placeholder(in _: Context) -> CurrentlyReadingEntry {
        CurrentlyReadingEntry(
            date: Date(),
            currentTab: WidgetDataStorage.sampleData.currentTab,
            recentSpaces: WidgetDataStorage.sampleData.recentSpaces,
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (CurrentlyReadingEntry) -> Void) {
        let entry = if let data = WidgetDataStorage.read() {
            CurrentlyReadingEntry(
                date: data.lastUpdated,
                currentTab: data.currentTab,
                recentSpaces: data.recentSpaces,
            )
        } else {
            CurrentlyReadingEntry(
                date: Date(),
                currentTab: WidgetDataStorage.sampleData.currentTab,
                recentSpaces: WidgetDataStorage.sampleData.recentSpaces,
            )
        }
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<CurrentlyReadingEntry>) -> Void) {
        let entry = if let data = WidgetDataStorage.read() {
            CurrentlyReadingEntry(
                date: data.lastUpdated,
                currentTab: data.currentTab,
                recentSpaces: data.recentSpaces,
            )
        } else {
            CurrentlyReadingEntry(
                date: Date(),
                currentTab: WidgetDataStorage.sampleData.currentTab,
                recentSpaces: WidgetDataStorage.sampleData.recentSpaces,
            )
        }

        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct CurrentlyReadingWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CurrentlyReadingEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallCurrentlyReadingView(currentTab: entry.currentTab)
        case .systemMedium:
            MediumCurrentlyReadingView(currentTab: entry.currentTab, recentSpaces: entry.recentSpaces)
        default:
            SmallCurrentlyReadingView(currentTab: entry.currentTab)
        }
    }
}

// MARK: - Small Widget

struct SmallCurrentlyReadingView: View {
    let currentTab: CurrentTabData?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "book.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Reading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let tab = currentTab {
                Spacer()

                // Favicon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 40, height: 40)

                    if let base64 = tab.faviconBase64,
                       let data = Data(base64Encoded: base64),
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(tab.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(tab.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if tab.isPlayingAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }

                Text(tab.spaceName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No active tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
        }
        .padding(4)
    }
}

// MARK: - Medium Widget

struct MediumCurrentlyReadingView: View {
    let currentTab: CurrentTabData?
    let recentSpaces: [SpaceSummary]

    var body: some View {
        HStack(spacing: 16) {
            // Left: Current tab
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Currently Reading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let tab = currentTab {
                    Spacer()

                    HStack(spacing: 12) {
                        // Favicon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                                .frame(width: 44, height: 44)

                            if let base64 = tab.faviconBase64,
                               let data = Data(base64Encoded: base64),
                               let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "globe")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(2)

                            HStack(spacing: 4) {
                                Text(tab.domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if tab.isPlayingAudio {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                            }

                            Text(tab.spaceName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "square.on.square.dashed")
                                .font(.title)
                                .foregroundStyle(.quaternary)
                            Text("No active tab")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right: Spaces
            VStack(alignment: .leading, spacing: 4) {
                Text("Spaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(recentSpaces.prefix(4)) { space in
                    SpaceRow(space: space)
                }

                if recentSpaces.isEmpty {
                    Text("No spaces")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .frame(width: 100)
        }
        .padding(4)
    }
}

struct SpaceRow: View {
    let space: SpaceSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: space.iconName)
                .font(.caption)
                .foregroundStyle(spaceColor)
                .frame(width: 16)

            Text(space.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text("\(space.tabCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var spaceColor: Color {
        if let hex = space.colorHex {
            return Color(encoded: hex) ?? .blue
        }
        return .blue
    }
}

// MARK: - Color Extension

extension Color {
    init?(encoded: String) {
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("#") {
            // Legacy hex
            let hex = trimmed.replacingOccurrences(of: "#", with: "")
            var rgb: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&rgb) else { return nil }
            let r = Double((rgb & 0xFF0000) >> 16) / 255.0
            let g = Double((rgb & 0x00FF00) >> 8) / 255.0
            let b = Double(rgb & 0x0000FF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b)
            return
        }

        // Tagged format: colorspace:r,g,b[,a]
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let cs = String(trimmed[..<colon])
        let parts = trimmed[trimmed.index(after: colon)...].split(separator: ",")
        guard parts.count >= 3,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]) else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1.0) : 1.0

        switch cs {
        case "p3":
            self.init(.displayP3, red: r, green: g, blue: b, opacity: a)
        default:
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        }
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    CurrentlyReadingWidget()
} timeline: {
    CurrentlyReadingEntry(
        date: Date(),
        currentTab: WidgetDataStorage.sampleData.currentTab,
        recentSpaces: WidgetDataStorage.sampleData.recentSpaces,
    )
}

#Preview("Medium", as: .systemMedium) {
    CurrentlyReadingWidget()
} timeline: {
    CurrentlyReadingEntry(
        date: Date(),
        currentTab: WidgetDataStorage.sampleData.currentTab,
        recentSpaces: WidgetDataStorage.sampleData.recentSpaces,
    )
}

#Preview("No Tab", as: .systemSmall) {
    CurrentlyReadingWidget()
} timeline: {
    CurrentlyReadingEntry(
        date: Date(),
        currentTab: nil,
        recentSpaces: [],
    )
}
