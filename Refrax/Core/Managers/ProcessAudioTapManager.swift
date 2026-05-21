import AudioToolbox
import AVFoundation
import Darwin.libproc
import Foundation
import ObjectiveC
import Observation

/// Controller that captures audio from WebKit's GPU process and re-routes it through
/// our process so that ScreenCaptureKit can include it when screen sharing.
///
/// ## Background
///
/// WebKit renders audio in a separate system process (`com.apple.WebKit.GPU`), which means
/// ScreenCaptureKit cannot attribute that audio to our app. Chrome works around this by
/// bundling their own Audio Service within their app bundle.
///
/// This controller uses a process audio tap to capture WebKit.GPU's audio output and
/// re-emit it from our process, making it visible to ScreenCaptureKit.
///
/// ## Usage
///
/// ```swift
/// let controller = ProcessAudioTapManager()
/// controller.beginWindowSharing() // Call when screen sharing is detected
/// controller.endWindowSharing()   // Call when screen sharing ends
/// ```

final class ProcessAudioTapManager: NSObject {
    // MARK: - Types

    private enum Constants {
        static let webKitGPUProcessName = "WebKit.GPU"
        static let refreshRate: NSNumber = 60
        static let sampleRateFallback: Double = 48_000
        static let channelCountFallback: UInt32 = 2
        static let maxPidPathLength = 4_096 // PROC_PIDPATHINFO_MAXSIZE
    }

    // MARK: - State

    unowned let tabManager: TabManager
    
    private(set) var isCapturing = false

    // These need nonisolated(unsafe) for deinit cleanup
    // Using NSObject instead of MPCProcessAudioTap to avoid linker dependency
    private nonisolated(unsafe) var processTap: NSObject?
    private nonisolated(unsafe) var frameworkHandle: UnsafeMutableRawPointer?
    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    private var activeShareCount = 0
    private var mutedPageStates: [TabPage.ID: Bool] = [:]

    private var muteObservationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init()
    }

    deinit {
        // Clean up synchronously without calling main-actor-isolated methods
        processTap?.perform(NSSelectorFromString("stop"))
        processTap = nil
        unloadFramework()
        playerNode?.stop()
        audioEngine?.stop()
    }

    // MARK: - Public Methods

    /// Increments the screen sharing reference count and starts capture if needed.
    func beginWindowSharing() {
        if activeShareCount == 0 {
            guard startCapturing() else { return }
        }
        activeShareCount += 1
    }

    /// Decrements the screen sharing reference count and stops capture if needed.
    func endWindowSharing() {
        guard activeShareCount > 0 else { return }
        activeShareCount -= 1
        if activeShareCount == 0 {
            stopCapturing()
        }
    }

    /// Starts capturing audio from the WebKit GPU process.
    ///
    /// This finds the WebKit.GPU process, creates an audio tap, and begins
    /// routing captured audio through our process via AVAudioEngine.
    private func startCapturing() -> Bool {
        guard !isCapturing else {
            Logger.debug("Already capturing audio", category: Logger.webview)
            return true
        }

        guard let webKitPID = findWebKitGPUProcess() else {
            Logger.warning("WebKit.GPU process not found - cannot capture audio", category: Logger.webview)
            return false
        }

        Logger.info("Found WebKit.GPU process: PID \(webKitPID)", category: Logger.webview)

        guard let tap = createProcessTap(pid: webKitPID) else {
            Logger.error("Failed to create process tap for PID \(webKitPID)", category: Logger.webview)
            return false
        }

        let sampleRate = tapSampleRate(tap) ?? Constants.sampleRateFallback
        let channelCount = tapChannelCount(tap) ?? Constants.channelCountFallback

        // Set up audio engine for output
        guard setupAudioEngine(sampleRate: sampleRate, channelCount: channelCount) else {
            Logger.error("Failed to set up audio engine", category: Logger.webview)
            tap.perform(NSSelectorFromString("stop"))
            processTap = nil
            return false
        }

        // Start the process tap
        processTap = tap
        tap.perform(NSSelectorFromString("start"))

        isCapturing = true
        startMuteObservationIfNeeded()
        Logger.info("Started capturing WebKit.GPU audio (PID: \(webKitPID))", category: Logger.webview)
        return true
    }

    /// Stops capturing audio and releases resources.
    private func stopCapturing() {
        guard isCapturing else { return }

        // Stop and release the tap
        processTap?.perform(NSSelectorFromString("stop"))
        processTap = nil

        // Tear down audio engine
        tearDownAudioEngine()

        stopMuteObservation()
        unloadFramework()
        isCapturing = false
        Logger.info("Stopped capturing WebKit.GPU audio", category: Logger.webview)
    }

    // MARK: - Private Methods

    /// Finds the PID of the WebKit GPU process.
    private func findWebKitGPUProcess() -> pid_t? {
        if let pid = gpuProcessIdentifierFromActivePages() {
            return pid
        }

        // WebKit.GPU is not a regular app, so enumerate processes directly.
        var pids = [pid_t](repeating: 0, count: 1_024)
        var numberOfProcesses = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        numberOfProcesses /= Int32(MemoryLayout<pid_t>.size)

        let currentPID = getpid()
        var fallbackPID: pid_t?

        for i in 0 ..< Int(numberOfProcesses) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var pathBuffer = [CChar](repeating: 0, count: Constants.maxPidPathLength)
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

            if pathLength > 0 {
                // swiftlint:disable:next optional_data_string_conversion
                let path = String(decoding: pathBuffer.prefix(Int(pathLength)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if path.contains(Constants.webKitGPUProcessName) {
                    if isChildProcess(pid, of: currentPID) {
                        return pid
                    }
                    fallbackPID = pid
                }
            }
        }

        if let fallbackPID {
            Logger.warning("Using fallback WebKit.GPU PID \(fallbackPID) (parent not matched)", category: Logger.webview)
            return fallbackPID
        }

        return nil
    }

    private func gpuProcessIdentifierFromActivePages() -> pid_t? {
        if let controller = tabManager.windowManager.activeWindowController,
           let focusedPage = controller.windowState.focusedWebPage,
           let pid = gpuProcessIdentifier(for: focusedPage) {
            return pid
        }

        if let playingPage = tabManager.pagePool.activePages.values.first(where: { $0.isPlayingAudio }),
           let pid = gpuProcessIdentifier(for: playingPage) {
            return pid
        }

        if let anyPage = tabManager.pagePool.activePages.values.first,
           let pid = gpuProcessIdentifier(for: anyPage) {
            return pid
        }

        return nil
    }

    private func gpuProcessIdentifier(for page: WebPage) -> pid_t? {
        let pid = page.backingWebView._gpuProcessIdentifier
        return pid > 0 ? pid : nil
    }

    private func isChildProcess(_ pid: pid_t, of parentPID: pid_t) -> Bool {
        var bsdInfo = proc_bsdinfo()
        let infoSize = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &bsdInfo,
            Int32(MemoryLayout<proc_bsdinfo>.size),
        )
        guard infoSize == Int32(MemoryLayout<proc_bsdinfo>.size) else {
            return false
        }
        return bsdInfo.pbi_ppid == parentPID
    }

    private func startMuteObservationIfNeeded() {
        muteActivePages()

        muteObservationTask?.cancel()
        muteObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Observe pagesVersion instead of activePages to avoid cascade invalidation.
            // pagesVersion only increments when pages are structurally added/removed.
            let pageChanges = Observations { self.tabManager.pagePool.pagesVersion }
            for await _ in pageChanges {
                guard isCapturing else { return }
                muteActivePages()
            }
        }
    }

    private func stopMuteObservation() {
        muteObservationTask?.cancel()
        muteObservationTask = nil
        restorePageMuteStates()
    }

    private func muteActivePages() {
        for (pageID, page) in tabManager.pagePool.activePages {
            if mutedPageStates[pageID] == nil {
                mutedPageStates[pageID] = page.isAudioMuted
            }
            if !page.isAudioMuted {
                page.setAudioMuted(true)
            }
        }
    }

    private func restorePageMuteStates() {
        for (pageID, wasMuted) in mutedPageStates {
            if let page = tabManager.pagePool.activePages[pageID] {
                page.setAudioMuted(wasMuted)
            }
        }
        mutedPageStates.removeAll()
    }

    private func loadFrameworkIfNeeded() -> Bool {
        if frameworkHandle != nil {
            return true
        }

        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore",
            RTLD_NOW,
        ) else {
            Logger.error("Failed to load MediaPlaybackCore framework", category: Logger.webview)
            return false
        }

        frameworkHandle = handle
        return true
    }

    private nonisolated func unloadFramework() {
        if let handle = frameworkHandle {
            dlclose(handle)
            frameworkHandle = nil
        }
    }

    /// Sets up AVAudioEngine for audio output.
    private func setupAudioEngine(sampleRate: Double, channelCount: UInt32) -> Bool {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else {
            return false
        }

        audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount,
        )

        guard let format = audioFormat else {
            return false
        }

        // Attach and connect nodes
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.play()
            Logger.debug("Audio engine started", category: Logger.webview)
            return true
        } catch {
            Logger.error("Failed to start audio engine: \(error)", category: Logger.webview)
            return false
        }
    }

    /// Tears down the audio engine.
    private func tearDownAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        audioFormat = nil
    }

    /// Creates the process audio tap using private MediaPlaybackCore API.
    private func createProcessTap(pid: pid_t) -> NSObject? {
        guard loadFrameworkIfNeeded() else { return nil }

        // Get the class dynamically to avoid linker dependency
        guard let tapClass = NSClassFromString("MPCProcessAudioTap") else {
            Logger.error("MPCProcessAudioTap class not found", category: Logger.webview)
            return nil
        }

        let initSelector = NSSelectorFromString("initWithPID:refreshRate:delegate:")

        // Verify the class responds to our initializer and get method
        guard let initMethod = class_getInstanceMethod(tapClass, initSelector) else {
            Logger.error("MPCProcessAudioTap does not respond to initWithPID:refreshRate:delegate:", category: Logger.webview)
            return nil
        }

        // Get alloc method from metaclass
        let allocSelector = NSSelectorFromString("alloc")
        guard let metaClass = object_getClass(tapClass),
              let allocMethod = class_getClassMethod(metaClass, allocSelector) else {
            Logger.error("Failed to get alloc method for MPCProcessAudioTap", category: Logger.webview)
            return nil
        }

        // Call alloc
        typealias AllocMethod = @convention(c) (AnyClass, Selector) -> AnyObject
        let allocIMP = method_getImplementation(allocMethod)
        let allocFunc = unsafeBitCast(allocIMP, to: AllocMethod.self)
        let allocated = allocFunc(tapClass, allocSelector)

        // Call init with our parameters
        typealias InitMethod = @convention(c) (AnyObject, Selector, Int32, NSNumber, AnyObject?) -> AnyObject?
        let initIMP = method_getImplementation(initMethod)
        let initFunc = unsafeBitCast(initIMP, to: InitMethod.self)

        guard let tap = initFunc(allocated, initSelector, Int32(pid), Constants.refreshRate, self) as? NSObject else {
            Logger.error("MPCProcessAudioTap initWithPID failed", category: Logger.webview)
            return nil
        }

        return tap
    }

    /// Gets the sample rate from the tap using KVC.
    private func tapSampleRate(_ tap: NSObject) -> Double? {
        guard let value = tap.value(forKey: "sampleRate") as? UInt32, value > 0 else {
            return nil
        }
        return Double(value)
    }

    /// Gets the channel count from the tap using KVC.
    private func tapChannelCount(_ tap: NSObject) -> UInt32? {
        guard let value = tap.value(forKey: "numberOfChannels") as? UInt32, value > 0 else {
            return nil
        }
        return value
    }

    /// Schedules audio samples for playback.
    private func scheduleAudioSamples(_ samples: [Float]) {
        guard let player = playerNode,
              let format = audioFormat,
              player.isPlaying else {
            return
        }

        // Create a buffer and copy samples
        let channelCount = Int(format.channelCount)
        let frameCount = max(samples.count / channelCount, 0)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount),
        ) else {
            return
        }

        buffer.frameLength = buffer.frameCapacity

        // Copy interleaved samples to the buffer
        if let channelData = buffer.floatChannelData {
            for frame in 0 ..< frameCount {
                for channel in 0 ..< channelCount {
                    let sampleIndex = frame * channelCount + channel
                    channelData[channel][frame] = samples[sampleIndex]
                }
            }
        }

        // Schedule for playback
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}

// MARK: - Process Audio Tap Delegate

extension ProcessAudioTapManager {
    /// Called by MPCProcessAudioTap when audio samples are available.
    /// This is invoked via the delegate mechanism.
    @objc
    nonisolated func processAudioTapDidReceiveAudioSamples(_ samples: UnsafeRawPointer, numberOfSamples: UInt32) {
        let count = Int(numberOfSamples)
        guard count > 0 else { return }

        let floatSamples = samples.assumingMemoryBound(to: Float.self)
        let copiedSamples = Array(UnsafeBufferPointer(start: floatSamples, count: count))

        DispatchQueue.main.async { [weak self] in
            self?.scheduleAudioSamples(copiedSamples)
        }
    }

    @objc
    nonisolated func processAudioTapDidStop() {
        Logger.debug("Process audio tap stopped", category: Logger.webview)
        // The tap stopped (e.g., target process terminated)
        // We'll leave cleanup to the normal stopCapturing() flow
    }
}
