import Foundation

/// Shim for `browser.alarms` API using Swift timers.
///
/// Implements the WebExtensions alarms API for scheduling periodic or one-time
/// callbacks. Uses `DispatchSourceTimer` for precise timing.
///
/// ## Limitations
///
/// - Alarms are not persisted across app restarts (unlike Chrome which persists them)
/// - Minimum delay/period is 1 second (Chrome enforces 1 minute for packed extensions)
/// - Alarms only fire while the app is running
///
/// ## Thread Safety
///
/// All operations are MainActor-isolated. Timers fire on the main queue.

final class AlarmsShim: ExtensionShim {
    // MARK: - Types

    /// An active alarm.
    struct Alarm {
        let name: String
        let extensionID: String
        let scheduledTime: Date
        let periodInMinutes: Double?
        var timer: any DispatchSourceTimer
    }

    // MARK: - Properties

    /// Active alarms keyed by "{extensionID}:{name}".
    private var alarms: [String: Alarm] = [:]

    /// Callbacks to invoke when alarms fire.
    private var onAlarmCallbacks: [(String, String) -> Void] = []

    // MARK: - ExtensionShim Protocol

    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any? {
        switch method {
        case "create":
            let name = args["name"] as? String ?? ""
            guard let alarmInfo = args["alarmInfo"] as? [String: Any] else {
                throw ShimError.invalidArguments("'alarmInfo' is required")
            }
            try create(name: name, alarmInfo: alarmInfo, extensionID: extensionID)
            return nil

        case "get":
            let name = args["name"] as? String ?? ""
            return get(name: name, extensionID: extensionID)

        case "getAll":
            return getAll(extensionID: extensionID)

        case "clear":
            let name = args["name"] as? String ?? ""
            return clear(name: name, extensionID: extensionID)

        case "clearAll":
            return clearAll(extensionID: extensionID)

        default:
            throw ShimError.unsupportedMethod(method)
        }
    }

    // MARK: - Alarm Operations

    /// Creates an alarm.
    ///
    /// - Parameters:
    ///   - name: The alarm name (empty string for unnamed alarm).
    ///   - alarmInfo: Object with `when`, `delayInMinutes`, and/or `periodInMinutes`.
    ///   - extensionID: The calling extension's identifier.
    private func create(name: String, alarmInfo: [String: Any], extensionID: String) throws {
        let key = "\(extensionID):\(name)"

        // Cancel existing alarm with same name
        if let existing = alarms[key] {
            existing.timer.cancel()
        }

        // Calculate when to fire
        let scheduledTime: Date
        let delayInterval: TimeInterval

        if let when = alarmInfo["when"] as? Double {
            // Absolute time in milliseconds since epoch
            scheduledTime = Date(timeIntervalSince1970: when / 1_000)
            delayInterval = scheduledTime.timeIntervalSinceNow
        } else if let delayInMinutes = alarmInfo["delayInMinutes"] as? Double {
            delayInterval = delayInMinutes * 60
            scheduledTime = Date().addingTimeInterval(delayInterval)
        } else if let periodInMinutes = alarmInfo["periodInMinutes"] as? Double {
            // If only period is specified, first fire is after one period
            delayInterval = periodInMinutes * 60
            scheduledTime = Date().addingTimeInterval(delayInterval)
        } else {
            throw ShimError.invalidArguments("Must specify 'when', 'delayInMinutes', or 'periodInMinutes'")
        }

        // Minimum delay of 1 second
        let actualDelay = max(delayInterval, 1.0)

        let periodInMinutes = alarmInfo["periodInMinutes"] as? Double

        // Create the timer
        let timer = DispatchSource.makeTimerSource(queue: .main)

        if let period = periodInMinutes {
            // Repeating alarm
            timer.schedule(
                deadline: .now() + actualDelay,
                repeating: period * 60,
            )
        } else {
            // One-shot alarm
            timer.schedule(deadline: .now() + actualDelay)
        }

        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.fireAlarm(name: name, extensionID: extensionID)
            }
        }

        timer.resume()

        alarms[key] = Alarm(
            name: name,
            extensionID: extensionID,
            scheduledTime: scheduledTime,
            periodInMinutes: periodInMinutes,
            timer: timer,
        )

        Logger.debug(
            "Created alarm '\(name)' for extension \(extensionID), fires in \(actualDelay)s",
            category: Logger.extensions,
        )
    }

    /// Gets information about an alarm.
    ///
    /// - Parameters:
    ///   - name: The alarm name.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: Alarm info or nil if not found.
    private func get(name: String, extensionID: String) -> [String: Any]? {
        let key = "\(extensionID):\(name)"
        guard let alarm = alarms[key] else { return nil }
        return alarmToDict(alarm)
    }

    /// Gets all alarms for an extension.
    ///
    /// - Parameter extensionID: The calling extension's identifier.
    /// - Returns: Array of alarm info objects.
    private func getAll(extensionID: String) -> [[String: Any]] {
        alarms.values
            .filter { $0.extensionID == extensionID }
            .map { alarmToDict($0) }
    }

    /// Clears an alarm.
    ///
    /// - Parameters:
    ///   - name: The alarm name.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: `true` if the alarm was cleared.
    private func clear(name: String, extensionID: String) -> Bool {
        let key = "\(extensionID):\(name)"
        guard let alarm = alarms.removeValue(forKey: key) else {
            return false
        }
        alarm.timer.cancel()
        return true
    }

    /// Clears all alarms for an extension.
    ///
    /// - Parameter extensionID: The calling extension's identifier.
    /// - Returns: `true` (always succeeds).
    private func clearAll(extensionID: String) -> Bool {
        let keys = alarms.keys.filter { $0.hasPrefix("\(extensionID):") }
        for key in keys {
            if let alarm = alarms.removeValue(forKey: key) {
                alarm.timer.cancel()
            }
        }
        return true
    }

    // MARK: - Private Helpers

    /// Fires an alarm and handles cleanup for one-shot alarms.
    private func fireAlarm(name: String, extensionID: String) {
        let key = "\(extensionID):\(name)"

        guard let alarm = alarms[key] else { return }

        Logger.debug(
            "Firing alarm '\(name)' for extension \(extensionID)",
            category: Logger.extensions,
        )

        // Notify callbacks
        for callback in onAlarmCallbacks {
            callback(name, extensionID)
        }

        // Remove one-shot alarms after firing
        if alarm.periodInMinutes == nil {
            alarms.removeValue(forKey: key)
        }
    }

    /// Converts an alarm to a dictionary for JavaScript.
    private func alarmToDict(_ alarm: Alarm) -> [String: Any] {
        var dict: [String: Any] = [
            "name": alarm.name,
            "scheduledTime": alarm.scheduledTime.timeIntervalSince1970 * 1_000,
        ]
        if let period = alarm.periodInMinutes {
            dict["periodInMinutes"] = period
        }
        return dict
    }

    // MARK: - Event Registration

    /// Registers a callback for alarm events.
    ///
    /// - Parameter callback: Called with (alarmName, extensionID) when an alarm fires.
    func onAlarm(_ callback: @escaping (String, String) -> Void) {
        onAlarmCallbacks.append(callback)
    }

    /// Clears all alarms for an extension (called on uninstall).
    func clearAllForExtension(_ extensionID: String) {
        _ = clearAll(extensionID: extensionID)
    }
}
