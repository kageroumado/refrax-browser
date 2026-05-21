/**
 * WKOpenPanelParametersPrivate.h
 * Refrax Browser
 *
 * Private extensions to WKOpenPanelParameters for file input handling.
 *
 * These properties expose the file type restrictions specified by the HTML
 * `<input type="file" accept="...">` attribute, allowing the file picker
 * to be properly configured with allowed types.
 *
 * ## Properties
 *
 * - `_acceptedMIMETypes`: MIME types from the accept attribute (e.g., "image/png", "application/pdf")
 * - `_acceptedFileExtensions`: File extensions parsed from the accept attribute (e.g., ".jpg", ".pdf")
 * - `_allowedFileExtensions`: Normalized file extensions (macOS 11+, preferred)
 *
 * ## Usage
 *
 * Use `_allowedFileExtensions` on macOS 11+ for the most reliable results.
 * Fall back to `_acceptedFileExtensions` or `_acceptedMIMETypes` on older systems.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKOpenPanelParametersPrivate.h
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions. Refrax is distributed
 * outside the App Store.
 *
 * Last verified: WebKit trunk (February 2025)
 */

#ifndef WKOpenPanelParametersPrivate_h
#define WKOpenPanelParametersPrivate_h

#import <WebKit/WebKit.h>

@interface WKOpenPanelParameters (WKPrivate)

/// MIME types accepted by the file input element.
///
/// These come directly from the `accept` attribute of the HTML element.
/// Common values include:
/// - "image/*" for any image
/// - "image/png" for specific image types
/// - "application/pdf" for PDFs
/// - ".jpg,.png" (extension format, also parsed)
///
/// ## Availability
/// macOS 10.13.4+
@property (nonatomic, readonly, copy) NSArray<NSString *> *_acceptedMIMETypes API_AVAILABLE(macos(10.13.4));

/// File extensions parsed from the accept attribute.
///
/// WebKit normalizes the accept string and extracts file extensions.
/// Extensions are returned without the leading dot (e.g., "jpg" not ".jpg").
///
/// ## Availability
/// macOS 10.13.4+
@property (nonatomic, readonly, copy) NSArray<NSString *> *_acceptedFileExtensions API_AVAILABLE(macos(10.13.4));

/// Normalized file extensions for the file input.
///
/// Preferred on macOS 11+ as it provides better normalization than
/// `_acceptedFileExtensions`. Extensions are without the leading dot.
///
/// ## Availability
/// macOS 11.0+
@property (nonatomic, readonly, copy) NSArray<NSString *> *_allowedFileExtensions API_AVAILABLE(macos(11.0));

@end

#endif /* WKOpenPanelParametersPrivate_h */
