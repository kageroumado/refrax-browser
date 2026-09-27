import Foundation
import Security

/// An installed engine bundle (`<Name>.engine`), read without executing any of its code.
nonisolated struct EngineBundle: Hashable, Sendable {
    let url: URL
    let descriptor: EngineDescriptor
    let principalClassName: String

    /// Reads and validates a bundle's Info.plist. Returns nil for anything that isn't a usable engine.
    init?(url: URL) {
        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary,
              let identifier = bundle.bundleIdentifier,
              let principalClass = info["NSPrincipalClass"] as? String,
              let contract = (info[RFXEngineInfoKey.contractVersion.rawValue] as? String).flatMap(EngineContractVersion.init(string:))
        else {
            return nil
        }
        self.url = url
        principalClassName = principalClass
        descriptor = EngineDescriptor(
            id: EngineID(rawValue: identifier),
            displayName: info[RFXEngineInfoKey.displayName.rawValue] as? String ?? url.deletingPathExtension().lastPathComponent,
            // The release forge packaged (`152.0.7977.82-r1`), what the engine catalog names.
            version: info["RFXEngineBuild"] as? String ?? info["CFBundleShortVersionString"] as? String ?? "0",
            engineVersion: info[RFXEngineInfoKey.engineVersion.rawValue] as? String ?? "",
            vendor: info[RFXEngineInfoKey.vendor.rawValue] as? String ?? "",
            contractVersion: contract,
            capabilities: EngineCapabilities(names: info[RFXEngineInfoKey.capabilities.rawValue] as? [String] ?? []),
            isOutOfProcess: info[RFXEngineInfoKey.outOfProcess.rawValue] as? Bool ?? false,
        )
    }

    // MARK: Code Signature

    /// Verifies the bundle is intact and signed by the same team as Refrax.
    ///
    /// Library validation would reject a foreign-team bundle at load time anyway;
    /// checking first turns that into a clear error instead of a failed `dlopen`,
    /// and catches tampered or partially written installs before any code runs.
    func verifySignature() throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw EngineError.failedToLoad(descriptor.id, reason: "The bundle has no code signature.")
        }
        var requirement: SecRequirement?
        if let teamID = Self.ownTeamIdentifier {
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
            SecRequirementCreateWithString(text as CFString, [], &requirement)
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            throw EngineError.failedToLoad(descriptor.id, reason: "Code signature check failed: \(reason)")
        }
    }

    /// The Team ID that signed the running Refrax, or nil when unsigned (tests, local builds).
    private static let ownTeamIdentifier: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else {
            return nil
        }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()
}
