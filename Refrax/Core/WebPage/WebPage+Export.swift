import AppKit
import Foundation
import WebKit

// MARK: - Exported Content Configuration

extension WebPage {
    /// A specialized configuration of a specific exportable type that can have specific properties unique to the content type.
    ///
    /// Use this to configure export of webpage content as images or PDFs.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Capture full page as image
    /// let config = WebPage.ExportedContentConfiguration.image(
    ///     region: .contents,
    ///     allowTransparentBackground: false,
    ///     afterScreenUpdates: true
    /// )
    /// let data = try await webPage.exported(as: config)
    ///
    /// // Export as PDF with transparent background
    /// let square = CGRect(x: 0, y: 0, width: 100, height: 100)
    /// let pdfData = try await webPage.exported(as: .pdf(region: .rect(square), allowTransparentBackground: true))
    /// ```
    struct ExportedContentConfiguration: Sendable {
        /// Represents a specific semantic region of a webpage.
        struct Region: Sendable {
            private enum Storage: Sendable {
                case contents
                case rect(CGRect)
            }

            /// A region that corresponds to a rectangle in the page's coordinate system.
            ///
            /// - Parameter rect: The rectangle to use for the region.
            /// - Returns: A ``Region`` that uses the specified rectangle.
            static func rect(_ rect: CGRect) -> Self {
                .init(storage: .rect(rect))
            }

            /// The entire region of the webpage.
            static var contents: Self {
                .init(storage: .contents)
            }

            private let storage: Storage

            private init(storage: Storage) {
                self.storage = storage
            }

            var rect: CGRect? {
                switch storage {
                case .contents: nil
                case let .rect(value): value
                }
            }

            var usesContentsRect: Bool {
                switch storage {
                case .contents: true
                case .rect: false
                }
            }
        }

        enum Storage: Sendable {
            case pdf(Region, allowTransparentBackground: Bool)
            case image(Region, allowTransparentBackground: Bool, snapshotWidth: CGFloat?, afterScreenUpdates: Bool)
        }

        /// A configuration of a webpage for a representation as PDF data.
        ///
        /// - Parameters:
        ///   - region: The region of the page used to generate the PDF.
        ///   - allowTransparentBackground: Indicates whether the PDF may have a transparent background.
        /// - Returns: The PDF configuration of this page that will be used when producing its representation.
        static func pdf(region: Region = .contents, allowTransparentBackground: Bool = false) -> Self {
            .init(storage: .pdf(region, allowTransparentBackground: allowTransparentBackground))
        }

        /// A configuration of a webpage for a representation as image data.
        ///
        /// - Parameters:
        ///   - region: The region of the page used to generate the image.
        ///   - allowTransparentBackground: Indicates whether the image may have a transparent background.
        ///   - snapshotWidth: The width of the captured image, in points.
        ///
        ///     Use this property to scale the generated image to the specified width. The webpage maintains the aspect ratio of the captured content, but scales it to match the width you specify.
        ///
        ///     The default value of this parameter is `nil`, which returns an image whose size matches the original size of the captured region.
        ///
        ///   - afterScreenUpdates: Indicates whether to take the snapshot after incorporating any pending screen updates.
        ///
        /// - Returns: The image configuration of this page that will be used when producing its representation.
        static func image(
            region: Region = .contents,
            allowTransparentBackground: Bool = false,
            snapshotWidth: CGFloat? = nil,
            afterScreenUpdates: Bool = true,
        ) -> Self {
            .init(
                storage: .image(
                    region,
                    allowTransparentBackground: allowTransparentBackground,
                    snapshotWidth: snapshotWidth,
                    afterScreenUpdates: afterScreenUpdates,
                ),
            )
        }

        let storage: Storage

        private init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Export Implementation

extension WebPage {
    /// Using the type's `Transferable` conformance implementation, exports a value as binary data,
    /// optionally with a specified configuration for that type of data.
    ///
    /// For example, you can export a 100 pt by 100 pt region of a webpage as a PDF, and allow it to have a transparent background:
    ///
    /// ```swift
    /// let page = WebPage()
    /// // Load web content and wait for navigation to complete.
    ///
    /// let square = CGRect(x: 0, y: 0, width: 100, height: 100)
    /// let pdf = try await page.exported(as: .pdf(region: .rect(square), allowTransparentBackground: true))
    /// ```
    ///
    /// - Parameter representation: A configuration for a representation for a specific type of data with optional customizable properties.
    /// - Returns: The data with the specified representation type.
    /// - Throws: An error if the specified representation cannot be created from the page.
    func exported(as representation: ExportedContentConfiguration) async throws -> Data {
        switch representation.storage {
        case let .pdf(region, allowTransparentBackground):
            try await pdfRepresentation(region: region, allowTransparentBackground: allowTransparentBackground)
        case let .image(region, allowTransparentBackground, snapshotWidth, afterScreenUpdates):
            try await imageRepresentation(
                region: region,
                allowTransparentBackground: allowTransparentBackground,
                snapshotWidth: snapshotWidth,
                afterScreenUpdates: afterScreenUpdates,
            )
        }
    }

    /// Exports the page as PDF.
    private func pdfRepresentation(
        region: ExportedContentConfiguration.Region,
        allowTransparentBackground: Bool,
    ) async throws -> Data {
        let configuration = WKPDFConfiguration()
        if let rect = region.rect {
            configuration.rect = rect
        }
        configuration.allowTransparentBackground = allowTransparentBackground

        return try await backingWebView.pdf(configuration: configuration)
    }

    /// Exports the page as a PNG image.
    private func imageRepresentation(
        region: ExportedContentConfiguration.Region,
        allowTransparentBackground: Bool,
        snapshotWidth: CGFloat?,
        afterScreenUpdates: Bool,
    ) async throws -> Data {
        let configuration = WKSnapshotConfiguration()

        // Set rect if specific region, otherwise use .null for default behavior
        configuration.rect = region.rect ?? .null

        // Use contents rect mode when capturing entire page content
        if region.usesContentsRect {
            configuration._usesContentsRect = true
        }

        configuration._usesTransparentBackground = allowTransparentBackground
        configuration.snapshotWidth = snapshotWidth.map { NSNumber(value: $0) }
        configuration.afterScreenUpdates = afterScreenUpdates

        let snapshot = try await backingWebView.takeSnapshot(configuration: configuration)

        // Convert to PNG data
        guard let tiffData = snapshot.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.conversionFailed
        }

        return pngData
    }

    /// Exports the page as a web archive.
    private func webArchiveRepresentation() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            backingWebView.createWebArchiveData { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Errors that can occur during export.
    enum ExportError: Error, LocalizedError {
        case conversionFailed
        case pageSourceFailed

        var errorDescription: String? {
            switch self {
            case .conversionFailed:
                "Failed to convert captured image to PNG data"
            case .pageSourceFailed:
                "Failed to retrieve page source"
            }
        }
    }

    // MARK: - Convenience Export Methods (Refrax extensions)

    /// Exports the current page as PDF data.
    ///
    /// - Note: This is a Refrax convenience method.
    /// - Returns: PDF data of the current page.
    /// - Throws: Error if export fails.
    func exportAsPDF() async throws -> Data {
        try await exported(as: .pdf())
    }

    /// Exports the current page as a web archive.
    ///
    /// - Note: This is a Refrax convenience method.
    /// - Returns: Web archive data of the current page.
    /// - Throws: Error if export fails.
    func exportAsWebArchive() async throws -> Data {
        try await webArchiveRepresentation()
    }

    /// Exports the current page as a PNG image.
    ///
    /// - Note: This is a Refrax convenience method.
    /// - Returns: PNG image data of the full page content.
    /// - Throws: Error if export fails.
    func exportAsImage() async throws -> Data {
        try await exported(as: .image())
    }

    /// Exports the current page's HTML source.
    ///
    /// - Note: This is a Refrax convenience method.
    /// - Returns: The page's HTML source as UTF-8 encoded data.
    /// - Throws: Error if JavaScript execution fails.
    func exportAsPageSource() async throws -> Data {
        let js = "return document.documentElement.outerHTML"
        guard let result = try await callJavaScript(js),
              let html = result as? String,
              let data = html.data(using: .utf8) else {
            throw ExportError.pageSourceFailed
        }
        return data
    }

    /// Prints the current page using the system print dialog.
    ///
    /// Uses the underlying WKWebView's print functionality.
    func printPage() {
        guard let window = backingWebView.window else {
            Logger.warning("Cannot print: no window for WKWebView", category: Logger.navigation)
            return
        }

        let printInfo = NSPrintInfo.shared
        let printOperation = backingWebView.printOperation(with: printInfo)

        // Fix for WebKit print view frame initialization issue.
        // The print operation's view must have a non-empty frame before
        // knowsPageRange: is called, otherwise printing fails with:
        // "The NSPrintOperation view's frame was not initialized properly"
        if printOperation.view?.frame.isEmpty == true {
            printOperation.view?.frame = backingWebView.bounds
        }

        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
