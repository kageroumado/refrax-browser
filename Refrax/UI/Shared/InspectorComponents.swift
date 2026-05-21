import SwiftUI

// MARK: - Inspector Header

/// Header for inspector panels with title and optional close button.
struct InspectorHeader: View {
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Close Inspector")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Inspector Section

/// A titled section within an inspector panel.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Inspector Row

/// A label-value row for displaying information in an inspector.
struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            content()
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Inspector Value Row

/// A simple label-value row with text content.
struct InspectorValueRow: View {
    let label: String
    let value: String

    var body: some View {
        InspectorRow(label: label) {
            Text(value)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Inspector Link Row

/// A clickable URL row in the inspector.
struct InspectorLinkRow: View {
    let label: String
    let url: URL
    let action: () -> Void

    var body: some View {
        InspectorRow(label: label) {
            Button(action: action) {
                Text(url.absoluteString)
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

// MARK: - Inspector Date Row

/// A row displaying a formatted date.
struct InspectorDateRow: View {
    let label: String
    let date: Date
    var style: DateDisplayStyle = .dateTime

    enum DateDisplayStyle {
        case dateOnly
        case timeOnly
        case dateTime
        case relative
    }

    var body: some View {
        InspectorRow(label: label) {
            switch style {
            case .dateOnly:
                Text(date, style: .date)
            case .timeOnly:
                Text(date, style: .time)
            case .dateTime:
                HStack(spacing: 4) {
                    Text(date, style: .date)
                    Text("at")
                        .foregroundStyle(.secondary)
                    Text(date, style: .time)
                }
            case .relative:
                Text(date, style: .relative)
            }
        }
    }
}

// MARK: - Inspector Duration Row

/// A row displaying a formatted duration.
struct InspectorDurationRow: View {
    let label: String
    let duration: TimeInterval

    var body: some View {
        InspectorValueRow(label: label, value: formatDuration(duration))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "< 1s"
        } else if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        } else {
            let hours = Int(seconds / 3_600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
}

// MARK: - Inspector Divider

/// A styled divider for inspector panels.
struct InspectorDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }
}

// MARK: - Inspector Action Bar

/// A row of action buttons at the bottom of an inspector.
struct InspectorActionBar: View {
    let actions: [InspectorAction]

    struct InspectorAction: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String?
        let style: ActionStyle
        let action: () -> Void

        enum ActionStyle {
            case primary
            case secondary
            case destructive
        }

        init(_ title: String, systemImage: String? = nil, style: ActionStyle = .secondary, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.style = style
            self.action = action
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                actionButton(for: action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func actionButton(for action: InspectorAction) -> some View {
        switch action.style {
        case .primary:
            Button(action: action.action) {
                actionLabel(for: action)
            }
            .buttonStyle(.borderedProminent)
        case .secondary:
            Button(action: action.action) {
                actionLabel(for: action)
            }
            .buttonStyle(.bordered)
        case .destructive:
            Button(role: .destructive, action: action.action) {
                actionLabel(for: action)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func actionLabel(for action: InspectorAction) -> some View {
        if let systemImage = action.systemImage {
            Label(action.title, systemImage: systemImage)
        } else {
            Text(action.title)
        }
    }
}

// MARK: - Inspector Empty State

/// Empty state view for when no item is selected in the inspector.
struct InspectorEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Inspector Favicon

/// Large favicon display for inspector headers.
struct InspectorFavicon: View {
    let faviconData: Data?
    let url: URL
    var size: CGFloat = 48

    var body: some View {
        FaviconView(data: faviconData, url: url, size: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}

// MARK: - Inspector Toggle Row

/// A row with a toggle switch.
struct InspectorToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Inspector Tags Row

/// A row displaying a list of tags.
struct InspectorTagsRow: View {
    let label: String
    let tags: [String]
    var onRemove: ((String) -> Void)?

    var body: some View {
        InspectorRow(label: label) {
            if tags.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        tagView(tag)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagView(_ tag: String) -> some View {
        HStack(spacing: 2) {
            Text(tag)
                .font(.caption)

            if let onRemove {
                Button {
                    onRemove(tag)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appAccentColor.opacity(0.1))
        .foregroundStyle(Color.appAccentColor)
        .clipShape(Capsule())
    }
}
