import AppKit
import SwiftTerm

class TermHubTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    private nonisolated(unsafe) var flagsMonitor: Any?
    private nonisolated(unsafe) var scrollMonitor: Any?

    override func bell(source: Terminal) {
        onBell?()
    }

    // Monitor Shift key to temporarily disable mouse reporting,
    // enabling native text selection even when tmux has mouse mode active.
    func installEventMonitors() {
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
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
