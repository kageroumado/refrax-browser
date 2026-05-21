import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for Refrax bookmark drags
    /// This needs to be registered in Info.plist as an exported type
    nonisolated static let refraxBookmark = UTType(exportedAs: "com.refrax.bookmark-drag")
}
