import AppKit
import SwiftUI

/// Controller for the Speed Reader panel.
///
/// Creates a floating panel attached to the parent window that displays article
/// content one word at a time using RSVP (Rapid Serial Visual Presentation).
final class SpeedReaderWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - State

    private let article: ExtractedArticle
    private let speedReaderState: SpeedReaderState
    private let settings: BrowserSettings?
    private weak var parentWindow: NSWindow?

    // MARK: - Initialization

    /// Creates a Speed Reader panel for the given article.
    ///
    /// - Parameters:
    ///   - article: The extracted article to display.
    ///   - settings: Browser settings for WPM persistence (optional).
    ///   - startIndex: Optional starting word index for resume functionality.
    ///   - parentWindow: The window to attach to (stays on top of this window only).
    init(
        article: ExtractedArticle,
        settings: BrowserSettings? = nil,
        startIndex: Int = 0,
        parentWindow: NSWindow? = nil,
    ) {
        self.article = article
        self.settings = settings
        self.parentWindow = parentWindow
        let initialWPM = settings?.speedReaderWPM ?? 250
        self.speedReaderState = SpeedReaderState(article: article, startIndex: startIndex, initialWPM: initialWPM)

        let panel = SpeedReaderPanel(onClose: {})
        super.init(window: panel)

        panel.delegate = self
        panel.onClose = { [weak self] in self?.close() }

        setupContentView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupContentView() {
        guard let panel = window as? SpeedReaderPanel else { return }

        // Wire up WPM persistence callback
        speedReaderState.onWPMChanged = { [weak self] newWPM in
            self?.settings?.speedReaderWPM = newWPM
        }

        speedReaderState.onCloseRequested = { [weak self] in
            self?.close()
        }

        let contentView = SpeedReaderView()
            .environment(speedReaderState)

        panel.setupContent(contentView)
    }

    // MARK: - Window Actions

    /// Shows the Speed Reader panel centered on the parent window's web view area.
    func showCentered() {
        guard let panel = window as? SpeedReaderPanel else { return }

        panel.setContentSize(SpeedReaderPanel.defaultSize)

        if let parentWindow {
            // Position at top center of parent window
            let parentFrame = parentWindow.frame
            let panelSize = SpeedReaderPanel.defaultSize
            let newOrigin = NSPoint(
                x: parentFrame.midX - panelSize.width / 2,
                y: parentFrame.maxY - panelSize.height - 80,
            )
            panel.setFrameOrigin(newOrigin)

            // Add as child window so it stays on top of parent only
            parentWindow.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }

        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        speedReaderState.pause()

        // Remove from parent window
        if let parentWindow, let panel = window {
            parentWindow.removeChildWindow(panel)
        }

        // Save resume position (only if not at the end)
        if !speedReaderState.isAtEnd, speedReaderState.currentIndex > 0 {
            settings?.setSpeedReaderResumePosition(
                speedReaderState.currentIndex,
                for: speedReaderState.articleURL,
            )
        } else if speedReaderState.isAtEnd {
            // Clear position if finished reading
            settings?.clearSpeedReaderResumePosition(for: speedReaderState.articleURL)
        }
    }
}

// MARK: - Speed Reader Panel

/// Floating panel for Speed Reader with transparent vibrancy background.
final class SpeedReaderPanel: NSPanel {
    static let defaultSize = NSSize(width: 500, height: 200)
    static let minimumSize = NSSize(width: 400, height: 160)
    static let maximumSize = NSSize(width: 700, height: 300)

    var onClose: () -> Void = {}

    private var vibrancyView: TintableVisualEffectView?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false,
        )

        title = "Speed Reader"
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        minSize = Self.minimumSize
        maxSize = Self.maximumSize
    }

    func setupContent(_ content: some View) {
        // Create a container that will handle the masking
        let container = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        // Create tint layer for vibrancy
        let tintLayer = CALayer()
        tintLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.3).cgColor

        // Create vibrancy view
        let vibrancy = TintableVisualEffectView(tintLayer: tintLayer)
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.material = .hudWindow
        vibrancy.translatesAutoresizingMaskIntoConstraints = false

        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Build view hierarchy: container > vibrancy > hostingView
        vibrancy.addSubview(hostingView)
        container.addSubview(vibrancy)

        NSLayoutConstraint.activate([
            vibrancy.topAnchor.constraint(equalTo: container.topAnchor),
            vibrancy.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            hostingView.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
        ])

        contentView = container
        vibrancyView = vibrancy
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Speed Reader State

/// Observable state for the Speed Reader.
///
/// Manages playback, word progression, and timing. Uses a timer to advance
/// through words at the configured WPM rate, with pause multipliers for
/// punctuation and paragraph breaks.
@Observable
final class SpeedReaderState {
    // MARK: - Content

    let words: [SpeedReaderWord]
    let articleTitle: String
    let articleURL: URL

    // MARK: - Playback State

    private(set) var currentIndex: Int
    var isPlaying: Bool = false {
        didSet {
            if isPlaying {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    // MARK: - Settings

    /// Words per minute reading speed.
    var wpm: Int {
        didSet {
            onWPMChanged?(wpm)
        }
    }

    /// Callback invoked when WPM changes.
    @ObservationIgnored
    var onWPMChanged: ((Int) -> Void)?

    /// Callback to close the panel.
    @ObservationIgnored
    var onCloseRequested: (() -> Void)?

    // MARK: - Computed

    var currentWord: SpeedReaderWord? {
        guard currentIndex >= 0, currentIndex < words.count else { return nil }
        return words[currentIndex]
    }

    var progress: Double {
        guard !words.isEmpty else { return 0 }
        return Double(currentIndex) / Double(words.count - 1)
    }

    var progressText: String {
        "\(currentIndex + 1) / \(words.count)"
    }

    var isAtEnd: Bool {
        currentIndex >= words.count - 1
    }

    var isAtStart: Bool {
        currentIndex <= 0
    }

    // MARK: - Private

    @ObservationIgnored
    private var timer: Timer?

    // MARK: - Initialization

    init(article: ExtractedArticle, startIndex: Int = 0, initialWPM: Int = 250) {
        self.words = SpeedReaderProcessor.process(article.textContent)
        self.articleTitle = article.title
        self.articleURL = article.sourceURL
        self.currentIndex = min(startIndex, max(0, words.count - 1))
        self.wpm = max(50, min(800, initialWPM))
    }

    // MARK: - Playback Control

    func play() {
        if isAtEnd {
            currentIndex = 0
        }
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func rewind(_ count: Int = 10) {
        currentIndex = max(0, currentIndex - count)
    }

    func skip(_ count: Int = 10) {
        currentIndex = min(words.count - 1, currentIndex + count)
    }

    func goToStart() {
        currentIndex = 0
    }

    func goToEnd() {
        currentIndex = words.count - 1
        pause()
    }

    func seek(to progress: Double) {
        let newIndex = Int(progress * Double(words.count - 1))
        currentIndex = max(0, min(words.count - 1, newIndex))
    }

    func adjustWPM(by delta: Int) {
        let newWPM = wpm + delta
        wpm = max(50, min(800, newWPM))

        if isPlaying {
            startTimer()
        }
    }

    func requestClose() {
        onCloseRequested?()
    }

    // MARK: - Timer Management

    private func startTimer() {
        stopTimer()
        scheduleNextWord()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextWord() {
        guard isPlaying, currentIndex < words.count else {
            if currentIndex >= words.count - 1 {
                pause()
            }
            return
        }

        let word = words[currentIndex]
        let baseInterval = 60.0 / Double(wpm)
        let adjustedInterval = baseInterval * word.pauseMultiplier

        timer = Timer.scheduledTimer(withTimeInterval: adjustedInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceWord()
            }
        }
    }

    private func advanceWord() {
        guard isPlaying else { return }

        if currentIndex < words.count - 1 {
            currentIndex += 1
            scheduleNextWord()
        } else {
            pause()
        }
    }
}

// MARK: - Speed Reader View

/// Main view for the Speed Reader panel.
struct SpeedReaderView: View {
    @Environment(SpeedReaderState.self) private var state

    private enum Layout {
        static let cornerRadius: CGFloat = 16
        static let closeButtonSize: CGFloat = 24
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with close button
            topBar

            // Word display area - takes remaining space
            wordDisplayArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Controls at bottom
            controlsArea
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            state.togglePlayback()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            state.rewind(10)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            state.skip(10)
            return .handled
        }
        .onKeyPress(.upArrow) {
            state.adjustWPM(by: 25)
            return .handled
        }
        .onKeyPress(.downArrow) {
            state.adjustWPM(by: -25)
            return .handled
        }
        .onKeyPress(.escape) {
            state.requestClose()
            return .handled
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button(action: { state.requestClose() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Word Display

    private var wordDisplayArea: some View {
        VStack(spacing: 8) {
            if let word = state.currentWord {
                SpeedReaderWordView(word: word)
            } else {
                Text("No content")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            state.togglePlayback()
        }
    }

    // MARK: - Controls

    private var controlsArea: some View {
        VStack(spacing: 12) {
            // Progress bar
            progressBar

            // Controls: WPM | [spacer] | Play Controls | [spacer] | Progress
            HStack(spacing: 0) {
                // WPM control - left side
                wpmControl
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Centered play controls
                playbackControls

                // Progress text - right side
                Text(state.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .frame(width: geometry.size.width * state.progress)
            }
            .frame(height: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        state.seek(to: progress)
                    },
            )
        }
        .frame(height: 4)
    }

    private var wpmControl: some View {
        HStack(spacing: 8) {
            Button {
                state.adjustWPM(by: -25)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(state.wpm <= 50)

            Text("\(state.wpm) wpm")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 60)

            Button {
                state.adjustWPM(by: 25)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(state.wpm >= 800)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                state.rewind(10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(state.isAtStart)

            Button {
                state.togglePlayback()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                state.skip(10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(state.isAtEnd)
        }
    }
}

// MARK: - Word View with ORP Highlighting

/// Displays a single word with Optimal Recognition Point highlighting.
struct SpeedReaderWordView: View {
    let word: SpeedReaderWord

    private var segments: (prefix: String, orp: String, suffix: String) {
        let text = word.text
        guard !text.isEmpty else { return ("", "", "") }

        let orpIndex = word.orpIndex
        let orpStringIndex = text.index(text.startIndex, offsetBy: orpIndex, limitedBy: text.endIndex)
            ?? text.startIndex

        guard orpStringIndex < text.endIndex else {
            return (text, "", "")
        }

        let prefix = String(text[..<orpStringIndex])
        let orp = String(text[orpStringIndex])
        let suffixStart = text.index(after: orpStringIndex)
        let suffix = suffixStart < text.endIndex ? String(text[suffixStart...]) : ""

        return (prefix, orp, suffix)
    }

    var body: some View {
        let (prefix, orp, suffix) = segments

        VStack(spacing: 8) {
            // ORP indicator line
            HStack(spacing: 0) {
                Text(prefix)
                    .foregroundStyle(.clear)
                Rectangle()
                    .fill(.tint)
                    .frame(width: 2, height: 8)
                Text(orp + suffix)
                    .foregroundStyle(.clear)
            }
            .font(.system(size: 42, weight: .medium, design: .rounded))

            // Word with ORP highlight
            HStack(spacing: 0) {
                Text(prefix)
                    .foregroundStyle(.secondary)
                Text(orp)
                    .foregroundStyle(.primary)
                    .fontWeight(.bold)
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 42, weight: .medium, design: .rounded))
        }
    }
}
