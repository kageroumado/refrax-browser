import AppKit
import Observation

/// Tracks the current state of keyboard modifier keys.
///
/// This class monitors modifier key changes using `NSEvent.addLocalMonitorForEvents`
/// and exposes the state as `@Observable` properties for SwiftUI reactivity.
///
/// ## Usage
///
/// ```swift
/// // In your app's environment setup
/// @State private var modifierKeys = ModifierKeysState()
///
/// ContentView()
///     .environment(modifierKeys)
///
/// // In a view
/// @Environment(ModifierKeysState.self) private var modifierKeys
///
/// if modifierKeys.isOptionPressed {
///     // Option key is pressed
/// }
/// ```
@Observable
final class ModifierKeysState {
    // MARK: - State

    /// Whether the Option (Alt) key is currently pressed.
    private(set) var isOptionPressed: Bool = false

    /// Whether the Command key is currently pressed.
    private(set) var isCommandPressed: Bool = false

    /// Whether the Shift key is currently pressed.
    private(set) var isShiftPressed: Bool = false

    /// Whether the Control key is currently pressed.
    private(set) var isControlPressed: Bool = false

    // MARK: - Private

    @ObservationIgnored
    private nonisolated(unsafe) var monitor: Any?

    // MARK: - Initialization

    init() {
        startMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Set initial state
        updateFromFlags(NSEvent.modifierFlags)

        // Monitor for modifier key changes
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateFromFlags(event.modifierFlags)
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func updateFromFlags(_ flags: NSEvent.ModifierFlags) {
        isOptionPressed = flags.contains(.option)
        isCommandPressed = flags.contains(.command)
        isShiftPressed = flags.contains(.shift)
        isControlPressed = flags.contains(.control)
    }
}
