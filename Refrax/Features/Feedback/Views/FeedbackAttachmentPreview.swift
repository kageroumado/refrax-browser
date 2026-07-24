import SwiftUI

/// Preview for a single feedback attachment.
///
/// Displays text content for log files (`.log`, `.txt`, `.crash`, `.ips`)
/// in a scrollable monospaced view. For other file types, shows basic
/// file metadata.
struct FeedbackAttachmentPreview: View {
    let attachment: FeedbackAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var textContent: String?
    @State private var imageContent: NSImage?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 500, height: 400)
        .task {
            loadContent()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.headline)
                Text(formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView {
                Label("Unable to Preview", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if let text = textContent {
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if let image = imageContent {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isTextFile || isImageFile {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            fileInfoView
        }
    }

    private var fileInfoView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(attachment.filename)
                .font(.title3)
            Text(formattedFileSize)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Preview not available for this file type.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var isTextFile: Bool {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        return ["log", "txt", "crash", "ips", "json", "xml", "csv"].contains(ext)
    }

    private var isImageFile: Bool {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"].contains(ext)
    }

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file)
    }

    private func loadContent() {
        if isImageFile {
            loadImage()
        } else if isTextFile {
            loadText()
        }
    }

    private func loadText() {
        do {
            let data = try Data(contentsOf: attachment.url)
            // Limit display to 1 MB to avoid UI performance issues
            let maxDisplayBytes = 1_048_576
            if data.count > maxDisplayBytes {
                let truncated = data.prefix(maxDisplayBytes)
                textContent = (String(data: truncated, encoding: .utf8) ?? "")
                    + "\n\n--- Truncated (\(formattedFileSize) total) ---"
            } else {
                textContent = String(data: data, encoding: .utf8)
                    ?? "Unable to decode file as text."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadImage() {
        guard let image = NSImage(contentsOf: attachment.url) else {
            loadError = "Unable to load image."
            return
        }
        imageContent = image
    }
}
