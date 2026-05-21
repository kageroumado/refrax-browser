import CoreGraphics
import Foundation
import Testing
@testable import Refrax

// MARK: - Shared Test Helpers

private func makeNode(
    ref: String? = nil,
    nativeID: String? = nil,
    type: PageContentNode.NodeType = .generic,
    role: String? = nil,
    name: String? = nil,
    rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 50),
    visibility: PageContentNode.Visibility = .visible,
    isInteractive: Bool = false,
    eventListeners: UInt = 0,
    ariaAttributes: [String: String] = [:],
    children: [PageContentNode] = [],
) -> PageContentNode {
    PageContentNode(
        ref: ref,
        nativeID: nativeID,
        type: type,
        role: role,
        name: name,
        rect: rect,
        visibility: visibility,
        isInteractive: isInteractive,
        eventListeners: eventListeners,
        ariaAttributes: ariaAttributes,
        children: children,
    )
}

@MainActor
private func makeTree(
    root: PageContentNode? = nil,
    title: String = "Test Page",
    url: String = "https://example.com",
) -> PageContentTree {
    PageContentTree(
        root: root ?? makeNode(type: .root),
        metadata: .init(title: title, url: url, viewportSize: CGSize(width: 1_200, height: 800)),
        extractedAt: Date(),
    )
}

// MARK: - PageContentTree Tests

@Suite("PageContentTree")
@MainActor
struct PageContentTreeTests {
    // MARK: - Ref Lookup

    @Test("findNode returns node with matching ref")
    func findNodeByRef() {
        let target = makeNode(ref: "e3", type: .button, name: "Submit")
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, children: [
                makeNode(ref: "e1", type: .link(url: "https://a.com")),
                makeNode(ref: "e2", type: .link(url: "https://b.com")),
                target,
            ]),
        ])
        let tree = makeTree(root: root)

        let found = tree.findNode(byRef: "e3")
        #expect(found != nil)
        #expect(found?.name == "Submit")
        #expect(found?.type == .button)
    }

    @Test("findNode returns nil for nonexistent ref")
    func findNodeMissing() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", type: .button),
        ])
        let tree = makeTree(root: root)

        #expect(tree.findNode(byRef: "e99") == nil)
    }

    @Test("nativeID returns WebKit node identifier for ref")
    func nativeIDLookup() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", nativeID: "wk-42", type: .button),
            makeNode(ref: "e2", nativeID: "wk-99", type: .link(url: nil)),
        ])
        let tree = makeTree(root: root)

        #expect(tree.nativeID(forRef: "e1") == "wk-42")
        #expect(tree.nativeID(forRef: "e2") == "wk-99")
        #expect(tree.nativeID(forRef: "e3") == nil)
    }

    // MARK: - Interactive Elements

    @Test("interactiveElements collects all nodes with refs")
    func interactiveElements() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .navigation, children: [
                makeNode(ref: "e1", type: .link(url: "https://a.com"), name: "Home"),
                makeNode(ref: "e2", type: .link(url: "https://b.com"), name: "About"),
            ]),
            makeNode(type: .section, children: [
                makeNode(type: .text(content: "Some text")),
                makeNode(ref: "e3", type: .button, name: "Click Me"),
            ]),
        ])
        let tree = makeTree(root: root)

        let elements = tree.interactiveElements
        #expect(elements.count == 3)
        #expect(elements[0].ref == "e1")
        #expect(elements[0].name == "Home")
        #expect(elements[1].ref == "e2")
        #expect(elements[2].ref == "e3")
        #expect(elements[2].name == "Click Me")
    }

    @Test("interactiveElements returns empty for tree with no refs")
    func interactiveElementsEmpty() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Hello")),
            makeNode(type: .section, children: [
                makeNode(type: .text(content: "World")),
            ]),
        ])
        let tree = makeTree(root: root)

        #expect(tree.interactiveElements.isEmpty)
    }

    // MARK: - NodeType Helpers

    @Test("isLink identifies link nodes")
    func isLink() {
        #expect(PageContentNode.NodeType.link(url: "https://example.com").isLink)
        #expect(PageContentNode.NodeType.link(url: nil).isLink)
        #expect(!PageContentNode.NodeType.button.isLink)
        #expect(!PageContentNode.NodeType.text(content: "hi").isLink)
    }

    @Test("isText identifies text nodes")
    func isText() {
        #expect(PageContentNode.NodeType.text(content: "hello").isText)
        #expect(!PageContentNode.NodeType.link(url: nil).isText)
        #expect(!PageContentNode.NodeType.generic.isText)
    }

    // MARK: - Visibility

    @Test("Visibility has correct raw values")
    func visibilityRawValues() {
        #expect(PageContentNode.Visibility.visible.rawValue == "visible")
        #expect(PageContentNode.Visibility.offscreen.rawValue == "offscreen")
        #expect(PageContentNode.Visibility.collapsed.rawValue == "collapsed")
        #expect(PageContentNode.Visibility.hidden.rawValue == "hidden")
    }
}

// MARK: - PageContentFormatter Tests

@Suite("PageContentFormatter")
@MainActor
struct PageContentFormatterTests {
    // MARK: - Header

    @Test("Output starts with title, URL, and word count")
    func headerFormat() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Hello")),
        ])
        let tree = makeTree(root: root, title: "My Page", url: "https://example.com/page")
        let output = PageContentFormatter.format(tree)

        #expect(output.hasPrefix("# My Page\nURL: https://example.com/page"))
        #expect(output.contains("Words: 1"))
    }

    // MARK: - Text Nodes

    @Test("Text content is quoted")
    func textNodeFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Hello World")),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("- \"Hello World\""))
    }

    @Test("Empty text is skipped")
    func emptyTextSkipped() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "   ")),
            makeNode(type: .text(content: "Visible")),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(!output.contains("\"   \""))
        #expect(output.contains("\"Visible\""))
    }

    @Test("Long text is truncated")
    func longTextTruncated() {
        let longText = String(repeating: "x", count: 300)
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: longText)),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        // Truncated to 200 chars (199 + ellipsis)
        #expect(output.contains("…"))
        #expect(!output.contains(longText))
    }

    // MARK: - Links

    @Test("Link with label and URL")
    func linkFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(
                ref: "e1", type: .link(url: "https://example.com"),
                children: [makeNode(type: .text(content: "Click here"))],
            ),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("LINK \"Click here\" [ref=e1]"))
        #expect(output.contains("→ https://example.com"))
    }

    @Test("Link without label shows tag only")
    func linkNoLabel() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", type: .link(url: "https://example.com")),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("LINK [ref=e1]"))
    }

    // MARK: - Images

    @Test("Image with alt text")
    func imageWithAlt() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .image(alt: "A photo")),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("IMG \"A photo\""))
    }

    @Test("Image without alt text")
    func imageNoAlt() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .image(alt: nil)),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("IMG [no alt]"))
    }

    // MARK: - Buttons

    @Test("Button with name")
    func buttonFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", type: .button, name: "Submit"),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("BTN \"Submit\" [ref=e1]"))
    }

    // MARK: - Form Controls

    @Test("Form control with label and type")
    func formControlFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(
                ref: "e1",
                type: .formControl(controlType: "text", label: "Email", isDisabled: false, isChecked: false),
            ),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("TEXT \"Email\" [ref=e1]"))
    }

    @Test("Disabled checkbox shows tags")
    func disabledCheckedControl() {
        let root = makeNode(type: .root, children: [
            makeNode(
                ref: "e1",
                type: .formControl(controlType: "checkbox", label: "Agree", isDisabled: true, isChecked: true),
            ),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("CHECKBOX \"Agree\" [ref=e1] [disabled] [checked]"))
    }

    // MARK: - Select

    @Test("Select with selected values")
    func selectFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", type: .select(selectedValues: ["Option A", "Option B"])),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("SELECT [ref=e1] [Option A, Option B]"))
    }

    // MARK: - Visibility Tags

    @Test("Hidden nodes are excluded")
    func hiddenNodesExcluded() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Visible"), visibility: .visible),
            makeNode(type: .text(content: "Hidden"), visibility: .hidden),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("\"Visible\""))
        #expect(!output.contains("\"Hidden\""))
    }

    @Test("Offscreen nodes show tag in full mode")
    func offscreenTag() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, name: "Footer", visibility: .offscreen, children: [
                makeNode(type: .text(content: "Footer text")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root), scope: .full)

        #expect(output.contains("[offscreen]"))
    }

    @Test("Viewport mode skips offscreen nodes")
    func viewportSkipsOffscreen() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, name: "Visible", visibility: .visible, children: [
                makeNode(type: .text(content: "Visible text")),
            ]),
            makeNode(type: .section, name: "Below Fold", visibility: .offscreen, children: [
                makeNode(type: .text(content: "Hidden text")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root), scope: .viewport)

        #expect(output.contains("Visible text"))
        #expect(!output.contains("Hidden text"))
        #expect(!output.contains("Below Fold"))
        #expect(output.contains("offscreen elements not shown"))
        #expect(output.contains("visible /"))
    }

    @Test("Formatter includes OCR text in footer section")
    func imageOCRText() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Hello world")),
        ])
        var tree = makeTree(root: root)
        tree.imageOCR = [
            "Image": "ChatGPT apparently got rewarded for using its built-in calculator",
        ]

        let output = PageContentFormatter.format(tree)
        #expect(output.contains("Text detected in images:"))
        #expect(output.contains("ChatGPT apparently got rewarded"))
    }

    @Test("OCR footer not shown when imageOCR is empty")
    func imageNoOCR() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .image(alt: "Photo"), visibility: .visible),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))
        #expect(!output.contains("Text detected in images:"))
        #expect(output.contains("IMG \"Photo\""))
    }

    @Test("Collapsed nodes show tag")
    func collapsedTag() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, name: "Menu", visibility: .collapsed, children: [
                makeNode(type: .text(content: "Item")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("[collapsed]"))
    }

    // MARK: - Landmark Summarization

    @Test("Offscreen nav with many links is summarized")
    func navSummarization() {
        let links = (1 ... 20).map { i in
            makeNode(
                ref: "e\(i)",
                type: .link(url: "https://example.com/\(i)"),
                role: "link",
                children: [makeNode(type: .text(content: "Link \(i)"))],
            )
        }
        let root = makeNode(type: .root, children: [
            makeNode(type: .navigation, name: "Main Nav", visibility: .offscreen, children: links),
        ])
        let output = PageContentFormatter.format(makeTree(root: root), scope: .full)

        // Should be a one-line summary, not 20 individual links
        #expect(output.contains("NAV \"Main Nav\""))
        #expect(output.contains("items"))
        // Should NOT enumerate all 20 links
        #expect(!output.contains("Link 20"))
    }

    @Test("Visible nav with few links is fully rendered")
    func visibleNavFullRender() {
        let links = (1 ... 3).map { i in
            makeNode(
                ref: "e\(i)",
                type: .link(url: nil),
                children: [makeNode(type: .text(content: "Link \(i)"))],
            )
        }
        let root = makeNode(type: .root, children: [
            makeNode(type: .navigation, name: "Small Nav", visibility: .visible, children: links),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        // Should enumerate all links
        #expect(output.contains("Link 1"))
        #expect(output.contains("Link 2"))
        #expect(output.contains("Link 3"))
    }

    // MARK: - Container Formatting

    @Test("Empty unnamed containers are skipped")
    func emptyContainerSkipped() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section),
            makeNode(type: .text(content: "After")),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(!output.contains("SECTION"))
        #expect(output.contains("\"After\""))
    }

    @Test("Named container is rendered")
    func namedContainerRendered() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, name: "Hero"),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("SECTION \"Hero\""))
    }

    // MARK: - Indentation

    @Test("Nested nodes are indented")
    func indentation() throws {
        let root = makeNode(type: .root, children: [
            makeNode(type: .section, name: "Content", children: [
                makeNode(type: .text(content: "Nested text")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        let lines = output.components(separatedBy: "\n")
        let sectionLine = lines.first { $0.contains("SECTION") }
        let textLine = lines.first { $0.contains("Nested text") }

        #expect(sectionLine != nil)
        #expect(textLine != nil)

        // Text should be indented more than section
        let sectionIndent = try #require(sectionLine?.prefix(while: { $0 == " " }).count)
        let textIndent = try #require(textLine?.prefix(while: { $0 == " " }).count)
        #expect(textIndent > sectionIndent)
    }

    // MARK: - Generic Nodes

    @Test("Generic node with name is rendered")
    func genericWithName() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .generic, name: "Cookie Banner", children: [
                makeNode(type: .text(content: "Accept cookies?")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("\"Cookie Banner\""))
        #expect(output.contains("\"Accept cookies?\""))
    }

    @Test("Generic node without name is transparent")
    func genericWithoutName() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .generic, children: [
                makeNode(type: .text(content: "Promoted text")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        // Text should appear at root indentation since generic is transparent
        #expect(output.contains("- \"Promoted text\""))
    }

    // MARK: - Scrollable Nodes

    @Test("Scrollable node is transparent")
    func scrollableTransparent() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .scrollable(contentSize: CGSize(width: 1_200, height: 5_000)), children: [
                makeNode(type: .text(content: "Scrolled content")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(!output.contains("SCROLL"))
        #expect(output.contains("\"Scrolled content\""))
    }

    // MARK: - Content Editable

    @Test("Content editable shows ref")
    func contentEditable() {
        let root = makeNode(type: .root, children: [
            makeNode(ref: "e1", type: .contentEditable(isFocused: true), children: [
                makeNode(type: .text(content: "Draft content")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("EDITABLE [ref=e1]"))
        #expect(output.contains("\"Draft content\""))
    }

    // MARK: - IFrame

    @Test("IFrame shows origin")
    func iframeFormatting() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .iframe(origin: "https://ads.example.com"), children: [
                makeNode(type: .text(content: "Ad content")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("IFRAME \"https://ads.example.com\""))
        #expect(output.contains("\"Ad content\""))
    }

    // MARK: - Footer Detection

    @Test("Footer detected via contentinfo ARIA role")
    func footerDetection() {
        let links = (1 ... 8).map { i in
            makeNode(
                ref: "e\(i)",
                type: .link(url: "https://example.com/\(i)"),
                role: "link",
                children: [makeNode(type: .text(content: "Link \(i)"))],
            )
        }
        let root = makeNode(type: .root, children: [
            makeNode(type: .generic, role: "contentinfo", visibility: .offscreen, children: links),
        ])
        let output = PageContentFormatter.format(makeTree(root: root), scope: .full)

        // Should be rendered as FOOTER landmark with summarization
        #expect(output.contains("FOOTER"))
        #expect(output.contains("items"))
        // Should NOT enumerate all links
        #expect(!output.contains("Link 8"))
    }

    @Test("Visible footer renders children fully")
    func visibleFooterFullRender() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .generic, role: "contentinfo", visibility: .visible, children: [
                makeNode(ref: "e1", type: .link(url: nil), children: [
                    makeNode(type: .text(content: "Privacy")),
                ]),
                makeNode(ref: "e2", type: .link(url: nil), children: [
                    makeNode(type: .text(content: "Terms")),
                ]),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("FOOTER"))
        #expect(output.contains("Privacy"))
        #expect(output.contains("Terms"))
    }

    // MARK: - Word Count

    @Test("Word count is accurate across nested text nodes")
    func wordCount() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .text(content: "Hello world")),
            makeNode(type: .section, children: [
                makeNode(type: .text(content: "Three more words")),
            ]),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("Words: 5"))
    }

    @Test("Word count is zero for tree with no text")
    func wordCountEmpty() {
        let root = makeNode(type: .root, children: [
            makeNode(type: .image(alt: "An image")),
            makeNode(ref: "e1", type: .button, name: "Click"),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("Words: 0"))
    }

    // MARK: - Progressive Collapse

    @Test("Large trees trigger progressive collapse")
    func progressiveCollapse() {
        // Create a tree that's larger than the token budget
        let manyChildren = (1 ... 100).map { i in
            makeNode(
                type: .section, name: "Section \(i)", visibility: .offscreen,
                children: (1 ... 10).map { j in
                    makeNode(type: .text(content: "Content \(i)-\(j)"))
                },
            )
        }
        let root = makeNode(type: .root, children: manyChildren)
        let tree = makeTree(root: root)

        // With a small token budget, offscreen sections should be collapsed
        let output = PageContentFormatter.format(tree, scope: .full, tokenBudget: 500)

        // Should contain "items" summaries for collapsed sections
        #expect(output.contains("items"))
    }

    // MARK: - URL Shortening

    @Test("Short URLs are preserved")
    func shortURLPreserved() {
        let root = makeNode(type: .root, children: [
            makeNode(
                ref: "e1", type: .link(url: "https://example.com/page"),
                children: [makeNode(type: .text(content: "Link"))],
            ),
        ])
        let output = PageContentFormatter.format(makeTree(root: root))

        #expect(output.contains("example.com/page"))
    }

    // MARK: - Complete Tree

    @Test("Full page structure formats correctly")
    func fullPageStructure() {
        let root = makeNode(type: .root, children: [
            // Navigation
            makeNode(type: .navigation, name: "Main", visibility: .visible, children: [
                makeNode(ref: "e1", type: .link(url: nil), children: [
                    makeNode(type: .text(content: "Home")),
                ]),
                makeNode(ref: "e2", type: .link(url: nil), children: [
                    makeNode(type: .text(content: "About")),
                ]),
            ]),
            // Main content
            makeNode(type: .article, name: "Blog Post", children: [
                makeNode(type: .text(content: "Welcome to my blog")),
                makeNode(type: .image(alt: "Hero image")),
                makeNode(ref: "e3", type: .button, name: "Like"),
            ]),
            // Form
            makeNode(type: .form, children: [
                makeNode(
                    ref: "e4",
                    type: .formControl(controlType: "text", label: "Name", isDisabled: false, isChecked: false),
                ),
                makeNode(ref: "e5", type: .button, name: "Submit"),
            ]),
        ])
        let tree = makeTree(root: root, title: "My Blog")
        let output = PageContentFormatter.format(tree)

        // Verify structure
        #expect(output.contains("# My Blog"))
        #expect(output.contains("NAV \"Main\""))
        #expect(output.contains("LINK \"Home\" [ref=e1]"))
        #expect(output.contains("LINK \"About\" [ref=e2]"))
        #expect(output.contains("ARTICLE \"Blog Post\""))
        #expect(output.contains("\"Welcome to my blog\""))
        #expect(output.contains("IMG \"Hero image\""))
        #expect(output.contains("BTN \"Like\" [ref=e3]"))
        #expect(output.contains("TEXT \"Name\" [ref=e4]"))
        #expect(output.contains("BTN \"Submit\" [ref=e5]"))
    }
}
