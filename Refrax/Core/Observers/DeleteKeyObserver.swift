import AppKit
import Observation

/// Observes delete/backspace key presses for targeted handling.
///
/// This observer monitors keyboard events using `NSEvent.addLocalMonitorForEvents`
/// and invokes a callback when the delete key is pressed. The callback can return
/// `true` to consume the event (preventing it from propagating to other responders)
/// or `false` to let it through.
///
/// ## Usage
///
/// ```swift
/// @State private var deleteKeyObserver: DeleteKeyObserver?
///
/// .onAppear {
///     let observer = DeleteKeyObserver()
///     observer.onDeletePressed = {
///         if shouldHandleDelete {
///             performDeleteAction()
///             return true // Consume the event
///         }
///         return false // Let TextField handle it
///     }
///     deleteKeyObserver = observer
/// }
/// .onDisappear {
///     deleteKeyObserver?.stopMonitoring()
///     deleteKeyObserver = nil
/// }
/// ```
///
/// ## Key Codes
///
/// - Delete (backspace): keyCode 51
/// - Forward delete: keyCode 117
@Observable
final class DeleteKeyObserver {
    // MARK: - Callback

    /// Callback invoked when delete key is pressed.
    ///
    /// Return `true` to consume the event and prevent it from propagating.
    /// Return `false` to let the event through to other responders (like TextField).
    @ObservationIgnored
    var onDeletePressed: (() -> Bool)?

    // MARK: - Private

    @ObservationIgnored
    private nonisolated(unsafe) var monitor: Any?

    // MARK: - Initialization

    init() {
        startMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Check for delete (backspace) or forward delete
            let isDeleteKey = event.keyCode == 51 || event.keyCode == 117

            if isDeleteKey, let handler = onDeletePressed {
                let consumed = handler()
                if consumed {
                    return nil // Consume the event
                }
            }

            return event // Let the event through
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Stops monitoring for delete key events.
    ///
    /// Call this method before releasing the observer to ensure the event
    /// monitor is properly removed from the system.
    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onDeletePressed = nil
    }
}
