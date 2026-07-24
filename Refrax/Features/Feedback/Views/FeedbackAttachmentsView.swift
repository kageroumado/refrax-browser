import SwiftUI
import UniformTypeIdentifiers

/// Displays and manages file attachments for a feedback submission.
///
/// Shows auto-attached log files with a badge, allows toggling selection
/// via checkboxes, previewing file contents, and adding new files through
/// the system file importer.
struct FeedbackAttachmentsView: View {
    @Environment(FeedbackManager.self) private var manager
    @State private var showingFileImporter = false
    @State private var previewingAttachment: FeedbackAttachment?

    var body: some View {
        @Bindable var manager = manager

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Attachments")
                    .font(.system(size: Constants.Typography.captionSize, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    showingFileImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add File")
            }

            if manager.attachments.isEmpty {
                emptyState
            } else {
                attachmentList
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $previewingAttachment) { attachment in
            FeedbackAttachmentPreview(attachment: attachment)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        Text("No attachments")
            .font(.system(size: Constants.Typography.captionSize))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private var attachmentList: some View {
        @Bindable var manager = manager

        return VStack(spacing: 0) {
            ForEach($manager.attachments) { $attachment in
                if attachment.id != manager.attachments.first?.id {
                    Divider()
                        .padding(.leading, 32)
                }
                attachmentRow(attachment: $attachment)
            }
        }
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func attachmentRow(attachment: Binding<FeedbackAttachment>) -> some View {
        let value = attachment.wrappedValue

        return HStack(spacing: 6) {
            Toggle(isOn: attachment.isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)

            Image(systemName: iconName(for: value.filename))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 14)

            Text(value.filename)
                .font(.system(size: Constants.Typography.bodySize))
                .lineLimit(1)
                .truncationMode(.middle)

            if value.isAutoAttached {
                Text("auto")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.fill.quaternary, in: Capsule())
            }

            Spacer()

            Text(formattedFileSize(value.fileSize))
                .font(.system(size: Constants.Typography.captionSize))
                .foregroundStyle(.quaternary)
                .monospacedDigit()

            Button {
                previewingAttachment = value
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Preview")

            if !value.isAutoAttached {
                Button {
                    manager.attachments.removeAll { $0.id == value.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    // MARK: - Helpers

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            manager.addAttachment(from: url)
        }
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "log", "txt":
            return "doc.text"
        case "crash", "ips":
            return "exclamationmark.triangle"
        case "png", "jpg", "jpeg", "gif":
            return "photo"
        default:
            return "doc"
        }
    }
}
