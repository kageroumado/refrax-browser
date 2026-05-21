/// Classification of tab age based on last access time.
///
/// Used for visual differentiation and automatic cleanup policies.
enum TabAgeCategory: Sendable {
    /// Accessed within the last 6 hours.
    case recent
    
    /// Accessed 6-12 hours ago.
    case old6h
    
    /// Accessed more than 12 hours ago.
    case old12h
}
