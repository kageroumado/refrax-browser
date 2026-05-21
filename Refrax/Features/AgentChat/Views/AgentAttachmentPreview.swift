import SwiftUI

/// Thumbnail grid for pending attachments in the chat input.
///
/// Displays image thumbnails with remove buttons.
struct AgentAttachmentPreview: View {
    let attachments: [AgentMessage.ImageAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func attachmentThumbnail(_ attachment: AgentMessage.ImageAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            // Pending attachments always have data (user-added), but handle nil gracefully
            if let data = attachment.data, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            // Remove button
            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    let testData = "test".data(using: .utf8)!
    AgentAttachmentPreview(
        attachments: [
            AgentMessage.ImageAttachment(data: testData, mimeType: "image/png", fileName: "test.png"),
        ],
        onRemove: { _ in },
    )
}
