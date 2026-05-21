import WebKit

/// Swift-friendly async/await wrappers for WebKit private APIs.
///
/// This extension provides ergonomic Swift concurrency wrappers around
/// completion-handler-based private APIs declared in the bridging headers.
///
/// ## Design Principles
/// - All methods are `@MainActor` since WebKit requires main thread access
/// - Completion handlers are converted to async/await using continuations
/// - Error conditions are handled with optional returns or throws
/// - Timeout handling for operations that may hang
///
/// ## Usage
/// ```swift
/// // Wait for rendering before screenshot
/// await webView.waitForPresentationUpdate()
/// let snapshot = try await webView.takeSnapshot(configuration: config)
///
/// // Control display capture audio
/// await webView.setDisplayCaptureState(.active)
///
/// // Play/pause media sessions
/// let success = await webView.playPredominantMediaSession()
/// ```
extension WKWebView {
    // MARK: - Window Moves

    /// Prepares the web view for moving to a new window.
    ///
    /// Call this before moving a WKWebView between windows to reduce visual
    /// artifacts during the transition. The completion handler is called when
    /// the web view is ready to be added to the new window.
    ///
    /// ## Usage
    /// ```swift
    /// await webView.prepareForMove(to: newWindow)
    /// newWindow.contentView?.addSubview(webView)
    /// ```
    ///
    /// - Parameter window: The target window, or nil if removing from window.
    func prepareForMove(to window: NSWindow?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _prepareForMove(to: window) {
                continuation.resume()
            }
        }
    }

    // MARK: - Presentation Updates

    /// Waits for the web view to complete its next presentation update.
    ///
    /// Use this to ensure the web view has finished rendering before performing
    /// operations that require accurate visual state.
    ///
    /// ## Example
    /// ```swift
    /// await webView.waitForPresentationUpdate()
    /// let snapshot = try await webView.takeSnapshot(configuration: config)
    /// ```
    ///
    /// ## Implementation
    /// Wraps `_doAfterNextPresentationUpdate:` with a checked continuation.
    func waitForPresentationUpdate() async {
        await withCheckedContinuation { continuation in
            _do(afterNextPresentationUpdate: {
                continuation.resume()
            })
        }
    }

    // MARK: - Display Capture Control

    /// Sets the display capture state with async/await.
    ///
    /// Use this to enable or disable audio during screen sharing.
    ///
    /// - Parameter state: The desired display capture state.
    ///
    /// ## Example
    /// ```swift
    /// // Enable screen sharing audio
    /// await webView.setDisplayCaptureState(.active)
    ///
    /// // Mute screen sharing audio
    /// await webView.setDisplayCaptureState(.muted)
    /// ```
    @available(macOS 13.0, *)
    func setDisplayCaptureState(_ state: WKDisplayCaptureState) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _setDisplayCaptureState(state) {
                continuation.resume()
            }
        }
    }

    /// Sets the system audio capture state with async/await.
    ///
    /// - Parameter state: The desired system audio capture state.
    @available(macOS 13.0, *)
    func setSystemAudioCaptureState(_ state: WKSystemAudioCaptureState) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _setSystemAudioCaptureState(state) {
                continuation.resume()
            }
        }
    }

    // MARK: - Media Session Control

    /// Plays the predominant media session or resumes Now Playing.
    ///
    /// This is the programmatic equivalent of pressing play on media.
    ///
    /// - Returns: `true` if playback started successfully.
    ///
    /// ## Example
    /// ```swift
    /// if await webView.playPredominantMediaSession() {
    ///     print("Playback started")
    /// }
    /// ```
    @available(macOS 15.0, *)
    func playPredominantMediaSession() async -> Bool {
        await withCheckedContinuation { continuation in
            _playPredominantOrNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Pauses the current Now Playing media session.
    ///
    /// - Returns: `true` if playback was paused.
    @available(macOS 15.0, *)
    func pauseNowPlayingMediaSession() async -> Bool {
        await withCheckedContinuation { continuation in
            _pauseNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Gets the title and artist of the currently playing media.
    ///
    /// - Returns: A tuple of (title, artist), both optional.
    ///
    /// ## Example
    /// ```swift
    /// let (title, artist) = await webView.nowPlayingInfo()
    /// if let title {
    ///     nowPlayingLabel.text = "\(title) - \(artist ?? "Unknown")"
    /// }
    /// ```
    func nowPlayingInfo() async -> (title: String?, artist: String?) {
        await withCheckedContinuation { continuation in
            _nowPlayingMediaTitleAndArtist { title, artist in
                continuation.resume(returning: (title, artist))
            }
        }
    }

    // MARK: - Animation Control

    /// Pauses all CSS and GIF animations on the page.
    ///
    /// ## Example
    /// ```swift
    /// await webView.pauseAllAnimations()
    /// // Take screenshot without animation artifacts
    /// let snapshot = try await webView.takeSnapshot(configuration: config)
    /// await webView.playAllAnimations()
    /// ```
    @available(macOS 13.3, *)
    func pauseAllAnimations() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _pauseAllAnimations {
                continuation.resume()
            }
        }
    }

    /// Resumes all paused animations.
    @available(macOS 13.3, *)
    func playAllAnimations() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _playAllAnimations {
                continuation.resume()
            }
        }
    }

    // MARK: - PDF Export

    /// Takes a PDF snapshot of the web view content.
    ///
    /// - Parameter configuration: Snapshot configuration, or nil for defaults.
    /// - Returns: PDF data on success.
    /// - Throws: Error if snapshot fails.
    ///
    /// ## Example
    /// ```swift
    /// let pdfData = try await webView.takePDFSnapshot()
    /// try pdfData.write(to: saveURL)
    /// ```
    @available(macOS 10.15.4, *)
    func takePDFSnapshot(configuration: WKSnapshotConfiguration? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _takePDFSnapshot(with: configuration) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WKWebViewPrivate",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "PDF snapshot returned nil without error"],
                    ))
                }
            }
        }
    }

    // MARK: - Thumbnail Snapshot with Waiting

    /// Takes a snapshot after waiting for the presentation update.
    ///
    /// This combines `waitForPresentationUpdate()` with `takeSnapshot()`
    /// to ensure accurate visual capture.
    ///
    /// - Parameter configuration: Snapshot configuration, or nil for defaults.
    /// - Returns: The snapshot image.
    /// - Throws: Error if snapshot fails.
    ///
    /// ## Example
    /// ```swift
    /// let config = WKSnapshotConfiguration()
    /// config.snapshotWidth = 320
    /// let image = try await webView.takeAccurateSnapshot(configuration: config)
    /// ```
    func takeAccurateSnapshot(configuration: WKSnapshotConfiguration? = nil) async throws -> NSImage {
        await waitForPresentationUpdate()
        return try await takeSnapshot(configuration: configuration)
    }
}

// MARK: - Thumbnail View Async Helpers

extension _WKThumbnailView {
    /// Requests a snapshot and waits for a brief period for rendering.
    ///
    /// Since `_WKThumbnailView.requestSnapshot()` has no completion handler,
    /// this method waits for a brief period after requesting.
    ///
    /// - Parameter delay: How long to wait for rendering (default 100ms).
    ///
    /// ## Note
    /// The actual rendering may complete before or after this delay.
    /// For guaranteed accuracy, use multiple requests or KVO on snapshotSize.
    func requestSnapshotAsync(delay: Duration = .milliseconds(100)) async {
        requestSnapshot()
        try? await Task.sleep(for: delay)
    }
}
