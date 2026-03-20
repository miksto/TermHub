import AppKit
import SwiftTerm

class TermHubTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    private nonisolated(unsafe) var flagsMonitor: Any?

    override func bell(source: Terminal) {
        onBell?()
    }

    // Monitor Option key to temporarily disable mouse reporting,
    // enabling native text selection even when tmux has mouse mode active.
    func installOptionKeyMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.shift) {
                self.allowMouseReporting = false
            } else {
                self.allowMouseReporting = true
            }
            return event
        }
    }

    func removeOptionKeyMonitor() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }

    deinit {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
