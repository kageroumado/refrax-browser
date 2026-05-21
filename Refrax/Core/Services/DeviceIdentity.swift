import CryptoKit
import Foundation
import IOKit

/// Generates a stable, non-reversible device identifier for telemetry.
///
/// Uses SHA-256 of the IOKit platform UUID with an app-specific salt.
/// The raw hardware UUID never leaves the device.
nonisolated enum DeviceIdentifier: Sendable {
    /// The hashed device identifier (64-char hex string).
    ///
    /// Computed once per process lifetime. Deterministic across reinstalls.
    /// Format: `SHA256("refrax-device-v1:" + IOPlatformUUID)`.
    static let value: String = {
        let uuid = platformUUID()
        let input = "refrax-device-v1:\(uuid)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    private static func platformUUID() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }

        guard service != IO_OBJECT_NULL,
              let uuidRef = IORegistryEntryCreateCFProperty(
                  service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
              )
        else {
            preconditionFailure("Failed to read IOPlatformUUID — IOKit unavailable")
        }

        return uuidRef.takeRetainedValue() as! String
    }
}
