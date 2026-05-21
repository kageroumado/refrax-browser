import SwiftData

// Schema versioning for SwiftData migrations.
//
// Each version captures the model schema at a point in time. When models change,
// create a new version and add migration steps in `RefraxMigrationPlan`.
//
// ## Adding a New Version
//
// 1. Create a new enum case (e.g., `SchemaV2`) conforming to `VersionedSchema`
// 2. Copy model type aliases to the new version (only changed models need updating)
// 3. Add a migration stage in `RefraxMigrationPlan.stages`
// 4. Update the schemas array in `RefraxMigrationPlan`

// MARK: - Schema V1

/// Initial schema version with unified Space model.
///
/// Features:
/// - Space as full @Model with relationships to Tab and TabGroup
/// - Tab.space relationship (inverse of Space.tabs)
/// - TabGroup.space relationship (inverse of Space.groups)
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Tab.self,
            TabPage.self,
            Space.self,
            TabGroup.self,
            HistoryEntry.self,
            TabSnapshot.self,
            TabSnapshotItem.self,
            BrowsingContext.self,
            SavedFilter.self,
            Bookmark.self,
            BookmarkFolder.self,
            BrowserSettings.self,
            CachedFavicon.self,
            SiteSettings.self,
            PrivacyProtectionSettings.self,
            CustomRedirect.self,
            AppRedirectRule.self,
            Download.self,
            AppShortcut.self,
            ArchiveRule.self,
            DomainTimeEntry.self,
            DomainTimeLimit.self,
            UserStyle.self,
            UserScript.self,
            UserScriptStorage.self,
            CustomSearchEngine.self,
            SyncState.self,
            SyncRecord.self,
            SourceAppRule.self,
            RoutingRule.self,
            FocusModeMapping.self,
            ExternalURLSettings.self,
            ExternalURLRule.self,
        ]
    }
}

// MARK: - Migration Plan

/// Migration plan for Refrax's SwiftData schema.
///
/// This defines the order of schema versions and migration stages.
/// SwiftData uses this to automatically migrate data between versions.
enum RefraxMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    /// Migration stages between versions.
    ///
    /// Each stage defines how to migrate from one version to the next.
    /// For lightweight migrations (adding/removing columns), use `.lightweight`.
    /// For complex migrations, use `.custom` with migration code.
    static var stages: [MigrationStage] {
        // No migrations yet - V1 is the initial version
        []
    }
}
