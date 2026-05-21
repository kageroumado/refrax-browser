import Dispatch
import Foundation
import Observation

/// Monitors system memory pressure and power state for adaptive resource management.
///
/// `MemoryPressureMonitor` observes macOS memory pressure events and power state changes,
/// providing a unified view of system resource constraints. Use this to adapt caching
/// and session management strategies based on current system load.
///
/// ## Overview
///
/// The monitor tracks three key signals:
/// - **Memory pressure**: Normal → Warning → Critical levels from the kernel
/// - **Low power mode**: User-enabled battery conservation mode
/// - **Thermal state**: System temperature affecting performance
///
/// ```swift
/// let monitor = MemoryPressureMonitor.shared
/// monitor.start()
///
/// // React to pressure changes
/// if monitor.shouldConserveResources {
///     reduceActiveSessions()
/// }
/// ```
///
/// ## Pressure Response Philosophy
///
/// The monitor implements a "purge and wait" strategy rather than aggressive eviction:
/// - On warning: Evict a few low-value sessions, then wait
/// - On critical: More aggressive eviction, but still measured
/// - After eviction: Wait before evicting more to see if pressure normalizes
///
/// This prevents cascading evictions during temporary pressure spikes (e.g., Xcode builds).
@Observable
final class MemoryPressureMonitor {
    // MARK: - Singleton
    
    /// Shared monitor instance.
    static let shared = MemoryPressureMonitor()
    
    // MARK: - Pressure State
    
    /// Current memory pressure level from the system.
    private(set) var pressureLevel: PressureLevel = .normal
    
    /// Whether low power mode is enabled by the user.
    private(set) var isLowPowerModeEnabled: Bool = false
    
    /// Current thermal state of the system.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    /// Timestamp of the last pressure event (for cooldown tracking).
    private(set) var lastPressureEventTime: Date?
    
    /// Timestamp of the last eviction we triggered.
    private(set) var lastEvictionTime: Date?
    
    // MARK: - Computed Properties
    
    /// Whether the system is under any resource constraint.
    var isConstrained: Bool {
        pressureLevel != .normal || isLowPowerModeEnabled || thermalState >= .serious
    }
    
    /// Whether we should actively conserve resources (reduce active sessions).
    var shouldConserveResources: Bool {
        pressureLevel == .critical ||
            (pressureLevel == .warning && isLowPowerModeEnabled) ||
            thermalState == .critical
    }
    
    /// Whether we're in a cooldown period after recent eviction.
    ///
    /// During cooldown, we wait to see if pressure normalizes before evicting more.
    var isInEvictionCooldown: Bool {
        guard let lastEviction = lastEvictionTime else { return false }
        let cooldownDuration = cooldownInterval(for: pressureLevel)
        return Date().timeIntervalSince(lastEviction) < cooldownDuration
    }
    
    /// Suggested number of sessions to evict based on current pressure.
    ///
    /// Returns 0 if in cooldown or pressure is normal.
    var suggestedEvictionCount: Int {
        guard !isInEvictionCooldown else { return 0 }

        switch pressureLevel {
        case .normal:
            return 0
        case .warning:
            // Conservative: evict 1-2 at a time
            return isLowPowerModeEnabled ? 2 : 1
        case .critical:
            // More aggressive but still measured
            return 3
        }
    }

    /// Minimum time since last access for a tab to be evictable at current pressure level.
    ///
    /// Returns `nil` if pressure is normal (no age-based eviction).
    /// - Warning: 12 hours - only evict truly stale tabs
    /// - Critical: 6 hours - more aggressive but still protects recently used tabs
    var minimumEvictableAge: TimeInterval? {
        switch pressureLevel {
        case .normal:
            nil
        case .warning:
            12 * 60 * 60 // 12 hours
        case .critical:
            6 * 60 * 60 // 6 hours
        }
    }

    /// Minimum number of pages to have before any pressure-based eviction occurs.
    ///
    /// When page count is below this threshold, memory pressure eviction is skipped
    /// entirely, as evicting from a small pool has minimal memory benefit.
    static let minimumPagesForEviction: Int = 10
    
    // MARK: - Private State
    
    @ObservationIgnored
    private var pressureSource: (any DispatchSourceMemoryPressure)?
    
    @ObservationIgnored
    private var powerStateObserver: (any NSObjectProtocol)?
    
    @ObservationIgnored
    private var thermalStateObserver: (any NSObjectProtocol)?
    
    @ObservationIgnored
    private var isRunning = false
    
    // MARK: - Types
    
    /// Memory pressure levels matching system notifications.
    enum PressureLevel: Int, Comparable, Sendable {
        case normal = 0
        case warning = 1
        case critical = 2
        
        static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Read initial states
        self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        self.thermalState = ProcessInfo.processInfo.thermalState
    }
    
    // MARK: - Lifecycle
    
    /// Starts monitoring system resource state.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        setupMemoryPressureMonitor()
        setupPowerStateObserver()
        setupThermalStateObserver()
        
        Logger.debug("Memory pressure monitor started", category: Logger.tabs)
    }
    
    /// Stops monitoring and releases resources.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        pressureSource?.cancel()
        pressureSource = nil
        
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
            powerStateObserver = nil
        }
        
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }
        
        Logger.debug("Memory pressure monitor stopped", category: Logger.tabs)
    }
    
    /// Records that an eviction was triggered, starting the cooldown period.
    func recordEviction() {
        lastEvictionTime = Date()
    }
    
    /// Resets pressure state to normal (for testing or recovery).
    func resetPressureState() {
        pressureLevel = .normal
        lastPressureEventTime = nil
        lastEvictionTime = nil
    }
    
    // MARK: - Private Setup
    
    private func setupMemoryPressureMonitor() {
        // Create dispatch source for memory pressure events
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main,
        )
        
        source.setEventHandler { [weak self] in
            guard let self else { return }
            
            let event = source.data
            let newLevel: PressureLevel = if event.contains(.critical) {
                .critical
            } else if event.contains(.warning) {
                .warning
            } else {
                .normal
            }
            
            handlePressureChange(to: newLevel)
        }
        
        source.setCancelHandler { [weak self] in
            self?.pressureSource = nil
        }
        
        source.resume()
        pressureSource = source
    }
    
    private func setupPowerStateObserver() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                Logger.debug(
                    "Low power mode: \(self.isLowPowerModeEnabled)",
                )
            }
        }
    }
    
    private func setupThermalStateObserver() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.thermalState = ProcessInfo.processInfo.thermalState
                Logger.debug(
                    "Thermal state changed: \(self?.thermalState, default: "")",
                )
            }
        }
    }
    
    private func handlePressureChange(to newLevel: PressureLevel) {
        let oldLevel = pressureLevel
        pressureLevel = newLevel
        lastPressureEventTime = Date()
        
        // Log the change
        if newLevel != oldLevel {
            Logger.debug(
                "Memory pressure changed: \(oldLevel) → \(newLevel)",
                category: Logger.tabs,
            )
        }
        
        // If pressure decreased, reset eviction cooldown
        if newLevel < oldLevel {
            lastEvictionTime = nil
        }
    }
    
    // MARK: - Helpers
    
    /// Returns the cooldown interval to wait after eviction before evicting more.
    private func cooldownInterval(for level: PressureLevel) -> TimeInterval {
        switch level {
        case .normal:
            0 // No cooldown when normal
        case .warning:
            10.0 // Wait 10 seconds
        case .critical:
            5.0 // Shorter wait when critical
        }
    }
}

// MARK: - ThermalState Comparable

extension ProcessInfo.ThermalState: @retroactive Comparable {
    public static func < (lhs: ProcessInfo.ThermalState, rhs: ProcessInfo.ThermalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
