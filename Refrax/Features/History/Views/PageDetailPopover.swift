import SwiftUI

/// Popover detail view for history graph nodes.
///
/// Shows comprehensive information about a visited page when clicking a node in the graph.
///
/// ## Visual Layout
///
/// ```
/// ┌──────────────────────────────────────┐
/// │  Page Details                      ✕ │
/// ├──────────────────────────────────────┤
/// │                                      │
/// │  Title:       SwiftUI Documentation  │
/// │  URL:         developer.apple.com... │
/// │                                      │
/// │  Visited:         Nov 15, 21:45     │
/// │  Closed:          Nov 15, 22:30     │
/// │                                      │
/// │  Time Spent:      45m 12s           │
/// │                                      │
/// │  Opened From:                        │
/// │    Hacker News Discussion            │
/// │    news.ycombinator.com...          │
/// │                                      │
/// │  Opened Pages:    2 page(s)         │
/// │                                      │
/// ├──────────────────────────────────────┤
/// │  [Open in New Tab]        [Copy URL] │
/// └──────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// .popover(isPresented: $showPopover) {
///     PageDetailPopover(
///         node: selectedNode,
///         onOpenInNewTab: { openURL(node.entry.url) },
///         onDismiss: { showPopover = false }
///     )
/// }
/// ```
struct PageDetailPopover: View {
    let node: GraphNode
    let onOpenInNewTab: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Page Details")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Title
                DetailRow(label: "Title") {
                    HStack(spacing: 4) {
                        Text(node.entry.title ?? "Untitled")
                            .textSelection(.enabled)
                            .foregroundStyle(node.entry.failedToLoad ? .secondary : .primary)

                        if node.entry.failedToLoad {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                // URL
                DetailRow(label: "URL") {
                    Text(node.entry.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                // Failed load status
                if node.entry.failedToLoad {
                    DetailRow(label: "Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                            Text(failedStatusDescription)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Divider()

                // Times
                DetailRow(label: "Visited") {
                    Text(node.entry.visitedAt, style: .date)
                    Text(node.entry.visitedAt, style: .time)
                }

                if let closedAt = node.entry.closedAt {
                    DetailRow(label: "Closed") {
                        Text(closedAt, style: .date)
                        Text(closedAt, style: .time)
                    }
                } else if !node.entry.failedToLoad {
                    DetailRow(label: "Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Still Open")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Stats
                DetailRow(label: "Time Spent") {
                    Text(formatDuration(node.entry.timeSpent))
                }
                
                // Parent page
                if let parent = node.entry.parent {
                    Divider()
                    
                    DetailRow(label: "Opened From") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parent.title ?? "Untitled")
                                .font(.caption)
                            
                            Text(parent.url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Children count
                if !node.entry.children.isEmpty {
                    DetailRow(label: "Opened Pages") {
                        Text("\(node.entry.children.count) page(s)")
                    }
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button(action: onOpenInNewTab) {
                    Label("Open in New Tab", systemImage: "plus.square")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Copy URL") {
                    copyURL()
                }
            }
        }
        .padding()
        .frame(width: 350)
    }
    
    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.entry.url.absoluteString, forType: .string)
    }

    /// Human-readable description for failed load status.
    private var failedStatusDescription: String {
        guard let code = node.entry.httpStatusCode else {
            return "Failed to load"
        }
        switch code {
        case 0:
            return "Network unreachable"
        case 404:
            return "Page not found"
        case 408:
            return "Connection timed out"
        case 495:
            return "SSL certificate error"
        case 503:
            return "Service unavailable"
        default:
            return "Error \(code)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
        } else {
            let hours = Int(seconds / 3_600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

/// Helper view for detail rows with label-value layout.
private struct DetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    PageDetailPopover(
        node: GraphNode(
            entry: HistoryEntry(
                url: URL.staticRequired("https://developer.apple.com"),
                title: "Apple Developer Documentation",
            ),
            level: 0,
            frame: .zero,
            spaceColor: .blue,
        ),
        onOpenInNewTab: {},
        onDismiss: {},
    )
}
