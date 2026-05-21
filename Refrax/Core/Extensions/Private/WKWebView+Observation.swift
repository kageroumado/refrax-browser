import Foundation
import Observation
import Synchronization
import WebKit

// MARK: - WKWebView+Observation

// KVO-to-Observation bridge for WebKit private properties.
//
// This file provides tools to observe WebKit's KVO-compliant private properties
// using Swift's Observation framework, enabling SwiftUI reactivity.
//
// ## Architecture
// WebKit's private properties (like `_isPlayingAudio`, `_webProcessState`) are
// KVO-compliant but don't work with Swift Observation directly. This bridge:
// 1. Uses NSKeyValueObservation to watch the private properties
// 2. Updates an `@Observable` wrapper when changes occur
// 3. SwiftUI views can then react to the wrapper's published properties
//
// ## Usage
// ```swift
// @Observable
// final class TabStateObserver {
//     private(set) var isPlayingAudio = false
//     private(set) var processState: _WKWebProcessState = .notRunning
//
//     private var observations = WebKitObservationBag()
//
//     func observe(_ webView: WKWebView) {
//         observations.observe(webView, keyPath: "_isPlayingAudio") { [weak self] in
//             self?.isPlayingAudio = webView.value(forKey: "_isPlayingAudio") as? Bool ?? false
//         }
//     }
// }
// ```

// MARK: - KVO Observation Storage

/// Non-copyable storage for KVO observations that handles cleanup in deinit.
///
/// Based on the pattern from WebPage's KeyValueObservations.
struct WebKitKVOStorage: ~Copyable {
    var wrappers: [KVOWrapper] = []

    mutating func add(_ wrapper: KVOWrapper) {
        wrappers.append(wrapper)
    }

    mutating func invalidateAll() {
        for wrapper in wrappers {
            wrapper.invalidate()
        }
        wrappers.removeAll()
    }

    deinit {
        for wrapper in wrappers {
            wrapper.invalidate()
        }
    }
}

// MARK: - KVO Wrapper

/// Internal wrapper for block-based KVO of private properties.
///
/// Marked as nonisolated because KVO callbacks can come from any thread,
/// but dispatches to main actor for actual processing.
final class KVOWrapper: NSObject, @unchecked Sendable {
    nonisolated(unsafe) weak var object: NSObject?
    nonisolated let keyPath: String
    private nonisolated(unsafe) let handler: () -> Void
    private let _isInvalidated = Mutex(false)
    nonisolated var isInvalidated: Bool { _isInvalidated.withLock { $0 } }

    nonisolated init(object: NSObject, keyPath: String, handler: @escaping () -> Void) {
        self.object = object
        self.keyPath = keyPath
        self.handler = handler
        super.init()
    }

    // KVO callback - must be nonisolated since it can be called from any thread
    // Block-based KVO doesn't support nonisolated callbacks
    // swiftlint:disable:next block_based_kvo
    override nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of _: Any?,
        change _: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?,
    ) {
        guard !isInvalidated, keyPath == self.keyPath else { return }
        handler()
    }

    nonisolated func invalidate() {
        let alreadyInvalidated = _isInvalidated.withLock {
            let was = $0
            $0 = true
            return was
        }
        guard !alreadyInvalidated else { return }
        object?.removeObserver(self, forKeyPath: keyPath)
    }
}

// MARK: - Observation Bag

/// A container for managing multiple WebKit KVO observations.
///
/// Use this to group related observations and invalidate them together.
///
/// ## Example
/// ```swift
/// class MediaObserver {
///     private var observations = WebKitObservationBag()
///
///     func startObserving(_ webView: WKWebView) {
///         observations.observe(webView, keyPath: "_isPlayingAudio") { [weak self] in
///             self?.updateAudioState(webView)
///         }
///
///         observations.observe(webView, keyPath: "_mediaMutedState") { [weak self] in
///             self?.updateMuteState(webView)
///         }
///     }
///
///     func stopObserving() {
///         observations.invalidateAll()
///     }
/// }
/// ```
final class WebKitObservationBag {
    private var storage = WebKitKVOStorage()

    init() {}

    /// Observes a KVO-compliant private property on an object.
    ///
    /// - Parameters:
    ///   - object: The object to observe (typically WKWebView).
    ///   - keyPath: The private property key path (e.g., "_isPlayingAudio").
    ///   - options: KVO options (default includes .initial and .new).
    ///   - onChange: Called when the property changes.
    func observe(
        _ object: some NSObject,
        keyPath: String,
        options: NSKeyValueObservingOptions = [.initial, .new],
        onChange: @escaping () -> Void,
    ) {
        let wrapper = KVOWrapper(object: object, keyPath: keyPath, handler: onChange)
        object.addObserver(wrapper, forKeyPath: keyPath, options: options, context: nil)
        storage.add(wrapper)
    }

    /// Invalidates all observations.
    func invalidateAll() {
        storage.invalidateAll()
    }

    /// The number of active observations.
    var count: Int {
        storage.wrappers.count
    }
}

// MARK: - WKWebView Convenience Extensions

extension WKWebView {
    /// Observes a private boolean property.
    ///
    /// - Parameters:
    ///   - keyPath: The private property key path.
    ///   - onChange: Called with the new value when it changes.
    /// - Returns: An observation bag containing the token.
    ///
    /// ## Example
    /// ```swift
    /// let bag = webView.observePrivateBool("_isPlayingAudio") { isPlaying in
    ///     self.audioIndicator.isHidden = !isPlaying
    /// }
    /// // Later: bag.invalidateAll()
    /// ```
    func observePrivateBool(
        _ keyPath: String,
        onChange: @escaping (Bool) -> Void,
    ) -> WebKitObservationBag {
        let bag = WebKitObservationBag()
        bag.observe(self, keyPath: keyPath, options: [.initial, .new]) { [weak self] in
            let newValue = self?.value(forKey: keyPath) as? Bool ?? false
            onChange(newValue)
        }
        return bag
    }

    /// Observes a private integer property.
    ///
    /// - Parameters:
    ///   - keyPath: The private property key path.
    ///   - onChange: Called with the new value when it changes.
    /// - Returns: An observation bag containing the token.
    func observePrivateInt(
        _ keyPath: String,
        onChange: @escaping (Int) -> Void,
    ) -> WebKitObservationBag {
        let bag = WebKitObservationBag()
        bag.observe(self, keyPath: keyPath, options: [.initial, .new]) { [weak self] in
            let newValue = self?.value(forKey: keyPath) as? Int ?? 0
            onChange(newValue)
        }
        return bag
    }

    /// Observes the web process state.
    ///
    /// - Parameter onChange: Called when the process state changes.
    /// - Returns: An observation bag containing the token.
    ///
    /// ## Example
    /// ```swift
    /// let bag = webView.observeProcessState { state in
    ///     switch state {
    ///     case .notRunning:
    ///         self.showSuspendedIndicator()
    ///     case .foreground:
    ///         self.showActiveIndicator()
    ///     default:
    ///         self.showBackgroundIndicator()
    ///     }
    /// }
    /// ```
    @available(macOS 15.4, *)
    func observeProcessState(
        onChange: @escaping (_WKWebProcessState) -> Void,
    ) -> WebKitObservationBag {
        let bag = WebKitObservationBag()
        bag.observe(self, keyPath: "_webProcessState", options: [.initial, .new]) { [weak self] in
            guard let self else { return }
            let state = _webProcessState
            onChange(state)
        }
        return bag
    }
}

// MARK: - Observable State Wrappers

/// An observable wrapper for WKWebView audio state.
///
/// Bridges WebKit's KVO-based audio properties to Swift Observation,
/// enabling SwiftUI views to react to audio state changes.
///
/// ## Usage
/// ```swift
/// let audioObserver = WKWebViewAudioObserver()
/// audioObserver.observe(webView)
///
/// // In SwiftUI
/// if audioObserver.isPlaying {
///     Image(systemName: "speaker.wave.2.fill")
/// }
/// ```
@Observable
final class WKWebViewAudioObserver {
    /// Whether the web view is playing audio.
    private(set) var isPlaying: Bool = false

    /// Whether audio is muted.
    private(set) var isMuted: Bool = false

    /// The raw media muted state bitmask.
    private(set) var mutedState: UInt = 0

    private weak var webView: WKWebView?
    private var observations = WebKitObservationBag()

    init() {}

    /// Starts observing a web view's audio state.
    ///
    /// - Parameter webView: The web view to observe, or nil to stop.
    func observe(_ webView: WKWebView?) {
        observations.invalidateAll()
        self.webView = webView

        guard let webView else {
            isPlaying = false
            isMuted = false
            mutedState = 0
            return
        }

        // Observe playing state
        observations.observe(webView, keyPath: "_isPlayingAudio") { [weak self, weak webView] in
            guard let self, let webView else { return }
            isPlaying = webView.value(forKey: "_isPlayingAudio") as? Bool ?? false
        }

        observations.observe(webView, keyPath: "_mediaMutedState") { [weak self, weak webView] in
            guard let self, let webView else { return }
            let state = webView.value(forKey: "_mediaMutedState") as? UInt ?? 0
            mutedState = state
            isMuted = (state & 1) != 0 // _WKMediaAudioMuted = 1 << 0
        }
    }

    /// Manually refreshes the audio state.
    ///
    /// Call after programmatically changing mute state, since `_setPageMuted:`
    /// doesn't trigger KVO notifications.
    func refresh() {
        guard let webView else { return }
        isPlaying = webView.value(forKey: "_isPlayingAudio") as? Bool ?? false
        let state = webView.value(forKey: "_mediaMutedState") as? UInt ?? 0
        mutedState = state
        isMuted = (state & 1) != 0
    }
}

/// An observable wrapper for WKWebView process state.
///
/// Bridges WebKit's KVO-based process state to Swift Observation.
///
/// ## Availability
/// Requires macOS 15.4+ for process state monitoring.
@Observable
@available(macOS 15.4, *)
final class WKWebViewProcessObserver {
    /// The current web process state.
    private(set) var state: _WKWebProcessState = .notRunning

    /// Whether the web process is running (foreground or background).
    var isRunning: Bool {
        state == .foreground || state == .background
    }

    /// Whether the tab needs to be reloaded.
    var needsReload: Bool {
        state == .notRunning
    }

    private weak var webView: WKWebView?
    private var observations = WebKitObservationBag()

    init() {}

    /// Starts observing a web view's process state.
    func observe(_ webView: WKWebView?) {
        observations.invalidateAll()
        self.webView = webView

        guard let webView else {
            state = .notRunning
            return
        }

        observations.observe(webView, keyPath: "_webProcessState") { [weak self, weak webView] in
            guard let self, let webView else { return }
            state = webView._webProcessState
        }
    }
}
