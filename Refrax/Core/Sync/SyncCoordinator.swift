import CloudKit
import SwiftData

/// Core orchestrator for CloudKit sync via CKSyncEngine.
///
/// A plain `actor` (not `@ModelActor`) that bridges SwiftData history tracking with
/// CKSyncEngine's push/pull lifecycle. Uses two separate ModelContainers:
/// - `mainContainer`: The app's primary data store (read for push, write for pull)
/// - `syncContainer`: Sync metadata store (SyncRecord, SyncState)
///
/// ## Push Flow
/// 1. On `willSendChanges`, scan SwiftData history since last token
/// 2. Register pending changes with the engine's state
/// 3. On `nextRecordZoneChangeBatch`, materialize CKRecords from models
///
/// ## Pull Flow
/// 1. On `fetchedRecordZoneChanges`, apply incoming records via `Syncable.applyRecord`
/// 2. Store system fields in `SyncRecord` for future updates
/// 3. Handle deletions by removing local models
actor SyncCoordinator {

    private let mainContainer: ModelContainer
    private let syncContainer: ModelContainer

    /// Set during `init` after all other stored properties are initialized.
    /// Using `nonisolated(unsafe)` because Swift requires all properties to be set before
    /// referencing `self` as the delegate, but CKSyncEngine needs `self` as its delegate.
    private nonisolated(unsafe) var engine: CKSyncEngine!

    /// Pending changes indexed by CKRecord.ID, populated during `preparePendingChanges`
    /// and consumed during `buildChangeBatch`.
    private var pendingRecordMaterializations: [CKRecord.ID: PendingChange] = [:]

    init(mainContainer: ModelContainer, syncContainer: ModelContainer) {
        self.mainContainer = mainContainer
        self.syncContainer = syncContainer

        let syncContext = ModelContext(syncContainer)
        let syncState = SyncState.fetchOrCreate(in: syncContext)

        var stateSerialization: CKSyncEngine.State.Serialization?
        if let data = syncState.engineState {
            stateSerialization = try? JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self, from: data
            )
        }

        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: "iCloud.website.refrax.browser").privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        self.engine = CKSyncEngine(configuration)
    }
}

// MARK: - CKSyncEngineDelegate

extension SyncCoordinator: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            await persistEngineState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .willSendChanges:
            await preparePendingChanges()

        case .fetchedRecordZoneChanges(let changes):
            await handleFetchedChanges(changes)

        case .sentRecordZoneChanges(let sent):
            await handleSentChanges(sent)

        case .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges, .didFetchChanges,
             .didSendChanges, .fetchedDatabaseChanges, .sentDatabaseChanges:
            break

        @unknown default:
            break
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await buildChangeBatch(for: context, syncEngine: syncEngine)
    }
}

// MARK: - Push Flow

private extension SyncCoordinator {

    /// Scans SwiftData history for changes since the last sync token and registers
    /// them as pending with the CKSyncEngine.
    func preparePendingChanges() {
        let mainContext = ModelContext(mainContainer)
        let syncContext = ModelContext(syncContainer)
        let syncState = SyncState.fetchOrCreate(in: syncContext)

        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let tokenData = syncState.historyToken,
           let token = try? JSONDecoder().decode(DefaultHistoryToken.self, from: tokenData)
        {
            descriptor.predicate = #Predicate { $0.token > token }
        }

        guard let transactions = try? mainContext.fetchHistory(descriptor) else {
            Logger.error("Failed to fetch SwiftData history", category: Logger.sync)
            return
        }

        var pendingSaves: [CKRecord.ID] = []
        var pendingDeletes: [CKRecord.ID] = []

        for transaction in transactions {
            for change in transaction.changes {
                switch change {
                case .insert(let insert):
                    processSaveChange(
                        persistentID: insert.changedPersistentIdentifier,
                        timestamp: transaction.timestamp,
                        mainContext: mainContext,
                        pendingSaves: &pendingSaves
                    )

                case .update(let update):
                    processSaveChange(
                        persistentID: update.changedPersistentIdentifier,
                        timestamp: transaction.timestamp,
                        mainContext: mainContext,
                        pendingSaves: &pendingSaves
                    )

                case .delete(let delete):
                    processDeleteChange(
                        delete: delete,
                        pendingDeletes: &pendingDeletes
                    )

                @unknown default:
                    break
                }
            }
        }

        if !pendingSaves.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pendingSaves.map { .saveRecord($0) })
        }
        if !pendingDeletes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pendingDeletes.map { .deleteRecord($0) })
        }

        if let lastTransaction = transactions.last {
            do {
                let tokenData = try JSONEncoder().encode(lastTransaction.token)
                syncState.historyToken = tokenData
                try syncContext.save()
            } catch {
                Logger.error("Failed to save sync history token: \(error)", category: Logger.sync)
            }
        }
    }

    /// Processes an insert or update from SwiftData history.
    func processSaveChange(
        persistentID: PersistentIdentifier,
        timestamp: Date,
        mainContext: ModelContext,
        pendingSaves: inout [CKRecord.ID]
    ) {
        let entityName = persistentID.entityName
        guard SyncableTypeRegistry.isSyncable(entityName: entityName) else { return }

        let model = mainContext.model(for: persistentID)
        guard let syncable = model as? (any Syncable) else { return }

        let uuid = extractUUID(from: syncable)
        guard let uuid else { return }

        let recordID = RecordMapper.recordID(for: uuid)
        pendingSaves.append(recordID)
        pendingRecordMaterializations[recordID] = PendingChange(
            uuid: uuid, entityName: entityName, persistentID: persistentID,
            timestamp: timestamp
        )
    }

    /// Processes a deletion from SwiftData history.
    ///
    /// Extracts the UUID from the tombstone (requires `@Attribute(.preserveValueOnDeletion)`
    /// on the model's `id` property) and enqueues a CloudKit record deletion.
    func processDeleteChange(
        delete: any HistoryDelete,
        pendingDeletes: inout [CKRecord.ID]
    ) {
        let entityName = delete.changedPersistentIdentifier.entityName
        guard SyncableTypeRegistry.isSyncable(entityName: entityName) else { return }

        guard let uuid = extractUUIDFromTombstone(delete, entityName: entityName) else {
            Logger.error("Could not extract UUID from tombstone for \(entityName), ensure id has .preserveValueOnDeletion", category: Logger.sync)
            return
        }

        let recordID = RecordMapper.recordID(for: uuid)
        pendingDeletes.append(recordID)
    }

    /// Materializes CKRecords for the engine's next send batch.
    func buildChangeBatch(
        for context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        guard !pendingChanges.isEmpty else { return nil }

        let mainContext = ModelContext(mainContainer)
        let syncContext = ModelContext(syncContainer)

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in pendingChanges {
            switch change {
            case .saveRecord(let recordID):
                guard let pending = pendingRecordMaterializations[recordID] else {
                    continue
                }

                let systemFieldsData = fetchSystemFields(
                    modelType: pending.entityName, modelID: pending.uuid.uuidString,
                    in: syncContext
                )

                guard let record = try? RecordMapper.record(
                    for: pending.uuid, recordType: pending.entityName,
                    systemFieldsData: systemFieldsData
                ) else {
                    Logger.error("Failed to create CKRecord for \(pending.entityName)/\(pending.uuid.uuidString)", category: Logger.sync)
                    continue
                }

                let model = mainContext.model(for: pending.persistentID)
                guard let syncable = model as? (any Syncable) else {
                    Logger.fault("Model not found for \(pending.entityName)/\(pending.uuid.uuidString), skipping", category: Logger.sync)
                    continue
                }

                syncable.encodeToRecord(record)
                record["modifiedAt"] = pending.timestamp as NSDate
                recordsToSave.append(record)

            case .deleteRecord(let recordID):
                recordIDsToDelete.append(recordID)

            @unknown default:
                break
            }
        }

        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete,
            atomicByZone: true
        )
    }
}

// MARK: - Pull Flow

private extension SyncCoordinator {

    /// Applies fetched record changes from CloudKit to the local store.
    func handleFetchedChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        let mainContext = ModelContext(mainContainer)
        let syncContext = ModelContext(syncContainer)

        for modification in changes.modifications {
            let record = modification.record
            do {
                try applyIncomingRecord(record, into: mainContext)
                updateSyncRecord(for: record, in: syncContext)
            } catch {
                Logger.error("Failed to apply record \(record.recordType)/\(record.recordID.recordName): \(error.localizedDescription)", category: Logger.sync)
            }
        }

        for deletion in changes.deletions {
            guard let uuid = RecordMapper.uuid(from: deletion.recordID) else { continue }
            deleteLocalModel(uuid: uuid, recordType: deletion.recordType, in: mainContext)
            deleteSyncRecord(modelType: deletion.recordType, modelID: uuid.uuidString, in: syncContext)
        }

        do { try mainContext.save() } catch {
            Logger.error("Failed to save main context after pull: \(error)", category: Logger.sync)
        }
        do { try syncContext.save() } catch {
            Logger.error("Failed to save sync context after pull: \(error)", category: Logger.sync)
        }
    }

    /// Routes an incoming CKRecord to the correct Syncable.applyRecord implementation.
    @discardableResult
    func applyIncomingRecord(_ record: CKRecord, into context: ModelContext) throws -> any PersistentModel {
        switch record.recordType {
        case "Space": return try Space.applyRecord(record, into: context)
        case "Tab": return try Tab.applyRecord(record, into: context)
        case "TabPage": return try TabPage.applyRecord(record, into: context)
        case "TabGroup": return try TabGroup.applyRecord(record, into: context)
        case "Bookmark": return try Bookmark.applyRecord(record, into: context)
        case "BookmarkFolder": return try BookmarkFolder.applyRecord(record, into: context)
        case "HistoryEntry": return try HistoryEntry.applyRecord(record, into: context)
        case "BrowsingContext": return try BrowsingContext.applyRecord(record, into: context)
        case "SiteSettings": return try SiteSettings.applyRecord(record, into: context)
        case "BrowserSettings": return try BrowserSettings.applyRecord(record, into: context)
        case "PrivacyProtectionSettings": return try PrivacyProtectionSettings.applyRecord(record, into: context)
        case "CustomSearchEngine": return try CustomSearchEngine.applyRecord(record, into: context)
        case "CustomRedirect": return try CustomRedirect.applyRecord(record, into: context)
        case "AppRedirectRule": return try AppRedirectRule.applyRecord(record, into: context)
        case "ExternalURLRule": return try ExternalURLRule.applyRecord(record, into: context)
        case "ExternalURLSettings": return try ExternalURLSettings.applyRecord(record, into: context)
        case "SourceAppRule": return try SourceAppRule.applyRecord(record, into: context)
        case "RoutingRule": return try RoutingRule.applyRecord(record, into: context)
        case "ArchiveRule": return try ArchiveRule.applyRecord(record, into: context)
        case "UserScript": return try UserScript.applyRecord(record, into: context)
        case "UserStyle": return try UserStyle.applyRecord(record, into: context)
        case "FocusModeMapping": return try FocusModeMapping.applyRecord(record, into: context)
        case "AppShortcut": return try AppShortcut.applyRecord(record, into: context)
        case "SavedFilter": return try SavedFilter.applyRecord(record, into: context)
        case "DomainTimeLimit": return try DomainTimeLimit.applyRecord(record, into: context)
        default: throw SyncError.unknownRecordType(record.recordType)
        }
    }

    /// Deletes a local model by UUID and record type.
    func deleteLocalModel(uuid: UUID, recordType: String, in context: ModelContext) {
        switch recordType {
        case "Space": deleteModel(Space.self, uuid: uuid, in: context)
        case "Tab": deleteModel(Tab.self, uuid: uuid, in: context)
        case "TabPage": deleteModel(TabPage.self, uuid: uuid, in: context)
        case "TabGroup": deleteModel(TabGroup.self, uuid: uuid, in: context)
        case "Bookmark": deleteModel(Bookmark.self, uuid: uuid, in: context)
        case "BookmarkFolder": deleteModel(BookmarkFolder.self, uuid: uuid, in: context)
        case "HistoryEntry": deleteModel(HistoryEntry.self, uuid: uuid, in: context)
        case "BrowsingContext": deleteModel(BrowsingContext.self, uuid: uuid, in: context)
        case "SiteSettings": deleteModel(SiteSettings.self, uuid: uuid, in: context)
        case "BrowserSettings": deleteModel(BrowserSettings.self, uuid: uuid, in: context)
        case "PrivacyProtectionSettings": deleteModel(PrivacyProtectionSettings.self, uuid: uuid, in: context)
        case "CustomSearchEngine": deleteModel(CustomSearchEngine.self, uuid: uuid, in: context)
        case "CustomRedirect": deleteModel(CustomRedirect.self, uuid: uuid, in: context)
        case "AppRedirectRule": deleteModel(AppRedirectRule.self, uuid: uuid, in: context)
        case "ExternalURLRule": deleteModel(ExternalURLRule.self, uuid: uuid, in: context)
        case "ExternalURLSettings": deleteModel(ExternalURLSettings.self, uuid: uuid, in: context)
        case "SourceAppRule": deleteModel(SourceAppRule.self, uuid: uuid, in: context)
        case "RoutingRule": deleteModel(RoutingRule.self, uuid: uuid, in: context)
        case "ArchiveRule": deleteModel(ArchiveRule.self, uuid: uuid, in: context)
        case "UserScript": deleteModel(UserScript.self, uuid: uuid, in: context)
        case "UserStyle": deleteModel(UserStyle.self, uuid: uuid, in: context)
        case "FocusModeMapping": deleteModel(FocusModeMapping.self, uuid: uuid, in: context)
        case "AppShortcut": deleteModel(AppShortcut.self, uuid: uuid, in: context)
        case "SavedFilter": deleteModel(SavedFilter.self, uuid: uuid, in: context)
        case "DomainTimeLimit": deleteModel(DomainTimeLimit.self, uuid: uuid, in: context)
        default:
            Logger.fault("Unknown record type for deletion: \(recordType)", category: Logger.sync)
        }
    }

    /// Fetches a model by UUID using a type-specific predicate and deletes it.
    ///
    /// All Refrax `@Model` types use `var id: UUID` as their primary key. This helper
    /// fetches by that field using the concrete type's `#Predicate`.
    func deleteModel<T: PersistentModel & Syncable>(_ type: T.Type, uuid: UUID, in context: ModelContext) {
        // Use the same fetch-by-UUID pattern as the Syncable extensions.
        // Since we can't write a generic #Predicate on `id`, we use the
        // ModelContext.model(for:) approach won't help for deletion.
        // Instead, we fetch using the concrete type that the switch dispatches.
        let model = fetchModelByUUID(type, uuid: uuid, in: context)
        if let model {
            context.delete(model)
        }
    }

    /// Fetches a Syncable model by its UUID using Mirror reflection.
    ///
    /// This is a fallback for when we can't write a type-erased `#Predicate` on `id`.
    /// The performance is acceptable since it's only called for individual deletions
    /// arriving from CloudKit, not in bulk operations.
    func fetchModelByUUID<T: PersistentModel>(_ type: T.Type, uuid: UUID, in context: ModelContext) -> T? {
        let descriptor = FetchDescriptor<T>()
        guard let models = try? context.fetch(descriptor) else { return nil }
        return models.first { model in
            let mirror = Mirror(reflecting: model)
            for child in mirror.children where child.label == "id" || child.label == "_id" {
                if let modelUUID = child.value as? UUID {
                    return modelUUID == uuid
                }
            }
            return false
        }
    }
}

// MARK: - Conflict Handling

private extension SyncCoordinator {

    /// Processes sent record results, handling conflicts via ConflictResolver.
    func handleSentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        let syncContext = ModelContext(syncContainer)

        for record in sent.savedRecords {
            updateSyncRecord(for: record, in: syncContext)
            pendingRecordMaterializations.removeValue(forKey: record.recordID)
        }

        for recordID in sent.deletedRecordIDs {
            if let uuid = RecordMapper.uuid(from: recordID) {
                deleteSyncRecord(modelType: nil, modelID: uuid.uuidString, in: syncContext)
            }
        }

        for failedSave in sent.failedRecordSaves {
            if failedSave.error.code == .serverRecordChanged {
                handleConflict(failedSave: failedSave)
            } else {
                Logger.error("Record save failed for \(failedSave.record.recordType)/\(failedSave.record.recordID.recordName): \(failedSave.error.localizedDescription)", category: Logger.sync)
            }
        }

        for (recordID, error) in sent.failedRecordDeletes {
            Logger.error("Record delete failed for \(recordID.recordName): \(error.localizedDescription)", category: Logger.sync)
        }

        do {
            try syncContext.save()
        } catch {
            Logger.error("Failed to save sync records after sent changes: \(error)", category: Logger.sync)
        }
    }

    /// Resolves a conflict between client and server records using LWW strategy.
    func handleConflict(failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let clientRecord = failedSave.record
        guard let serverRecord = failedSave.error.serverRecord else {
            Logger.error("serverRecordChanged but no server record available", category: Logger.sync)
            return
        }

        let winner = ConflictResolver.resolve(client: clientRecord, server: serverRecord)

        if winner === clientRecord {
            for key in clientRecord.allKeys() {
                serverRecord[key] = clientRecord[key]
            }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])

            if let pending = pendingRecordMaterializations[clientRecord.recordID] {
                pendingRecordMaterializations[serverRecord.recordID] = pending
            }
        } else {
            let mainContext = ModelContext(mainContainer)
            do {
                try applyIncomingRecord(serverRecord, into: mainContext)
                try mainContext.save()
            } catch {
                Logger.error("Failed to apply server-wins record: \(error)", category: Logger.sync)
            }

            let syncContext = ModelContext(syncContainer)
            updateSyncRecord(for: serverRecord, in: syncContext)
            do {
                try syncContext.save()
            } catch {
                Logger.error("Failed to save sync record after conflict resolution: \(error)", category: Logger.sync)
            }
        }
    }
}

// MARK: - Engine State Persistence

private extension SyncCoordinator {

    func persistEngineState(_ serialization: CKSyncEngine.State.Serialization) {
        let syncContext = ModelContext(syncContainer)
        let syncState = SyncState.fetchOrCreate(in: syncContext)
        do {
            syncState.engineState = try JSONEncoder().encode(serialization)
            try syncContext.save()
        } catch {
            Logger.error("Failed to persist sync engine state: \(error)", category: Logger.sync)
        }
    }
}

// MARK: - Account Change

private extension SyncCoordinator {

    /// Handles iCloud account changes (sign in, sign out, switch).
    ///
    /// Full account change handling is implemented in Task 11.
    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        Logger.info("iCloud account change: \(change.changeType)", category: Logger.sync)

        let syncContext = ModelContext(syncContainer)
        let syncState = SyncState.fetchOrCreate(in: syncContext)

        switch change.changeType {
        case .signIn(let currentUser):
            syncState.accountID = currentUser.recordName

        case .signOut:
            syncState.accountID = nil
            syncState.historyToken = nil
            syncState.engineState = nil

        case .switchAccounts(_, let currentUser):
            syncState.accountID = currentUser.recordName
            syncState.historyToken = nil
            syncState.engineState = nil

        @unknown default:
            break
        }

        do {
            try syncContext.save()
        } catch {
            Logger.error("Failed to save sync state after account change: \(error)", category: Logger.sync)
        }
    }
}

// MARK: - Sync Record Management

private extension SyncCoordinator {

    func updateSyncRecord(for record: CKRecord, in context: ModelContext) {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else { return }
        let modelType = record.recordType
        let modelID = uuid.uuidString
        let systemFields = RecordMapper.encodeSystemFields(of: record)

        var descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate { $0.modelType == modelType && $0.modelID == modelID }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.ckSystemFields = systemFields
            existing.lastSyncedAt = .now
        } else {
            context.insert(SyncRecord(
                modelType: modelType, modelID: modelID, ckSystemFields: systemFields
            ))
        }
    }

    func deleteSyncRecord(modelType: String?, modelID: String, in context: ModelContext) {
        let descriptor: FetchDescriptor<SyncRecord>
        if let modelType {
            descriptor = FetchDescriptor<SyncRecord>(
                predicate: #Predicate { $0.modelType == modelType && $0.modelID == modelID }
            )
        } else {
            descriptor = FetchDescriptor<SyncRecord>(
                predicate: #Predicate { $0.modelID == modelID }
            )
        }

        if let records = try? context.fetch(descriptor) {
            for record in records {
                context.delete(record)
            }
        }
    }

    func fetchSystemFields(modelType: String, modelID: String, in context: ModelContext) -> Data? {
        var descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate { $0.modelType == modelType && $0.modelID == modelID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.ckSystemFields
    }
}

// MARK: - Helpers

private extension SyncCoordinator {

    /// Extracts the UUID from a Syncable model (all Refrax models use `var id: UUID`).
    nonisolated func extractUUID(from model: any Syncable) -> UUID? {
        let mirror = Mirror(reflecting: model)
        for child in mirror.children {
            if child.label == "id" || child.label == "_id" {
                return child.value as? UUID
            }
        }
        return nil
    }

    /// Extracts the UUID from a deletion tombstone using entity-name dispatch.
    ///
    /// The `HistoryTombstone` subscript requires a concrete model key path, so we
    /// dispatch by entity name to cast to `DefaultHistoryDelete<T>` and access
    /// `tombstone[\T.id]`.
    nonisolated func extractUUIDFromTombstone(
        _ delete: any HistoryDelete,
        entityName: String
    ) -> UUID? {
        func id<T: PersistentModel>(
            _ type: T.Type,
            _ keyPath: PartialKeyPath<T>
        ) -> UUID? {
            (delete as? DefaultHistoryDelete<T>)?.tombstone[keyPath] as? UUID
        }

        return switch entityName {
        case "Tab": id(Tab.self, \Tab.id)
        case "TabPage": id(TabPage.self, \TabPage.id)
        case "Space": id(Space.self, \Space.id)
        case "TabGroup": id(TabGroup.self, \TabGroup.id)
        case "Bookmark": id(Bookmark.self, \Bookmark.id)
        case "BookmarkFolder": id(BookmarkFolder.self, \BookmarkFolder.id)
        case "HistoryEntry": id(HistoryEntry.self, \HistoryEntry.id)
        case "BrowsingContext": id(BrowsingContext.self, \BrowsingContext.id)
        case "BrowserSettings": id(BrowserSettings.self, \BrowserSettings.id)
        case "SiteSettings": id(SiteSettings.self, \SiteSettings.id)
        case "PrivacyProtectionSettings": id(PrivacyProtectionSettings.self, \PrivacyProtectionSettings.id)
        case "CustomSearchEngine": id(CustomSearchEngine.self, \CustomSearchEngine.id)
        case "CustomRedirect": id(CustomRedirect.self, \CustomRedirect.id)
        case "AppRedirectRule": id(AppRedirectRule.self, \AppRedirectRule.id)
        case "ExternalURLRule": id(ExternalURLRule.self, \ExternalURLRule.id)
        case "ExternalURLSettings": id(ExternalURLSettings.self, \ExternalURLSettings.id)
        case "SourceAppRule": id(SourceAppRule.self, \SourceAppRule.id)
        case "RoutingRule": id(RoutingRule.self, \RoutingRule.id)
        case "ArchiveRule": id(ArchiveRule.self, \ArchiveRule.id)
        case "UserScript": id(UserScript.self, \UserScript.id)
        case "UserStyle": id(UserStyle.self, \UserStyle.id)
        case "FocusModeMapping": id(FocusModeMapping.self, \FocusModeMapping.id)
        case "AppShortcut": id(AppShortcut.self, \AppShortcut.id)
        case "SavedFilter": id(SavedFilter.self, \SavedFilter.id)
        case "DomainTimeLimit": id(DomainTimeLimit.self, \DomainTimeLimit.id)
        default: nil
        }
    }

    struct PendingChange: Sendable {
        let uuid: UUID
        let entityName: String
        let persistentID: PersistentIdentifier
        let timestamp: Date
    }
}
