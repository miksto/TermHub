import AppKit
import SwiftTerm

class TermHubTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    /// When true, scroll events are consumed and not forwarded to the terminal.
    var blockScrollEvents = false
    /// When true, the terminal just started a process and is receiving the
    /// initial burst of data (e.g. tmux replaying its buffer). Data is parsed
    /// but not rendered. Once no new data arrives for a short period, this
    /// flips to false and a single redraw shows the final state instantly.
    var suppressRendering: Bool = false
    private var suppressionSettleTimer: Timer?

    /// Controls whether terminal rendering is active.
    /// Hidden terminals still parse data (keeping the buffer current) but skip
    /// all display work (feedPrepare/feedFinish/queuePendingDisplay/updateDisplay).
    /// Event monitors are also installed/removed based on this flag.
    var isVisible: Bool = false {
        didSet {
            guard isVisible != oldValue else { return }
            if isVisible {
                installEventMonitors()
                // Flush any data that accumulated while hidden, with rendering.
                if !pendingData.isEmpty {
                    flushPendingData()
                }
                // The buffer is already up-to-date (hidden terminals parse data),
                // so a single redraw is enough to show current content.
                needsDisplay = true
            } else {
                removeEventMonitors()
            }
        }
    }
    private nonisolated(unsafe) var flagsMonitor: Any?
    private nonisolated(unsafe) var scrollMonitor: Any?
    private nonisolated(unsafe) var keyMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }
        let paths = urls.map { shellEscape($0.path) }.joined(separator: " ")
        // Use the system paste mechanism so SwiftTerm handles bracketed paste mode.
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
        paste(self)
        // Restore previous pasteboard contents.
        pasteboard.clearContents()
        if let previousContents {
            pasteboard.setString(previousContents, forType: .string)
        }
        return true
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    override func bell(source: Terminal) {
        onBell?()
    }

    // Accumulate data from the process and feed it to the terminal in batches.
    //
    // Visible terminals: throttled to ~60fps, uses self.feed() which parses
    // data AND triggers rendering (feedPrepare/feedFinish/queuePendingDisplay).
    //
    // Hidden terminals: flushed on a 1s timer, uses getTerminal().feed() which
    // only parses data (updates buffer, fires bell callbacks) without any
    // display work. This keeps the buffer current so switching is instant.
    private var pendingData: [UInt8] = []
    private var flushScheduled = false
    private var lastFlushTime: UInt64 = 0
    private var slowFlushTimer: Timer?
    private static let flushIntervalNs: UInt64 = 16_000_000 // ~60fps

    override func dataReceived(slice: ArraySlice<UInt8>) {
        pendingData.append(contentsOf: slice)

        if suppressRendering {
            // During initial burst: parse data without rendering, and reset
            // the settle timer. Once data stops arriving, we redraw once.
            suppressionSettleTimer?.invalidate()
            suppressionSettleTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.finishSuppression()
                }
            }
            // Flush parse-only on a short timer to keep buffer current.
            if slowFlushTimer == nil {
                slowFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.slowFlushTimer = nil
                        self?.flushPendingDataParseOnly()
                    }
                }
            }
        } else if isVisible {
            guard !flushScheduled else { return }
            flushScheduled = true

            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = now - lastFlushTime
            if elapsed >= Self.flushIntervalNs {
                // Enough time has passed — flush immediately (keeps typing snappy).
                DispatchQueue.main.async { [weak self] in
                    self?.flushPendingData()
                }
            } else {
                // Throttle: wait for the remainder of the frame interval.
                let remaining = Self.flushIntervalNs - elapsed
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(remaining))
                ) { [weak self] in
                    self?.flushPendingData()
                }
            }
        } else {
            // Hidden: parse on a 1s timer to keep the buffer current
            // without doing any rendering work.
            if slowFlushTimer == nil {
                slowFlushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.slowFlushTimer = nil
                        self?.flushPendingDataParseOnly()
                    }
                }
            }
        }
    }

    /// End the suppression period: parse any remaining data, then redraw once.
    private func finishSuppression() {
        suppressRendering = false
        suppressionSettleTimer?.invalidate()
        suppressionSettleTimer = nil
        // Parse any remaining data without rendering.
        flushPendingDataParseOnly()
        // Single redraw to show the final buffer state.
        needsDisplay = true
    }

    /// Flush with full rendering (visible terminals).
    private func flushPendingData() {
        flushScheduled = false
        slowFlushTimer?.invalidate()
        slowFlushTimer = nil
        guard !pendingData.isEmpty else { return }
        let data = pendingData
        pendingData.removeAll(keepingCapacity: true)
        lastFlushTime = DispatchTime.now().uptimeNanoseconds
        feed(byteArray: data[...])
    }

    /// Flush with parsing only, no rendering (hidden terminals).
    /// Updates the terminal buffer and fires callbacks (e.g. bell)
    /// but skips feedPrepare/feedFinish/queuePendingDisplay/updateDisplay.
    private func flushPendingDataParseOnly() {
        guard !pendingData.isEmpty else { return }
        let data = pendingData
        pendingData.removeAll(keepingCapacity: true)
        getTerminal().feed(buffer: data[...])
    }

    // Monitor Shift key to temporarily disable mouse reporting,
    // enabling native text selection even when tmux has mouse mode active.
    func installEventMonitors() {
        // Shift+Enter: send LF (0x0A) instead of CR so the shell can bind it
        // to newline insertion (e.g. `bindkey '^J' self-insert` in zsh).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.window != nil,
                  event.window === self.window else {
                return event
            }

            // Shift+Enter: send LF (0x0A) instead of CR
            if event.keyCode == 36, event.modifierFlags.contains(.shift) {
                self.send([0x0A])
                return nil
            }

            // When optionAsMetaKey is off, SwiftTerm skips all Option key
            // handling. Intercept Option+navigation/editing keys here so
            // they still work as Meta sequences. Skip when Command is also
            // held so Cmd+Option shortcuts (tab switching, etc.) pass through.
            if !self.optionAsMetaKey
                && event.modifierFlags.contains(.option)
                && !event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let scalar = chars.unicodeScalars.first {
                switch Int(scalar.value) {
                case NSLeftArrowFunctionKey:
                    self.send(EscapeSequences.emacsBack)
                    return nil
                case NSRightArrowFunctionKey:
                    self.send(EscapeSequences.emacsForward)
                    return nil
                case 0x7f: // Backspace — delete word backward
                    self.send(EscapeSequences.cmdEsc)
                    self.send(EscapeSequences.cmdDel)
                    return nil
                case NSDeleteFunctionKey: // Forward Delete — delete word forward
                    self.send([0x1b, 0x1b, 0x5b, 0x33, 0x7e])
                    return nil
                default: break
                }
            }

            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.shift) {
                self.allowMouseReporting = false
            } else {
                self.allowMouseReporting = true
            }
            return event
        }

        // Forward scroll wheel events to the running process (e.g. tmux) when
        // mouse reporting is active. SwiftTerm only scrolls its local buffer,
        // which is empty when tmux manages the scrollback.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  !self.isHidden,
                  self.window != nil,
                  let eventWindow = event.window,
                  eventWindow === self.window else {
                return event
            }

            // Check that the scroll is over this terminal view.
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }

            // When the command palette is open, skip all terminal scroll handling.
            // Return the event so AppKit's normal hit-testing can route it to the
            // SwiftUI ScrollView in the palette overlay (which is on top in the ZStack).
            if self.blockScrollEvents { return event }

            guard event.deltaY != 0 else { return event }

            let terminal = self.getTerminal()
            if self.allowMouseReporting && terminal.mouseMode != .off {
                let isUp = event.deltaY > 0
                let flags = event.modifierFlags
                let buttonFlags = terminal.encodeButton(
                    button: isUp ? 4 : 5,
                    release: false,
                    shift: flags.contains(.shift),
                    meta: flags.contains(.option),
                    control: flags.contains(.control)
                )
                let cellWidth = self.bounds.width / CGFloat(max(terminal.cols, 1))
                let cellHeight = self.bounds.height / CGFloat(max(terminal.rows, 1))
                let col = min(max(0, Int(locationInView.x / cellWidth)), terminal.cols - 1)
                let row = min(max(0, Int((self.bounds.height - locationInView.y) / cellHeight)), terminal.rows - 1)
                terminal.sendEvent(buttonFlags: buttonFlags, x: col, y: row)
            } else {
                return event
            }
            return nil // Consume the event
        }
    }

    func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
