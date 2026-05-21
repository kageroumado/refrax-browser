import Foundation
import Observation

/// Coordinates periodic background tasks for archive expiration and auto-archive rules.
///
/// This manager uses `NSBackgroundActivityScheduler` for energy-efficient hourly task
/// execution, plus app activation triggers for immediate execution after idle periods.
///
/// ## Overview
///
/// Registered tasks run:
/// - Hourly via system-optimized scheduler (with ±10 minute tolerance for batching)
/// - On app activation if 60+ minutes have elapsed since last run
/// - Immediately on startup
///
/// ```swift
/// let scheduler = ScheduledTasksManager(activationObserver: observer)
///
/// scheduler.registerTask { [weak archiveManager] in
///     await archiveManager?.clearExpiredTabs()
/// }
///
/// scheduler.start()
/// ```
///
/// ## Power Efficiency
///
/// `NSBackgroundActivityScheduler` allows the system to defer, batch, or skip tasks
/// based on battery state, thermal conditions, and CPU load. The 10-minute tolerance
/// enables meaningful power savings while remaining imperceptible to users.
///
/// ## Registered Tasks
///
/// - ``TabArchiveManager/clearExpiredTabs()`` — Removes archived tabs past expiration
/// - ``TabAutoArchiveManager/executeRules()`` — Applies user-defined auto-archive rules
@Observable
final class ScheduledTasksManager {
    // MARK: - State

    /// Timestamp of the last successful task run.
    ///
    /// Used to determine if tasks should run immediately on app activation.
    private(set) var lastTaskRun: Date?

    // MARK: - Configuration

    /// Minimum interval between task runs (60 minutes).
    private let minimumInterval: TimeInterval = 3_600

    /// Tolerance for scheduler flexibility (10 minutes).
    private let schedulerTolerance: TimeInterval = 600

    // MARK: - Dependencies

    @ObservationIgnored
    private let activationObserver: AppActivationObserver

    // MARK: - Private State

    @ObservationIgnored
    private var scheduler: NSBackgroundActivityScheduler?

    @ObservationIgnored
    private var registeredTasks: [@Sendable () async -> Void] = []

    @ObservationIgnored
    private var activationTask: Task<Void, Never>?

    @ObservationIgnored
    private var isRunning = false

    // MARK: - Initialization

    /// Creates a scheduled tasks manager.
    ///
    /// - Parameter activationObserver: Observer for app activation events.
    init(activationObserver: AppActivationObserver) {
        self.activationObserver = activationObserver
    }

    // MARK: - Task Registration

    /// Registers a task to run on the hourly schedule.
    ///
    /// Tasks are executed sequentially in registration order.
    /// Registration must happen before calling ``start()``.
    ///
    /// - Parameter task: An async closure to execute on schedule.
    func registerTask(_ task: @escaping @Sendable () async -> Void) {
        registeredTasks.append(task)
    }

    // MARK: - Lifecycle

    /// Starts the scheduled task system.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Run immediately on start
        Task {
            await runTasks()
        }

        // Start listening for app activations
        startActivationListener()

        // Use NSBackgroundActivityScheduler for energy-efficient hourly tasks
        scheduler = NSBackgroundActivityScheduler(
            identifier: "com.refrax.browser.scheduledTasks",
        )
        scheduler?.interval = minimumInterval
        scheduler?.tolerance = schedulerTolerance
        scheduler?.repeats = true
        scheduler?.qualityOfService = .background

        scheduler?.schedule { completionHandler in
            // Run tasks on main actor
            Task { @MainActor [weak self] in
                guard let self else {
                    completionHandler(.finished)
                    return
                }

                // Check if system recommends deferral
                if scheduler?.shouldDefer == true {
                    completionHandler(.deferred)
                    return
                }

                await runTasks()
                completionHandler(.finished)
            }
        }

        Logger.debug("Scheduled tasks manager started", category: Logger.tabs)
    }

    /// Stops the scheduled task system.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        activationTask?.cancel()
        activationTask = nil

        scheduler?.invalidate()
        scheduler = nil

        Logger.debug("Scheduled tasks manager stopped", category: Logger.tabs)
    }

    /// Manually triggers task execution.
    ///
    /// Used for "Run Now" button in settings UI.
    func runNow() async {
        await runTasks()
    }

    // MARK: - Private

    private func startActivationListener() {
        activationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in activationObserver.makeActivationsStream() {
                guard !Task.isCancelled else { break }

                // Check if enough time has passed since last run
                if let lastRun = lastTaskRun {
                    let elapsed = Date().timeIntervalSince(lastRun)
                    guard elapsed >= minimumInterval else { continue }
                }

                await runTasks()
            }
        }
    }

    private func runTasks() async {
        lastTaskRun = Date()

        for task in registeredTasks {
            await task()
        }

        Logger.debug("Scheduled tasks completed", category: Logger.tabs)
    }
}
