import SwiftUI
import WidgetKit

// MARK: - Tab Health Widget

/// Widget displaying browser health statistics from Air Traffic Control.
///
/// Shows tab count, memory usage, crashed tabs, and active media.
struct TabHealthWidget: Widget {
    let kind = "TabHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TabHealthProvider()) { entry in
            TabHealthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Browser Health")
        .description("Monitor your browser's tab count, memory usage, and health status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Entry

struct TabHealthEntry: TimelineEntry {
    let date: Date
    let health: BrowserHealthData
    let topTabs: [TabSummary]
}

// MARK: - Timeline Provider

struct TabHealthProvider: TimelineProvider {
    func placeholder(in _: Context) -> TabHealthEntry {
        TabHealthEntry(
            date: Date(),
            health: WidgetDataStorage.sampleData.browserHealth,
            topTabs: WidgetDataStorage.sampleData.topTabs,
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (TabHealthEntry) -> Void) {
        let entry = if let data = WidgetDataStorage.read() {
            TabHealthEntry(date: data.lastUpdated, health: data.browserHealth, topTabs: data.topTabs)
        } else {
            TabHealthEntry(
                date: Date(),
                health: WidgetDataStorage.sampleData.browserHealth,
                topTabs: WidgetDataStorage.sampleData.topTabs,
            )
        }
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TabHealthEntry>) -> Void) {
        let entry = if let data = WidgetDataStorage.read() {
            TabHealthEntry(date: data.lastUpdated, health: data.browserHealth, topTabs: data.topTabs)
        } else {
            TabHealthEntry(
                date: Date(),
                health: WidgetDataStorage.sampleData.browserHealth,
                topTabs: WidgetDataStorage.sampleData.topTabs,
            )
        }

        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct TabHealthWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TabHealthEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallTabHealthView(health: entry.health)
        case .systemMedium:
            MediumTabHealthView(health: entry.health, topTabs: entry.topTabs)
        default:
            SmallTabHealthView(health: entry.health)
        }
    }
}

// MARK: - Small Widget

struct SmallTabHealthView: View {
    let health: BrowserHealthData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Refrax")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatItem(
                    icon: "square.stack.3d.up",
                    value: "\(health.totalTabCount)",
                    label: "Tabs",
                    color: .blue,
                )

                StatItem(
                    icon: "memorychip",
                    value: formatMemory(health.webContentMemoryMB),
                    label: "Memory",
                    color: memoryColor,
                )

                if health.crashedTabCount > 0 {
                    StatItem(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(health.crashedTabCount)",
                        label: "Crashed",
                        color: .red,
                    )
                } else if health.playingAudioCount > 0 {
                    StatItem(
                        icon: "speaker.wave.2.fill",
                        value: "\(health.playingAudioCount)",
                        label: "Playing",
                        color: .purple,
                    )
                } else {
                    StatItem(
                        icon: "checkmark.circle.fill",
                        value: "OK",
                        label: "Status",
                        color: .green,
                    )
                }

                StatItem(
                    icon: "cpu",
                    value: "\(health.activeProcessCount)",
                    label: "Procs",
                    color: .orange,
                )
            }
        }
        .padding(4)
    }

    private var memoryColor: Color {
        if health.webContentMemoryMB > 4_000 {
            .red
        } else if health.webContentMemoryMB > 2_000 {
            .orange
        } else {
            .green
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1_000 {
            String(format: "%.1fG", mb / 1_000)
        } else {
            String(format: "%.0fM", mb)
        }
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium Widget

struct MediumTabHealthView: View {
    let health: BrowserHealthData
    let topTabs: [TabSummary]

    var body: some View {
        HStack(spacing: 16) {
            // Left: Stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Browser Health")
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(health.totalTabCount) tabs", systemImage: "square.stack.3d.up")
                        Label("\(health.spaceCount) spaces", systemImage: "square.grid.2x2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label(formatMemory(health.webContentMemoryMB), systemImage: "memorychip")
                            .foregroundStyle(memoryColor)
                        Label("\(health.activeProcessCount) procs", systemImage: "cpu")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Status indicators
                HStack(spacing: 8) {
                    if health.crashedTabCount > 0 {
                        StatusBadge(
                            icon: "exclamationmark.triangle.fill",
                            text: "\(health.crashedTabCount) crashed",
                            color: .red,
                        )
                    }
                    if health.playingAudioCount > 0 {
                        StatusBadge(
                            icon: "speaker.wave.2.fill",
                            text: "\(health.playingAudioCount) playing",
                            color: .purple,
                        )
                    }
                    if health.mediaCaptureCount > 0 {
                        StatusBadge(
                            icon: "video.fill",
                            text: "\(health.mediaCaptureCount) capture",
                            color: .green,
                        )
                    }
                    if health.crashedTabCount == 0, health.playingAudioCount == 0, health.mediaCaptureCount == 0 {
                        StatusBadge(
                            icon: "checkmark.circle.fill",
                            text: "All healthy",
                            color: .green,
                        )
                    }
                }
            }

            Divider()

            // Right: Top Tabs
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Tabs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(topTabs.prefix(3)) { tab in
                    TabRow(tab: tab)
                }

                if topTabs.isEmpty {
                    Text("No tabs open")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .padding(4)
    }

    private var memoryColor: Color {
        if health.webContentMemoryMB > 4_000 {
            .red
        } else if health.webContentMemoryMB > 2_000 {
            .orange
        } else {
            .secondary
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1_000 {
            String(format: "%.1f GB", mb / 1_000)
        } else {
            String(format: "%.0f MB", mb)
        }
    }
}

struct StatusBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct TabRow: View {
    let tab: TabSummary

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Circle()
                .fill(tab.hasCrashed ? .red : (tab.isPlayingAudio ? .purple : .green))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
                Text(tab.domain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if tab.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    TabHealthWidget()
} timeline: {
    TabHealthEntry(
        date: Date(),
        health: WidgetDataStorage.sampleData.browserHealth,
        topTabs: WidgetDataStorage.sampleData.topTabs,
    )
}

#Preview("Medium", as: .systemMedium) {
    TabHealthWidget()
} timeline: {
    TabHealthEntry(
        date: Date(),
        health: WidgetDataStorage.sampleData.browserHealth,
        topTabs: WidgetDataStorage.sampleData.topTabs,
    )
}
