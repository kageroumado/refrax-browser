import Foundation

/// A single message in a Reference Pane AI chat conversation.
struct ChatMessage: Identifiable, Equatable {
    /// Unique identifier for the message.
    let id = UUID()

    /// The role of the message sender (system, user, or assistant).
    let role: ChatRole

    /// The text content of the message.
    let content: String

    /// When the message was created.
    let timestamp = Date()

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role && lhs.content == rhs.content
    }
}
