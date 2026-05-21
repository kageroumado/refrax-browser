import AppKit
import EventKit
import Foundation

/// Manages data detection in text using NaturalLanguage framework.
///
/// Detects entities like phone numbers, addresses, dates, and URLs in text,
/// and provides context menu actions for them.
///
/// ## Supported Entity Types
///
/// - **Phone numbers**: Call, copy, send message
/// - **Addresses**: Open in Maps, copy
/// - **Dates**: Create calendar event, copy
/// - **URLs**: Open, copy
/// - **Email addresses**: Compose mail, copy
///
/// ## Usage
///
/// ```swift
/// let manager = DataDetectionManager()
/// let items = manager.detectAndCreateMenuItems(for: "Call me at 555-1234")
/// // Returns menu items for detected phone number
/// ```
final class DataDetectionManager {
    // MARK: - Entity Detection

    /// Detected entity with its type, value, and range.
    struct DetectedEntity: Hashable {
        let type: EntityType
        let value: String
        let range: Range<String.Index>

        enum EntityType: Hashable {
            case phoneNumber
            case address
            case date
            case url
            case email
            case flightNumber(airline: String?)
            case trackingNumber(carrier: Carrier?)
            case onionLink
            case measurement(value: Double, unit: String, converted: String)
            case terminalCommand
        }

        /// Shipping carrier for tracking numbers.
        enum Carrier: String, Hashable {
            case ups = "UPS"
            case fedex = "FedEx"
            case usps = "USPS"
            case dhl = "DHL"
            case amazon = "Amazon"

            var trackingURL: String {
                switch self {
                case .ups: "https://www.ups.com/track?tracknum="
                case .fedex: "https://www.fedex.com/apps/fedextrack/?tracknumbers="
                case .usps: "https://tools.usps.com/go/TrackConfirmAction?tLabels="
                case .dhl: "https://www.dhl.com/us-en/home/tracking/tracking-parcel.html?submit=1&tracking-id="
                case .amazon: "https://www.amazon.com/gp/your-account/order-details?orderID="
                }
            }
        }
    }

    // MARK: - Detection Patterns

    /// Flight number pattern: 2-letter airline code + 1-4 digit flight number (e.g., AA1234, UA 456)
    private static let flightPattern = try? NSRegularExpression(
        pattern: #"(?i)\b([A-Z]{2})\s*(\d{1,4})\b"#,
        options: [],
    )

    /// Common airline codes for validation
    private static let airlineCodes: Set<String> = [
        "AA", "UA", "DL", "WN", "B6", "AS", "NK", "F9", "G4", "HA", // US carriers
        "BA", "LH", "AF", "KL", "IB", "AZ", "SK", "SN", "OS", "LX", // European
        "EK", "QR", "TK", "EY", "SQ", "CX", "QF", "NZ", "AC", "AM", // International
    ]

    /// Tracking number patterns by carrier
    private static let trackingPatterns: [(pattern: NSRegularExpression, carrier: DetectedEntity.Carrier)] = {
        var patterns: [(NSRegularExpression, DetectedEntity.Carrier)] = []

        // UPS: 1Z followed by 16 alphanumeric
        if let ups = try? NSRegularExpression(pattern: #"\b1Z[A-Z0-9]{16}\b"#, options: .caseInsensitive) {
            patterns.append((ups, .ups))
        }

        // FedEx: 12-15 digits, or 20-22 digits
        if let fedex = try? NSRegularExpression(pattern: #"\b\d{12,15}\b|\b\d{20,22}\b"#, options: []) {
            patterns.append((fedex, .fedex))
        }

        // USPS: 20-22 digits, or starts with 94 and is 20+ digits
        if let usps = try? NSRegularExpression(pattern: #"\b94\d{18,20}\b|\b\d{20,22}\b"#, options: []) {
            patterns.append((usps, .usps))
        }

        // DHL: 10-11 digits
        if let dhl = try? NSRegularExpression(pattern: #"\b\d{10,11}\b"#, options: []) {
            patterns.append((dhl, .dhl))
        }

        // Amazon: starts with TBA followed by 12 digits
        if let amazon = try? NSRegularExpression(pattern: #"\bTBA\d{12}\b"#, options: .caseInsensitive) {
            patterns.append((amazon, .amazon))
        }

        return patterns
    }()

    /// Onion link pattern: URLs ending in .onion
    private static let onionPattern = try? NSRegularExpression(
        pattern: #"(?i)\b(?:https?://)?[a-z2-7]{16,56}\.onion(?:/[^\s]*)?"#,
        options: [],
    )

    /// Measurement patterns for common units
    private static let measurementPattern = try? NSRegularExpression(
        pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(miles?|mi|kilometers?|km|feet|ft|meters?|m|inches?|in|cm|centimeters?|lbs?|pounds?|kg|kilograms?|oz|ounces?|grams?|g|°?[FC]|fahrenheit|celsius)\b"#,
        options: [],
    )

    /// Common shell command prefixes and commands for detection.
    private static let shellCommandPrefixes: [String] = [
        "sudo", "brew", "npm", "npx", "yarn", "pnpm", "git", "docker", "kubectl",
        "cd", "ls", "cat", "echo", "curl", "wget", "pip", "python", "python3",
        "ruby", "gem", "cargo", "rustc", "go", "make", "cmake", "gcc", "clang",
        "chmod", "chown", "mkdir", "rm", "cp", "mv", "touch", "grep", "sed", "awk",
        "ssh", "scp", "rsync", "tar", "zip", "unzip", "xcodebuild", "swift", "swiftc",
        "pod", "carthage", "fastlane", "xcode-select", "xcrun", "codesign",
    ]

    /// Pattern to detect shell prompt prefixes ($, %, #, >).
    private static let shellPromptPattern = try? NSRegularExpression(
        pattern: #"^\s*[$%#>]\s+"#,
        options: [],
    )

    /// Detects entities in the given text.
    ///
    /// Uses NSDataDetector for phone numbers, addresses, dates, and links,
    /// plus custom patterns for flight numbers and tracking numbers.
    ///
    /// - Parameter text: The text to analyze.
    /// - Returns: Array of detected entities.
    func detectEntities(in text: String) -> [DetectedEntity] {
        var entities: [DetectedEntity] = []

        // Use NSDataDetector for reliable detection of common entities
        let types: NSTextCheckingResult.CheckingType = [
            .phoneNumber,
            .address,
            .date,
            .link,
        ]

        if let detector = try? NSDataDetector(types: types.rawValue) {
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result,
                      let swiftRange = Range(result.range, in: text)
                else { return }

                let value = String(text[swiftRange])

                switch result.resultType {
                case .phoneNumber:
                    entities.append(DetectedEntity(type: .phoneNumber, value: value, range: swiftRange))

                case .address:
                    entities.append(DetectedEntity(type: .address, value: value, range: swiftRange))

                case .date:
                    entities.append(DetectedEntity(type: .date, value: value, range: swiftRange))

                case .link:
                    if let url = result.url {
                        if url.scheme == "mailto" {
                            let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                            entities.append(DetectedEntity(type: .email, value: email, range: swiftRange))
                        } else {
                            entities.append(DetectedEntity(type: .url, value: url.absoluteString, range: swiftRange))
                        }
                    }

                default:
                    break
                }
            }
        }

        // Detect flight numbers
        entities.append(contentsOf: detectFlightNumbers(in: text))

        // Detect tracking numbers
        entities.append(contentsOf: detectTrackingNumbers(in: text))

        // Detect onion links
        entities.append(contentsOf: detectOnionLinks(in: text))

        // Detect measurements
        entities.append(contentsOf: detectMeasurements(in: text))

        // Detect terminal commands
        entities.append(contentsOf: detectTerminalCommands(in: text))

        return entities
    }

    /// Detects flight numbers in text.
    private func detectFlightNumbers(in text: String) -> [DetectedEntity] {
        guard let pattern = Self.flightPattern else { return [] }

        var entities: [DetectedEntity] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)

        pattern.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result,
                  let swiftRange = Range(result.range, in: text)
            else { return }

            let value = String(text[swiftRange])
            let airlineCode = value.prefix(2).uppercased()

            // Only accept known airline codes to reduce false positives
            if Self.airlineCodes.contains(airlineCode) {
                entities.append(DetectedEntity(
                    type: .flightNumber(airline: airlineCode),
                    value: value.replacingOccurrences(of: " ", with: "").uppercased(),
                    range: swiftRange,
                ))
            }
        }

        return entities
    }

    /// Detects tracking numbers in text.
    private func detectTrackingNumbers(in text: String) -> [DetectedEntity] {
        var entities: [DetectedEntity] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)

        for (pattern, carrier) in Self.trackingPatterns {
            pattern.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result,
                      let swiftRange = Range(result.range, in: text)
                else { return }

                let value = String(text[swiftRange])

                // Avoid duplicates
                if !entities.contains(where: { $0.range.overlaps(swiftRange) }) {
                    entities.append(DetectedEntity(
                        type: .trackingNumber(carrier: carrier),
                        value: value,
                        range: swiftRange,
                    ))
                }
            }
        }

        return entities
    }

    /// Detects .onion links in text.
    private func detectOnionLinks(in text: String) -> [DetectedEntity] {
        guard let pattern = Self.onionPattern else { return [] }

        var entities: [DetectedEntity] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)

        pattern.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result,
                  let swiftRange = Range(result.range, in: text)
            else { return }

            let value = String(text[swiftRange])
            entities.append(DetectedEntity(type: .onionLink, value: value, range: swiftRange))
        }

        return entities
    }

    /// Detects measurements in text and provides conversions.
    private func detectMeasurements(in text: String) -> [DetectedEntity] {
        guard let pattern = Self.measurementPattern else { return [] }

        var entities: [DetectedEntity] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)

        pattern.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result,
                  let swiftRange = Range(result.range, in: text),
                  result.numberOfRanges >= 3,
                  let valueRange = Range(result.range(at: 1), in: text),
                  let unitRange = Range(result.range(at: 2), in: text),
                  let numericValue = Double(String(text[valueRange]))
            else { return }

            let value = String(text[swiftRange])
            let unitString = String(text[unitRange]).lowercased()

            if let converted = Self.convertMeasurement(value: numericValue, unit: unitString) {
                entities.append(DetectedEntity(
                    type: .measurement(value: numericValue, unit: unitString, converted: converted),
                    value: value,
                    range: swiftRange,
                ))
            }
        }

        return entities
    }

    /// Detects terminal commands in text.
    ///
    /// Looks for text that starts with shell prompt prefixes ($, %, #, >) or
    /// common command names. Strips the prompt prefix from the command value.
    private func detectTerminalCommands(in text: String) -> [DetectedEntity] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the entire text looks like a command
        guard isLikelyTerminalCommand(trimmed) else { return [] }

        // Extract the command (strip prompt prefix if present)
        let command = extractCommand(from: trimmed)
        guard !command.isEmpty else { return [] }

        return [DetectedEntity(
            type: .terminalCommand,
            value: command,
            range: text.startIndex ..< text.endIndex,
        )]
    }

    /// Checks if text looks like a terminal command.
    private func isLikelyTerminalCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't detect multi-line blocks as commands (use only for single lines)
        if trimmed.contains("\n") { return false }

        // Check for shell prompt prefix
        if let pattern = Self.shellPromptPattern {
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            if pattern.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Check if starts with known command
        let lowercased = trimmed.lowercased()
        for prefix in Self.shellCommandPrefixes {
            if lowercased.hasPrefix(prefix),
               trimmed.count == prefix.count || trimmed[trimmed.index(trimmed.startIndex, offsetBy: prefix.count)].isWhitespace {
                return true
            }
        }

        // Check for common command patterns: word followed by flags (--flag, -f)
        let flagPattern = try? NSRegularExpression(
            pattern: #"^[a-z_][a-z0-9_-]*\s+(-[\w-]+|\S+).*$"#,
            options: .caseInsensitive,
        )
        if let pattern = flagPattern {
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            if pattern.firstMatch(in: trimmed, options: [], range: range) != nil,
               trimmed.contains("-") {
                return true
            }
        }

        return false
    }

    /// Extracts the command from text, stripping shell prompt prefix.
    private func extractCommand(from text: String) -> String {
        var result = text

        // Strip prompt prefix
        if let pattern = Self.shellPromptPattern {
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            if let match = pattern.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range, in: text) {
                result = String(text[matchRange.upperBound...])
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Converts a measurement to an alternative unit system.
    private static func convertMeasurement(value: Double, unit: String) -> String? {
        switch unit {
        // Distance: Imperial to Metric
        case "mile", "miles", "mi":
            let km = Measurement(value: value, unit: UnitLength.miles).converted(to: .kilometers)
            return String(format: "%.1f km", km.value)
        case "feet", "ft":
            let m = Measurement(value: value, unit: UnitLength.feet).converted(to: .meters)
            return String(format: "%.2f m", m.value)
        case "inch", "inches", "in":
            let cm = Measurement(value: value, unit: UnitLength.inches).converted(to: .centimeters)
            return String(format: "%.1f cm", cm.value)
        // Distance: Metric to Imperial
        case "kilometer", "kilometers", "km":
            let mi = Measurement(value: value, unit: UnitLength.kilometers).converted(to: .miles)
            return String(format: "%.1f mi", mi.value)
        case "meter", "meters", "m":
            let ft = Measurement(value: value, unit: UnitLength.meters).converted(to: .feet)
            return String(format: "%.1f ft", ft.value)
        case "centimeter", "centimeters", "cm":
            let inches = Measurement(value: value, unit: UnitLength.centimeters).converted(to: .inches)
            return String(format: "%.1f in", inches.value)
        // Weight: Imperial to Metric
        case "lb", "lbs", "pound", "pounds":
            let kg = Measurement(value: value, unit: UnitMass.pounds).converted(to: .kilograms)
            return String(format: "%.2f kg", kg.value)
        case "oz", "ounce", "ounces":
            let g = Measurement(value: value, unit: UnitMass.ounces).converted(to: .grams)
            return String(format: "%.1f g", g.value)
        // Weight: Metric to Imperial
        case "kg", "kilogram", "kilograms":
            let lb = Measurement(value: value, unit: UnitMass.kilograms).converted(to: .pounds)
            return String(format: "%.1f lb", lb.value)
        case "g", "gram", "grams":
            let oz = Measurement(value: value, unit: UnitMass.grams).converted(to: .ounces)
            return String(format: "%.2f oz", oz.value)
        // Temperature
        case "°f", "f", "fahrenheit":
            let c = Measurement(value: value, unit: UnitTemperature.fahrenheit).converted(to: .celsius)
            return String(format: "%.1f°C", c.value)
        case "°c", "c", "celsius":
            let f = Measurement(value: value, unit: UnitTemperature.celsius).converted(to: .fahrenheit)
            return String(format: "%.1f°F", f.value)
        default:
            return nil
        }
    }

    // MARK: - Menu Item Creation

    /// Creates context menu items for detected entities in the text.
    ///
    /// - Parameter text: The selected or context text to analyze.
    /// - Returns: Array of menu items for detected entities.
    func createMenuItems(for text: String) -> [NSMenuItem] {
        let entities = detectEntities(in: text)
        var items: [NSMenuItem] = []

        for entity in entities {
            items.append(contentsOf: createMenuItems(for: entity))
        }

        return items
    }

    /// Creates menu items for a specific detected entity.
    private func createMenuItems(for entity: DetectedEntity) -> [NSMenuItem] {
        switch entity.type {
        case .phoneNumber:
            createPhoneMenuItems(for: entity.value)
        case .email:
            createEmailMenuItems(for: entity.value)
        case .address:
            createAddressMenuItems(for: entity.value)
        case .date:
            createDateMenuItems(for: entity.value)
        case .url:
            createURLMenuItems(for: entity.value)
        case let .flightNumber(airline):
            createFlightMenuItems(for: entity.value, airline: airline)
        case let .trackingNumber(carrier):
            createTrackingMenuItems(for: entity.value, carrier: carrier)
        case .onionLink:
            createOnionLinkMenuItems(for: entity.value)
        case let .measurement(_, _, converted):
            createMeasurementMenuItems(for: entity.value, converted: converted)
        case .terminalCommand:
            createTerminalCommandMenuItems(for: entity.value)
        }
    }

    // MARK: - Entity-Specific Menu Items

    private func createPhoneMenuItems(for phoneNumber: String) -> [NSMenuItem] {
        let cleanNumber = phoneNumber.filter { $0.isNumber || $0 == "+" }
        return [
            menuItem("Call \"\(phoneNumber)\"", action: .call(cleanNumber)),
            menuItem("FaceTime Audio \"\(phoneNumber)\"", action: .faceTimeAudio(cleanNumber)),
            menuItem("Send Message to \"\(phoneNumber)\"", action: .sendMessage(cleanNumber)),
            menuItem("Copy Phone Number", action: .copy(phoneNumber)),
        ]
    }

    private func createEmailMenuItems(for email: String) -> [NSMenuItem] {
        [
            menuItem("Send Email to \"\(email)\"", action: .composeEmail(email)),
            menuItem("Copy Email Address", action: .copy(email)),
        ]
    }

    private func createAddressMenuItems(for address: String) -> [NSMenuItem] {
        [
            menuItem("Show in Maps", action: .openInMaps(address)),
            menuItem("Get Directions", action: .getDirections(address)),
            menuItem("Copy Address", action: .copy(address)),
        ]
    }

    private func createDateMenuItems(for dateString: String) -> [NSMenuItem] {
        [
            menuItem("Create Calendar Event", action: .createCalendarEvent(dateString)),
            menuItem("Show in Calendar", action: .showInCalendar(dateString)),
            menuItem("Copy Date", action: .copy(dateString)),
        ]
    }

    private func createURLMenuItems(for urlString: String) -> [NSMenuItem] {
        [menuItem("Copy Link", action: .copy(urlString))]
    }

    private func createFlightMenuItems(for flightNumber: String, airline _: String?) -> [NSMenuItem] {
        [
            menuItem("Track Flight \"\(flightNumber)\"", action: .trackFlight(flightNumber)),
            menuItem("Copy Flight Number", action: .copy(flightNumber)),
        ]
    }

    private func createTrackingMenuItems(for trackingNumber: String, carrier: DetectedEntity.Carrier?) -> [NSMenuItem] {
        let carrierName = carrier?.rawValue ?? "Package"
        return [
            menuItem("Track \(carrierName) Package", action: .trackPackage(trackingNumber, carrier)),
            menuItem("Copy Tracking Number", action: .copy(trackingNumber)),
        ]
    }

    private func createOnionLinkMenuItems(for onionURL: String) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Check if Tor Browser is installed
        if Self.isTorBrowserInstalled() {
            items.append(menuItem("Open in Tor Browser", action: .openInTor(onionURL)))
        } else {
            items.append(menuItem("Copy Onion Link (Tor Browser not found)", action: .copy(onionURL)))
        }

        items.append(menuItem("Copy Onion Link", action: .copy(onionURL)))
        return items
    }

    private func createMeasurementMenuItems(for original: String, converted: String) -> [NSMenuItem] {
        [
            menuItem("\(original) = \(converted)", action: .copy(converted)),
            menuItem("Copy Converted (\(converted))", action: .copy(converted)),
        ]
    }

    private func createTerminalCommandMenuItems(for command: String) -> [NSMenuItem] {
        let truncated = command.count > 40 ? String(command.prefix(37)) + "..." : command
        return [
            menuItem("Run in Terminal: \"\(truncated)\"", action: .executeInTerminal(command)),
            menuItem("Copy Command", action: .copy(command)),
        ]
    }

    /// Checks if Tor Browser is installed on the system.
    private static func isTorBrowserInstalled() -> Bool {
        let torBrowserPaths = [
            "/Applications/Tor Browser.app",
            NSHomeDirectory() + "/Applications/Tor Browser.app",
        ]
        return torBrowserPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func menuItem(_ title: String, action: DataAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performDataAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        return item
    }

    // MARK: - Action Execution

    /// Enum defining data detection actions.
    private enum DataAction {
        case call(String)
        case faceTimeAudio(String)
        case sendMessage(String)
        case composeEmail(String)
        case openInMaps(String)
        case getDirections(String)
        case createCalendarEvent(String)
        case showInCalendar(String)
        case trackFlight(String)
        case trackPackage(String, DetectedEntity.Carrier?)
        case openInTor(String)
        case executeInTerminal(String)
        case copy(String)
    }

    @objc
    private func performDataAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? DataAction else { return }

        switch action {
        case let .call(number):
            if let url = URL(string: "tel://\(number)") {
                NSWorkspace.shared.open(url)
            }

        case let .faceTimeAudio(number):
            if let url = URL(string: "facetime-audio://\(number)") {
                NSWorkspace.shared.open(url)
            }

        case let .sendMessage(number):
            if let url = URL(string: "sms://\(number)") {
                NSWorkspace.shared.open(url)
            }

        case let .composeEmail(email):
            if let url = URL(string: "mailto:\(email)") {
                NSWorkspace.shared.open(url)
            }

        case let .openInMaps(address):
            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
            if let url = URL(string: "maps://?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }

        case let .getDirections(address):
            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
            if let url = URL(string: "maps://?daddr=\(encoded)") {
                NSWorkspace.shared.open(url)
            }

        case let .createCalendarEvent(dateString):
            Task {
                await createCalendarEvent(withDate: dateString)
            }

        case let .showInCalendar(dateString):
            showDateInCalendar(dateString)

        case let .trackFlight(flightNumber):
            // Use FlightAware for tracking
            let encoded = flightNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? flightNumber
            if let url = URL(string: "https://flightaware.com/live/flight/\(encoded)") {
                NSWorkspace.shared.open(url)
            }

        case let .trackPackage(trackingNumber, carrier):
            let trackingURL: String
            if let carrier {
                trackingURL = carrier.trackingURL + trackingNumber
            } else {
                // Generic tracking via Google
                let encoded = trackingNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trackingNumber
                trackingURL = "https://www.google.com/search?q=track+\(encoded)"
            }
            if let url = URL(string: trackingURL) {
                NSWorkspace.shared.open(url)
            }

        case let .openInTor(onionURL):
            // Ensure the URL has a scheme
            let fullURL = onionURL.hasPrefix("http") ? onionURL : "http://\(onionURL)"

            guard let onionTarget = URL(string: fullURL) else {
                Logger.warning(
                    "Skipping Tor launch for malformed onion URL: \(fullURL)",
                    category: Logger.network,
                )
                return
            }

            // Find Tor Browser and open the URL
            let torBrowserPaths = [
                "/Applications/Tor Browser.app",
                NSHomeDirectory() + "/Applications/Tor Browser.app",
            ]

            for path in torBrowserPaths {
                if FileManager.default.fileExists(atPath: path),
                   let torBrowserURL = URL(string: "file://\(path)") {
                    NSWorkspace.shared.open(
                        [onionTarget],
                        withApplicationAt: torBrowserURL,
                        configuration: NSWorkspace.OpenConfiguration(),
                    )
                    return
                }
            }

        case let .executeInTerminal(command):
            executeCommandInTerminal(command)

        case let .copy(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }

    /// Executes a command in Terminal.app after user confirmation.
    private func executeCommandInTerminal(_ command: String) {
        // Security confirmation
        let alert = NSAlert()
        alert.messageText = "Run Command in Terminal?"
        alert.informativeText = "This will execute in Terminal:\n\n\(command)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Escape the command for AppleScript
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Execute via osascript
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Opens the Calendar app showing the specified date.
    private func showDateInCalendar(_ dateString: String) {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(dateString.startIndex ..< dateString.endIndex, in: dateString)

        var detectedDate: Date?
        detector?.enumerateMatches(in: dateString, options: [], range: range) { result, _, stop in
            if let date = result?.date {
                detectedDate = date
                stop.pointee = true
            }
        }

        guard let date = detectedDate else {
            Logger.warning("Could not parse date from: \(dateString)", category: Logger.tabs)
            return
        }

        // Format date for Calendar URL
        let dateParam = date.formatted(.iso8601.year().month().day())

        if let url = URL(string: "x-apple-calevent://?date=\(dateParam)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Calendar Event Creation

    private func createCalendarEvent(withDate dateString: String) async {
        // Try to parse the date
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(dateString.startIndex ..< dateString.endIndex, in: dateString)

        var detectedDate: Date?
        detector?.enumerateMatches(in: dateString, options: [], range: range) { result, _, stop in
            if let date = result?.date {
                detectedDate = date
                stop.pointee = true
            }
        }

        guard let date = detectedDate else {
            Logger.warning("Could not parse date from: \(dateString)", category: Logger.tabs)
            return
        }

        let eventStore = EKEventStore()
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else {
                Logger.warning("Calendar access not granted", category: Logger.tabs)
                return
            }

            let event = EKEvent(eventStore: eventStore)
            event.title = "Event"
            event.startDate = date
            event.endDate = date.addingTimeInterval(3_600) // 1 hour duration
            event.calendar = eventStore.defaultCalendarForNewEvents

            try eventStore.save(event, span: .thisEvent)
            Logger.info("Calendar event created for \(date)", category: Logger.tabs)
        } catch {
            Logger.error("Calendar error: \(error)", category: Logger.tabs)
        }
    }
}
