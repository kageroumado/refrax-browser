import Foundation

/// A Finder internet location: a property list with one `URL` key, the file a link dragged
/// to the desktop becomes.
nonisolated enum WeblocFile {
    static let pathExtension = "webloc"
    /// The file type a promise of one carries.
    static let typeIdentifier = "com.apple.web-internet-location"

    /// The file's contents for `url`.
    static func data(for url: URL) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
    }

    /// The address a file's contents hold, binary or XML.
    static func url(from data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let string = plist["URL"] as? String else { return nil }
        return URL(string: string)
    }

    /// The file's name, extension included: the page's title made safe for any file system,
    /// else the address's host, else "Untitled".
    static func filename(title: String, url: URL) -> String {
        var name = title
        for (character, replacement) in Self.replacements {
            name = name.replacingOccurrences(of: character, with: replacement)
        }
        name = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > Self.maximumLength {
            name = String(name.prefix(Self.maximumLength)).trimmingCharacters(in: .whitespaces)
        }
        if name.isEmpty || name.allSatisfy({ $0 == "." }) {
            name = url.host() ?? "Untitled"
        }
        return "\(name).\(pathExtension)"
    }

    /// Characters a path or Finder reads specially, and what stands in for each.
    private static let replacements: KeyValuePairs<String, String> = [
        "/": "-", ":": "-", "\\": "-", "|": "-", "?": "", "*": "", "<": "", ">": "", "\"": "'",
    ]

    /// The longest name kept, leaving room for the extension within a file name's 255 bytes.
    private static let maximumLength = 200
}
