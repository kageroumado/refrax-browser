import CloudKit
import SwiftData

extension CustomRedirect: Syncable {
    nonisolated static var ckRecordType: String { "CustomRedirect" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["sourcePattern"] = sourcePattern as NSString
        record["destinationTemplate"] = destinationTemplate as NSString
        record["isEnabled"] = isEnabled as NSNumber
        record["order"] = order as NSNumber

        // Excluded: cachedRegex, cachedPatternSource (@Transient)

        // Relationships
        // CustomRedirect → PrivacyProtectionSettings: CASCADE (deleted with parent)
        // Parent is a singleton — no reference needed; resolved via singleton accessor.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> CustomRedirect {
        guard let name = record["name"] as? String, !name.isEmpty else {
            throw SyncError.missingRequiredField("name")
        }
        guard let sourcePattern = record["sourcePattern"] as? String else {
            throw SyncError.missingRequiredField("sourcePattern")
        }

        // CustomRedirect has no explicit UUID id. Use name + sourcePattern as
        // composite key for upsert, since each redirect rule is uniquely identified
        // by its name within the parent settings.
        var descriptor = FetchDescriptor<CustomRedirect>(
            predicate: #Predicate { $0.name == name && $0.sourcePattern == sourcePattern }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let redirect: CustomRedirect
        if let existing {
            redirect = existing
        } else {
            guard let destinationTemplate = record["destinationTemplate"] as? String else {
                throw SyncError.missingRequiredField("destinationTemplate")
            }
            redirect = CustomRedirect(
                name: name,
                sourcePattern: sourcePattern,
                destinationTemplate: destinationTemplate
            )
            context.insert(redirect)
        }

        // Update all properties from record
        redirect.name = name
        redirect.sourcePattern = sourcePattern
        redirect.destinationTemplate = record["destinationTemplate"] as? String
            ?? redirect.destinationTemplate
        redirect.isEnabled = (record["isEnabled"] as? Bool) ?? true
        redirect.order = (record["order"] as? Int) ?? 0

        // Re-attach to parent singleton if not already attached
        if redirect.privacySettings == nil {
            let settingsDescriptor = FetchDescriptor<BrowserSettings>()
            if let browserSettings = try? context.fetch(settingsDescriptor).first {
                redirect.privacySettings = browserSettings.privacyProtection
            }
        }

        return redirect
    }
}
