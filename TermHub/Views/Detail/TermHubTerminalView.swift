import AppKit
import SwiftTerm

class TermHubTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    /// When true, scroll events are consumed and not forwarded to the terminal.
    var blockScrollEvents = false
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

    // Accumulate data from the process and feed it to the terminal in larger
    // batches. SwiftTerm's LocalProcess delivers data in 4ms time-sliced chunks
    // via drainReceivedData. Between chunks, queuePendingDisplay can fire a
    // display update that shows a partially-drawn tmux screen (e.g. cleared top
    // rows before the bottom rows arrive). By buffering data and flushing on a
    // short delay, we ensure complete tmux screen updates reach the terminal
    // together, eliminating the visible top-to-bottom redraw artifact.
    private var pendingData: [UInt8] = []
    private var flushScheduled = false

    override func dataReceived(slice: ArraySlice<UInt8>) {
        pendingData.append(contentsOf: slice)
        if !flushScheduled {
            flushScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingData()
            }
        }
    }

    private func flushPendingData() {
        flushScheduled = false
        guard !pendingData.isEmpty else { return }
        let data = pendingData
        pendingData.removeAll(keepingCapacity: true)
        feed(byteArray: data[...])
    }

    // Monitor Shift key to temporarily disable mouse reporting,
    // enabling native text selection even when tmux has mouse mode active.
    func installEventMonitors() {
        // Shift+Enter: send LF (0x0A) instead of CR so the shell can bind it
        // to newline insertion (e.g. `bindkey '^J' self-insert` in zsh).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == 36,
                  event.modifierFlags.contains(.shift),
                  self.window != nil,
                  event.window === self.window else {
                return event
            }
            self.send([0x0A])
            return nil
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
