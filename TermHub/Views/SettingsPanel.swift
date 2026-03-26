import AppKit
import SwiftUI

/// Presents `SettingsOverlay` in a borderless child `NSPanel` so that
/// keyboard events are automatically isolated from the main window's terminal.
@MainActor
final class SettingsPanel: NSPanel {
    private static var current: SettingsPanel?

    private var resizeObserver: NSObjectProtocol?

    private init(contentRect: NSRect, appState: AppState) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = false

        let hostingView = NSHostingView(
            rootView: SettingsOverlay()
                .environment(appState)
        )
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    // MARK: - Show / Dismiss

    static func show(in parentWindow: NSWindow, appState: AppState) {
        guard current == nil else { return }

        let panel = SettingsPanel(
            contentRect: parentWindow.frame,
            appState: appState
        )

        // Track parent window resizes / moves
        panel.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { [weak panel, weak parentWindow] _ in
            guard let panel, let parentWindow else { return }
            MainActor.assumeIsolated {
                panel.setFrame(parentWindow.frame, display: true)
            }
        }

        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        current = panel
    }

    static func dismiss() {
        guard let panel = current else { return }
        if let observer = panel.resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        current = nil
    }

    // Allow the panel to become key so it receives keyboard events
    override var canBecomeKey: Bool { true }
}
