import SwiftTerm

class TermHubTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?

    override func bell(source: Terminal) {
        onBell?()
    }
}
