import Foundation

/// Writes structured log entries to rotating files on disk.
///
/// Logs are stored in `Directories.appStorage/"Logs"` with daily rotation,
/// 7-day retention, and a 10 MB maximum per file. Writes are buffered and
/// flushed periodically to amortize I/O cost.
///
/// ## File Naming
///
/// - `refrax-2026-02-26.log` (first file of the day)
/// - `refrax-2026-02-26-1.log` (after 10 MB exceeded)
///
/// ## Log Format
///
/// ```
/// [2026-02-26 14:30:45.123] [ERROR] [navigation] Failed to load URL
/// ```
actor PersistentLogWriter {
    static let shared = PersistentLogWriter()

    private let logsDirectory: URL
    private let maxFileSize = 10_485_760 // 10 MB
    private let maxRetentionDays = 7
    private let flushThreshold = 100
    private let flushInterval: TimeInterval = 1.0

    private var currentFileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentDate: String
    private var currentFileIndex = 0
    private var currentFileSize = 0
    private var buffer: [String] = []
    private var lastFlushTime: Date = .distantPast
    private var flushTask: Task<Void, Never>?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {
        self.logsDirectory = Directories.appStorage.appendingPathComponent("Logs", isDirectory: true)
        self.currentDate = PersistentLogWriter.currentDayString()

        let fm = FileManager.default
        if !fm.fileExists(atPath: logsDirectory.path) {
            try? fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
    }

    /// Writes a log entry, buffering it for efficient I/O.
    func write(_ entry: LogEntry) {
        let line = formatEntry(entry)
        buffer.append(line)

        if buffer.count >= flushThreshold {
            flushBuffer()
        } else {
            scheduleFlushIfNeeded()
        }
    }

    /// Rotates to a new log file if the date has changed or the file size limit is exceeded.
    func rotateIfNeeded() {
        let today = PersistentLogWriter.currentDayString()
        if today != currentDate {
            closeCurrentFile()
            currentDate = today
            currentFileIndex = 0
        } else if currentFileSize >= maxFileSize {
            closeCurrentFile()
            currentFileIndex += 1
        }
    }

    /// Removes log files older than the retention period.
    func pruneOldLogs() {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -maxRetentionDays, to: Date(),
        ) ?? Date()

        for url in logFileURLs() {
            guard let date = extractDate(from: url.lastPathComponent) else { continue }
            if date < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Returns URLs of all log files, sorted by name (chronological).
    func allLogFileURLs() -> [URL] {
        logFileURLs().sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Collects recent log data up to the specified byte limit, most recent first.
    ///
    /// - Parameter maxBytes: Maximum bytes to collect (default 1 MB).
    /// - Returns: Combined log data from the most recent files.
    func collectRecentLogs(maxBytes: Int = 1_048_576) -> Data {
        flushBuffer()

        let files = allLogFileURLs().reversed()
        var collected = Data()

        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            if collected.count + data.count > maxBytes {
                let remaining = maxBytes - collected.count
                if remaining > 0 {
                    collected.append(data.suffix(remaining))
                }
                break
            }
            collected.append(data)
        }

        return collected
    }

    // MARK: - Private

    private func formatEntry(_ entry: LogEntry) -> String {
        let timestamp = dateFormatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        return "[\(timestamp)] [\(level)] [\(entry.category)] \(entry.message)\n"
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }

        rotateIfNeeded()
        let handle = ensureFileHandle()
        let combined = buffer.joined()
        buffer.removeAll(keepingCapacity: true)

        if let data = combined.data(using: .utf8) {
            handle.write(data)
            currentFileSize += data.count
        }

        lastFlushTime = Date()
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self = self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.performScheduledFlush()
        }
    }

    private func performScheduledFlush() {
        flushTask = nil
        flushBuffer()
    }

    private func ensureFileHandle() -> FileHandle {
        if let handle = currentFileHandle {
            return handle
        }

        let fm = FileManager.default
        let url = logFileURL(date: currentDate, index: currentFileIndex)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
            currentFileSize = 0
        } else {
            currentFileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }

        let handle = FileHandle(forWritingAtPath: url.path)!
        handle.seekToEndOfFile()
        currentFileHandle = handle
        currentFileURL = url
        return handle
    }

    private func closeCurrentFile() {
        currentFileHandle?.closeFile()
        currentFileHandle = nil
        currentFileURL = nil
    }

    private func logFileURL(date: String, index: Int) -> URL {
        let filename = index == 0
            ? "refrax-\(date).log"
            : "refrax-\(date)-\(index).log"
        return logsDirectory.appendingPathComponent(filename)
    }

    private func logFileURLs() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: nil,
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "log" }
    }

    private func extractDate(from filename: String) -> Date? {
        // Filenames: "refrax-YYYY-MM-DD.log" or "refrax-YYYY-MM-DD-N.log"
        guard filename.hasPrefix("refrax-") else { return nil }
        let stripped = filename
            .replacingOccurrences(of: "refrax-", with: "")
            .replacingOccurrences(of: ".log", with: "")
        let dateString = String(stripped.prefix(10))
        return dayFormatter.date(from: dateString)
    }

    private static func currentDayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
