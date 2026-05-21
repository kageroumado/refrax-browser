import Foundation

/// The role of a participant in a Reference Pane AI chat.
enum ChatRole: Equatable {
    /// A system-level instruction message.
    case system

    /// A message from the user.
    case user

    /// A response from the AI assistant.
    case assistant
}
