import CryptoKit
import Foundation

/// Downloads, verifies and installs one engine release from the catalog.
///
/// Every check runs before the engine lands where ``EngineRegistry`` looks: the zip comes from a
/// refrax-engines release over HTTPS, is exactly the declared size, hashes to the declared
/// sha256 and carries a valid `.sig`; the bundle inside is the engine and release the catalog
/// names, speaks a contract Refrax accepts, and is signed by Refrax's team. Only then does it
/// replace the installed bundle, or, while that engine runs, wait in `Engines/.pending/` for the
/// next launch: a loaded engine can't be unloaded, and its running host still reads its files.
nonisolated enum EngineInstaller {
    enum Outcome: Equatable, Sendable {
        case installed(URL)
        /// Installed at the next launch of Refrax.
        case pendingRelaunch
    }

    enum Stage: Equatable, Sendable {
        case downloading(fraction: Double)
        case verifying
        case installing
    }

    /// Where a verified engine waits while the installed one runs; hidden from the registry's scan.
    static let pendingDirectoryName = ".pending"

    /// Checks a candidate bundle's code signature; the registry's team check by default.
    typealias CodeCheck = @Sendable (EngineBundle) throws -> Void

    @concurrent
    static func install(
        _ release: EngineCatalog.Release,
        engine id: EngineID,
        into enginesDirectory: URL,
        replacingRunningEngine isRunning: Bool,
        session: URLSession = .shared,
        key: Curve25519.Signing.PublicKey? = nil,
        checkCode: CodeCheck = { try $0.verifySignature() },
        stage: @escaping @Sendable (Stage) -> Void = { _ in },
    ) async throws -> Outcome {
        guard EngineSignature.isAllowedDownloadURL(release.url) else {
            throw EngineDistributionError.urlNotAllowed(release.url)
        }
        let key = try key ?? EngineSignature.pinnedKey()
        let staging = try makeStaging()
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = staging.appending(path: release.url.lastPathComponent)
        try await download(release.url, to: archive, declaredSize: release.sizeBytes, session: session) {
            stage(.downloading(fraction: $0))
        }
        stage(.verifying)
        let signatureURL = EngineSignature.signatureURL(for: release.url)
        let (signature, response) = try await session.data(from: signatureURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw EngineDistributionError.http(signatureURL, http.statusCode)
        }
        try verify(archive, against: release, signatureFile: signature, key: key)

        stage(.installing)
        let bundle = try unpack(archive, in: staging, expecting: release, engine: id)
        try checkCode(bundle)
        return try place(bundle.url, engine: id, in: enginesDirectory, replacingRunningEngine: isRunning)
    }

    /// Size, hash and signature, in that order: the cheap checks refuse a wrong file before the
    /// signature is computed over hundreds of megabytes.
    static func verify(
        _ archive: URL, against release: EngineCatalog.Release, signatureFile: Data, key: Curve25519.Signing.PublicKey,
    ) throws {
        let size = try (FileManager.default.attributesOfItem(atPath: archive.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value ?? -1
        guard size == release.sizeBytes else {
            throw EngineDistributionError.sizeMismatch(expected: release.sizeBytes, actual: size)
        }
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256.lowercased() else {
            throw EngineDistributionError.hashMismatch
        }
        try EngineSignature.verify(bytes, signatureFile: signatureFile, subject: archive.lastPathComponent, key: key)
    }

    /// Extracts the zip and returns its one `.engine`, once it is the engine and release the
    /// catalog describes, in a contract this Refrax speaks.
    static func unpack(
        _ archive: URL, in staging: URL, expecting release: EngineCatalog.Release, engine id: EngineID,
    ) throws -> EngineBundle {
        let extracted = staging.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        // ditto keeps the bundle's signatures and extended attributes, as ditto made the zip.
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path(percentEncoded: false), extracted.path(percentEncoded: false)]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw EngineDistributionError.archiveInvalid("ditto exited with \(ditto.terminationStatus)")
        }
        let contents = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        guard contents.count == 1, let url = contents.first, url.pathExtension == "engine" else {
            throw EngineDistributionError.archiveInvalid("expected one .engine, found \(contents.map(\.lastPathComponent))")
        }
        clearQuarantine(under: url)
        guard let bundle = EngineBundle(url: url) else {
            throw EngineDistributionError.bundleMismatch("\(url.lastPathComponent) isn't an engine bundle")
        }
        guard bundle.descriptor.id == id else {
            throw EngineDistributionError.bundleMismatch("it is \(bundle.descriptor.id), not \(id)")
        }
        guard bundle.descriptor.version == release.version else {
            throw EngineDistributionError.bundleMismatch("it is release \(bundle.descriptor.version), not \(release.version)")
        }
        guard EngineContractVersion.current.accepts(bundle.descriptor.contractVersion) else {
            throw EngineError.incompatibleContract(id, engine: bundle.descriptor.contractVersion)
        }
        return bundle
    }

    /// Moves a verified bundle to where the registry reads it, or to `.pending` while the
    /// installed engine runs.
    static func place(
        _ bundle: URL, engine id: EngineID, in enginesDirectory: URL, replacingRunningEngine isRunning: Bool,
    ) throws -> Outcome {
        if isRunning {
            let pending = enginesDirectory
                .appending(path: pendingDirectoryName, directoryHint: .isDirectory)
                .appending(path: id.rawValue, directoryHint: .isDirectory)
            try replaceContents(of: pending, with: bundle)
            return .pendingRelaunch
        }
        let destination = enginesDirectory.appending(path: id.rawValue, directoryHint: .isDirectory)
        try replaceContents(of: destination, with: bundle)
        return .installed(destination.appending(path: bundle.lastPathComponent))
    }

    /// Moves every engine waiting in `.pending` into place. Called before any engine loads, so
    /// nothing it replaces is running.
    static func applyPending(in enginesDirectory: URL, skipping running: Set<EngineID>) {
        let fileManager = FileManager.default
        let pendingRoot = enginesDirectory.appending(path: pendingDirectoryName, directoryHint: .isDirectory)
        let directories = (try? fileManager.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil)) ?? []
        for directory in directories where !running.contains(EngineID(rawValue: directory.lastPathComponent)) {
            let bundles = ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "engine" }
            guard bundles.count == 1, let bundle = bundles.first else { continue }
            let destination = enginesDirectory.appending(path: directory.lastPathComponent, directoryHint: .isDirectory)
            do {
                try replaceContents(of: destination, with: bundle)
                try fileManager.removeItem(at: directory)
                Logger.info("Installed pending engine \(bundle.lastPathComponent) for \(directory.lastPathComponent)", category: Logger.engines)
            } catch {
                Logger.warning("Could not install pending engine \(bundle.path): \(error.localizedDescription)", category: Logger.engines)
            }
        }
    }

    /// Makes `bundle` the only engine in `directory`; the previous one goes to the Trash.
    private static func replaceContents(of directory: URL, with bundle: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for existing in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where existing.pathExtension == "engine" {
            try fileManager.trashItem(at: existing, resultingItemURL: nil)
        }
        try fileManager.moveItem(at: bundle, to: directory.appending(path: bundle.lastPathComponent))
    }

    private static func makeStaging() throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appending(path: "refrax-engine-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// The zip Refrax downloaded is quarantined; its bundle is verified above and loads into
    /// Refrax, so the flag only stands between Gatekeeper and a host Refrax already trusts.
    private static func clearQuarantine(under root: URL) {
        let attribute = "com.apple.quarantine"
        removexattr(root.path(percentEncoded: false), attribute, XATTR_NOFOLLOW)
        guard let walk = FileManager.default.enumerator(atPath: root.path(percentEncoded: false)) else { return }
        for case let relative as String in walk {
            removexattr(root.appending(path: relative).path(percentEncoded: false), attribute, XATTR_NOFOLLOW)
        }
    }

    /// A download task with progress against the declared size; never a byte-by-byte async loop,
    /// which costs an await per byte. URLSession deletes its temporary file when the completion
    /// handler returns, so it is moved inside the handler.
    private static func download(
        _ url: URL, to destination: URL, declaredSize: Int64, session: URLSession,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        let transfer = Transfer()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let task = session.downloadTask(with: url) { temporary, response, error in
                    transfer.finish()
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                        continuation.resume(throwing: EngineDistributionError.http(url, http.statusCode))
                        return
                    }
                    do {
                        guard let temporary else { throw EngineDistributionError.archiveInvalid("the download produced no file") }
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                nonisolated(unsafe) var reported = -1.0
                let observation = task.progress.observe(\.completedUnitCount) { taskProgress, _ in
                    let fraction = min(1, Double(taskProgress.completedUnitCount) / Double(max(declaredSize, 1)))
                    guard fraction - reported >= 0.01 || fraction >= 1 else { return }
                    reported = fraction
                    progress(fraction)
                }
                transfer.start(task, observing: observation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }

    /// One download's task and progress observation. A cancel that arrives before the task
    /// exists cancels it the moment it starts.
    private final class Transfer: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var observation: NSKeyValueObservation?
        private var isCancelled = false

        func start(_ task: URLSessionDownloadTask, observing observation: NSKeyValueObservation) {
            let cancelled = lock.withLock {
                self.task = task
                self.observation = observation
                return isCancelled
            }
            task.resume()
            if cancelled {
                task.cancel()
            }
        }

        func cancel() {
            let task = lock.withLock {
                isCancelled = true
                return self.task
            }
            task?.cancel()
        }

        func finish() {
            let observation = lock.withLock {
                defer { self.observation = nil }
                return self.observation
            }
            observation?.invalidate()
        }
    }
}
