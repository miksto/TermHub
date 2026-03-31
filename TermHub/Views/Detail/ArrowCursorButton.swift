import AppKit

class ArrowCursorButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
