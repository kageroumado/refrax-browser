import CoreGraphics
import Foundation

/// Value types for the browser automation program interpreter.
enum ProgramValue: Sendable, CustomStringConvertible {
    case string(String)
    case content(PageContentTree)
    case element(ElementHandle)
    case elementList([ElementHandle])
    case bool(Bool)

    var stringValue: String {
        switch self {
        case let .string(s): s
        case let .bool(b): b ? "true" : "false"
        case let .content(tree): tree.metadata.title
        case let .element(el): el.description
        case let .elementList(els): "[\(els.count) elements]"
        }
    }

    var boolValue: Bool {
        switch self {
        case let .bool(b): b
        case let .string(s): !s.isEmpty
        case let .elementList(els): !els.isEmpty
        case .content, .element: true
        }
    }

    var elementListValue: [ElementHandle]? {
        switch self {
        case let .elementList(els): els
        case let .element(el): [el]
        default: nil
        }
    }

    var description: String {
        switch self {
        case let .string(s): "string(\"\(s)\")"
        case let .bool(b): "bool(\(b))"
        case let .content(tree): "content(\(tree.metadata.title))"
        case let .element(el): "element(\(el.description))"
        case let .elementList(els): "elementList(\(els.count) elements)"
        }
    }
}

// MARK: - Element Handle

/// A resolved element from page content, carrying enough info for interaction and interpolation.
struct ElementHandle: Sendable, Equatable, CustomStringConvertible {
    let ref: String
    let text: String
    let tag: String
    let role: String?
    let href: String?
    let value: String?
    let inputType: String?
    let rect: CGRect?

    /// Accesses element properties by name for `${element.property}` interpolation.
    func property(_ name: String) -> String? {
        switch name {
        case "ref": ref
        case "text": text
        case "tag": tag
        case "role": role
        case "href": href
        case "value": value
        case "type": inputType
        default: nil
        }
    }

    var description: String {
        var parts = "[\(ref)] \(tag)"
        if let role {
            parts += " (\(role))"
        }
        if !text.isEmpty {
            parts += " \"\(text)\""
        }
        return parts
    }
}

// MARK: - Factory

extension ElementHandle {
    /// Creates an ElementHandle from a PageContentNode.
    /// Returns nil if the node has no ref (non-interactive element).
    static func from(_ node: PageContentNode) -> ElementHandle? {
        guard let ref = node.ref else { return nil }
        return ElementHandle(
            ref: ref,
            text: node.name ?? "",
            tag: node.type.tagName,
            role: node.role,
            href: node.ariaAttributes["href"],
            value: node.ariaAttributes["value"],
            inputType: node.ariaAttributes["type"],
            rect: node.rect,
        )
    }
}

// MARK: - NodeType Tag Name

extension PageContentNode.NodeType {
    var tagName: String {
        switch self {
        case .root: "root"
        case .overlay: "overlay"
        case .navigation: "nav"
        case .section: "section"
        case .article: "article"
        case .list: "list"
        case .listItem: "li"
        case .blockquote: "blockquote"
        case .button: "button"
        case .canvas: "canvas"
        case .form: "form"
        case .generic: "div"
        case .text: "text"
        case .link: "a"
        case .image: "img"
        case .formControl: "input"
        case .select: "select"
        case .iframe: "iframe"
        case .scrollable: "scroll"
        case .contentEditable: "editable"
        }
    }
}
