import AppKit
import SwiftUI

// MARK: - Row Model

enum DiffRowKind {
    case fileHeader(DiffFile)
    case hunkHeader(hunk: DiffHunk, file: DiffFile)
    case unifiedLine(DiffLine)
    case sideBySideLine(old: DiffLine?, new: DiffLine?)
    case fileSeparator
}

struct DiffRow {
    let kind: DiffRowKind
    /// Index of the hunk within its file (for future discard-hunk actions).
    let hunkIndex: Int?
    /// Index of the file within the diff.
    let fileIndex: Int
}

// MARK: - Row Heights

private enum DiffMetrics {
    static let lineRowHeight: CGFloat = 20
    static let fileHeaderRowHeight: CGFloat = 28
    static let hunkHeaderRowHeight: CGFloat = 22
    static let separatorRowHeight: CGFloat = 1
    static let gutterWidth: CGFloat = 44
    static let prefixWidth: CGFloat = 14
}

// MARK: - Row Builder

enum DiffRowBuilder {
    static func buildRows(from diff: GitDiff, sideBySide: Bool) -> [DiffRow] {
        var rows: [DiffRow] = []
        for (fileIdx, file) in diff.files.enumerated() {
            rows.append(DiffRow(kind: .fileHeader(file), hunkIndex: nil, fileIndex: fileIdx))

            if !file.isBinary {
                for (hunkIdx, hunk) in file.hunks.enumerated() {
                    rows.append(DiffRow(
                        kind: .hunkHeader(hunk: hunk, file: file),
                        hunkIndex: hunkIdx,
                        fileIndex: fileIdx
                    ))

                    if sideBySide {
                        for pair in pairLines(hunk.lines) {
                            rows.append(DiffRow(
                                kind: .sideBySideLine(old: pair.old, new: pair.new),
                                hunkIndex: hunkIdx,
                                fileIndex: fileIdx
                            ))
                        }
                    } else {
                        for line in hunk.lines {
                            rows.append(DiffRow(
                                kind: .unifiedLine(line),
                                hunkIndex: hunkIdx,
                                fileIndex: fileIdx
                            ))
                        }
                    }
                }
            }

            rows.append(DiffRow(kind: .fileSeparator, hunkIndex: nil, fileIndex: fileIdx))
        }
        return rows
    }

    private struct LinePair {
        let old: DiffLine?
        let new: DiffLine?
    }

    private static func pairLines(_ lines: [DiffLine]) -> [LinePair] {
        var result: [LinePair] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            switch line.type {
            case .context:
                result.append(LinePair(old: line, new: line))
                i += 1
            case .removed:
                var removed: [DiffLine] = []
                while i < lines.count && lines[i].type == .removed {
                    removed.append(lines[i])
                    i += 1
                }
                var added: [DiffLine] = []
                while i < lines.count && lines[i].type == .added {
                    added.append(lines[i])
                    i += 1
                }
                let maxCount = max(removed.count, added.count)
                for j in 0..<maxCount {
                    result.append(LinePair(
                        old: j < removed.count ? removed[j] : nil,
                        new: j < added.count ? added[j] : nil
                    ))
                }
            case .added:
                result.append(LinePair(old: nil, new: line))
                i += 1
            }
        }
        return result
    }
}

// MARK: - SwiftUI Bridge

struct DiffTableView: NSViewRepresentable {
    let diff: GitDiff

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.usesAutomaticRowHeights = false
        tableView.rowSizeStyle = .custom
        tableView.floatsGroupRows = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        let delegate = DiffTableDelegate()
        delegate.diff = diff
        delegate.lastDiff = diff
        delegate.rebuildRows(for: scrollView.frame.width)
        context.coordinator.delegate = delegate
        context.coordinator.scrollView = scrollView

        tableView.dataSource = delegate
        tableView.delegate = delegate
        tableView.reloadData()

        // Observe frame changes at the AppKit level — no SwiftUI involvement
        scrollView.postsFrameChangedNotifications = true
        context.coordinator.startObservingFrame(scrollView: scrollView, tableView: tableView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView,
              let delegate = context.coordinator.delegate else { return }

        // Only rebuild if the diff data changed
        guard delegate.lastDiff != diff else { return }

        delegate.diff = diff
        delegate.lastDiff = diff
        delegate.rebuildRows(for: scrollView.frame.width)
        tableView.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    class Coordinator {
        var delegate: DiffTableDelegate?
        weak var scrollView: NSScrollView?
        private nonisolated(unsafe) var frameObserver: (any NSObjectProtocol)?

        func startObservingFrame(scrollView: NSScrollView, tableView: NSTableView) {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleFrameChange(tableView: tableView)
                }
            }
        }

        private func handleFrameChange(tableView: NSTableView) {
            guard let delegate, let scrollView else { return }
            let width = scrollView.frame.width
            let newSideBySide = width >= 800
            guard newSideBySide != delegate.isSideBySide else { return }
            delegate.rebuildRows(for: width)
            tableView.reloadData()
        }

        deinit {
            if let observer = frameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

// MARK: - Table Delegate

@MainActor
class DiffTableDelegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var diff: GitDiff = .empty
    var rows: [DiffRow] = []
    var isSideBySide: Bool = false
    var lastDiff: GitDiff = .empty

    func rebuildRows(for width: CGFloat) {
        isSideBySide = width >= 800
        rows = DiffRowBuilder.buildRows(from: diff, sideBySide: isSideBySide)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .fileHeader = rows[row].kind { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row].kind {
        case .fileHeader: DiffMetrics.fileHeaderRowHeight
        case .hunkHeader: DiffMetrics.hunkHeaderRowHeight
        case .unifiedLine, .sideBySideLine: DiffMetrics.lineRowHeight
        case .fileSeparator: DiffMetrics.separatorRowHeight
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let diffRow = rows[row]

        switch diffRow.kind {
        case .fileHeader(let file):
            let id = NSUserInterfaceItemIdentifier("fileHeader")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileHeaderDrawView
                ?? FileHeaderDrawView(identifier: id)
            cell.file = file
            cell.needsDisplay = true
            return cell

        case .hunkHeader(let hunk, _):
            let id = NSUserInterfaceItemIdentifier("hunkHeader")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? HunkHeaderDrawView
                ?? HunkHeaderDrawView(identifier: id)
            cell.hunk = hunk
            cell.needsDisplay = true
            return cell

        case .unifiedLine(let line):
            let id = NSUserInterfaceItemIdentifier("unifiedLine")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? UnifiedLineDrawView
                ?? UnifiedLineDrawView(identifier: id)
            cell.line = line
            cell.needsDisplay = true
            return cell

        case .sideBySideLine(let old, let new):
            let id = NSUserInterfaceItemIdentifier("sideBySideLine")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? SideBySideLineDrawView
                ?? SideBySideLineDrawView(identifier: id)
            cell.oldLine = old
            cell.newLine = new
            cell.needsDisplay = true
            return cell

        case .fileSeparator:
            let id = NSUserInterfaceItemIdentifier("separator")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? SeparatorDrawView
                ?? SeparatorDrawView(identifier: id)
            return cell
        }
    }
}

// MARK: - Colors

@MainActor
private enum DiffColors {
    static let addedBg = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.12)
    static let removedBg = NSColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 0.12)
    static let addedGutterBg = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.18)
    static let removedGutterBg = NSColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 0.18)
    static let contextGutterBg = NSColor.white.withAlphaComponent(0.03)
    static let addedFg = NSColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1.0)
    static let removedFg = NSColor(red: 0.9, green: 0.6, blue: 0.6, alpha: 1.0)
    static let contextFg = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
    static let gutterFg = NSColor.secondaryLabelColor
    static let hunkHeaderBg = NSColor.cyan.withAlphaComponent(0.05)
    static let hunkHeaderFg = NSColor.cyan.withAlphaComponent(0.6)
    static let fileHeaderBg = NSColor.white.withAlphaComponent(0.05)
    static let separatorColor = NSColor.white.withAlphaComponent(0.06)
    static let dividerColor = NSColor.white.withAlphaComponent(0.08)

    static func background(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: addedBg
        case .removed: removedBg
        case .context: .clear
        }
    }

    static func gutterBackground(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: addedGutterBg
        case .removed: removedGutterBg
        case .context: contextGutterBg
        }
    }

    static func foreground(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: addedFg
        case .removed: removedFg
        case .context: contextFg
        }
    }

    static func prefix(for type: DiffLineType) -> String {
        switch type {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        }
    }
}

// MARK: - Fonts

@MainActor
private enum DiffFonts {
    static let mono = NSFont(name: "SF Mono", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let monoSmall = NSFont(name: "SF Mono", size: 11)
        ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let monoMedium = NSFont(name: "SF Mono", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
}

// MARK: - Draw Helpers

@MainActor
private enum DiffDrawing {
    static func drawGutterText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let y = rect.midY - size.height / 2
        // Right-align within rect with 4pt padding
        let x = rect.maxX - size.width - 4
        (text as NSString).draw(at: NSPoint(x: max(rect.minX, x), y: y), withAttributes: attrs)
    }

    static func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let y = rect.midY - size.height / 2
        let x = centered ? rect.midX - size.width / 2 : rect.minX
        (text as NSString).draw(
            in: NSRect(x: x, y: y, width: rect.width - (x - rect.minX), height: size.height),
            withAttributes: attrs
        )
    }

    static func drawLineSide(
        line: DiffLine?, isOld: Bool, in rect: NSRect, font: NSFont, gutterFont: NSFont
    ) {
        let gw = DiffMetrics.gutterWidth
        let pw = DiffMetrics.prefixWidth
        let gutterRect = NSRect(x: rect.minX, y: rect.minY, width: gw, height: rect.height)
        let prefixRect = NSRect(x: rect.minX + gw, y: rect.minY, width: pw, height: rect.height)
        let contentRect = NSRect(
            x: rect.minX + gw + pw, y: rect.minY,
            width: rect.width - gw - pw - 4, height: rect.height
        )

        if let line {
            let fg = DiffColors.foreground(for: line.type)

            // Gutter background
            DiffColors.gutterBackground(for: line.type).setFill()
            gutterRect.fill()

            // Line background (full side)
            let bg = DiffColors.background(for: line.type)
            if bg != .clear {
                bg.setFill()
                NSRect(x: rect.minX + gw, y: rect.minY, width: rect.width - gw, height: rect.height).fill()
            }

            // Gutter text
            let lineNum = isOld ? line.oldLineNumber : line.newLineNumber
            if let num = lineNum {
                drawGutterText(String(num), in: gutterRect, font: gutterFont, color: DiffColors.gutterFg)
            }

            // Prefix
            drawText(DiffColors.prefix(for: line.type), in: prefixRect, font: font, color: fg, centered: true)

            // Content
            drawText(line.content, in: contentRect, font: font, color: fg)
        } else {
            // Empty side
            DiffColors.contextGutterBg.setFill()
            gutterRect.fill()
        }
    }
}

// MARK: - File Header Cell (draw-based)

private class FileHeaderDrawView: NSView {
    var file: DiffFile?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let file else { return }
        let bounds = self.bounds

        // Background
        DiffColors.fileHeaderBg.setFill()
        bounds.fill()

        // File path
        let pathAttrs: [NSAttributedString.Key: Any] = [
            .font: DiffFonts.monoMedium,
            .foregroundColor: NSColor.white,
        ]
        let pathSize = (file.displayPath as NSString).size(withAttributes: pathAttrs)
        let pathY = bounds.midY - pathSize.height / 2
        let pathRect = NSRect(x: 12, y: pathY, width: bounds.width - 120, height: pathSize.height)
        (file.displayPath as NSString).draw(with: pathRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: pathAttrs)

        // Stats
        if file.isBinary {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: DiffFonts.monoSmall,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let text = "Binary"
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: NSPoint(x: bounds.maxX - size.width - 12, y: bounds.midY - size.height / 2),
                withAttributes: attrs
            )
        } else {
            let addedStr = "+\(file.linesAdded)"
            let deletedStr = " −\(file.linesDeleted)"

            let addedAttrs: [NSAttributedString.Key: Any] = [
                .font: DiffFonts.monoSmall, .foregroundColor: NSColor.systemGreen,
            ]
            let deletedAttrs: [NSAttributedString.Key: Any] = [
                .font: DiffFonts.monoSmall, .foregroundColor: NSColor.systemRed,
            ]

            let addedSize = (addedStr as NSString).size(withAttributes: addedAttrs)
            let deletedSize = (deletedStr as NSString).size(withAttributes: deletedAttrs)
            let totalWidth = addedSize.width + deletedSize.width
            let startX = bounds.maxX - totalWidth - 12
            let y = bounds.midY - addedSize.height / 2

            (addedStr as NSString).draw(at: NSPoint(x: startX, y: y), withAttributes: addedAttrs)
            (deletedStr as NSString).draw(at: NSPoint(x: startX + addedSize.width, y: y), withAttributes: deletedAttrs)
        }
    }
}

// MARK: - Hunk Header Cell (draw-based)

private class HunkHeaderDrawView: NSView {
    var hunk: DiffHunk?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let hunk else { return }
        let bounds = self.bounds

        DiffColors.hunkHeaderBg.setFill()
        bounds.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: DiffFonts.monoSmall,
            .foregroundColor: DiffColors.hunkHeaderFg,
        ]
        let size = (hunk.header as NSString).size(withAttributes: attrs)
        let y = bounds.midY - size.height / 2
        let rect = NSRect(x: 12, y: y, width: bounds.width - 24, height: size.height)
        (hunk.header as NSString).draw(with: rect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)
    }
}

// MARK: - Unified Line Cell (draw-based)

private class UnifiedLineDrawView: NSView {
    var line: DiffLine?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let line else { return }
        let bounds = self.bounds
        let gw = DiffMetrics.gutterWidth
        let pw = DiffMetrics.prefixWidth
        let font = DiffFonts.mono
        let fg = DiffColors.foreground(for: line.type)

        // Line background
        let bg = DiffColors.background(for: line.type)
        if bg != .clear {
            bg.setFill()
            bounds.fill()
        }

        // Old gutter background + text
        let oldGutterRect = NSRect(x: 0, y: 0, width: gw, height: bounds.height)
        DiffColors.gutterBackground(for: line.type).setFill()
        oldGutterRect.fill()
        if let num = line.oldLineNumber {
            DiffDrawing.drawGutterText(String(num), in: oldGutterRect, font: font, color: DiffColors.gutterFg)
        }

        // New gutter background + text
        let newGutterRect = NSRect(x: gw, y: 0, width: gw, height: bounds.height)
        DiffColors.gutterBackground(for: line.type).setFill()
        newGutterRect.fill()
        if let num = line.newLineNumber {
            DiffDrawing.drawGutterText(String(num), in: newGutterRect, font: font, color: DiffColors.gutterFg)
        }

        // Prefix
        let prefixRect = NSRect(x: gw * 2, y: 0, width: pw, height: bounds.height)
        DiffDrawing.drawText(DiffColors.prefix(for: line.type), in: prefixRect, font: font, color: fg, centered: true)

        // Content
        let contentX = gw * 2 + pw
        let contentRect = NSRect(x: contentX, y: 0, width: bounds.width - contentX - 4, height: bounds.height)
        DiffDrawing.drawText(line.content, in: contentRect, font: font, color: fg)
    }
}

// MARK: - Side-by-Side Line Cell (draw-based)

private class SideBySideLineDrawView: NSView {
    var oldLine: DiffLine?
    var newLine: DiffLine?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let half = floor(bounds.width / 2)
        let font = DiffFonts.mono

        // Left side
        let leftRect = NSRect(x: 0, y: 0, width: half, height: bounds.height)
        DiffDrawing.drawLineSide(line: oldLine, isOld: true, in: leftRect, font: font, gutterFont: font)

        // Center divider
        DiffColors.dividerColor.setFill()
        NSRect(x: half, y: 0, width: 1, height: bounds.height).fill()

        // Right side
        let rightRect = NSRect(x: half + 1, y: 0, width: bounds.width - half - 1, height: bounds.height)
        DiffDrawing.drawLineSide(line: newLine, isOld: false, in: rightRect, font: font, gutterFont: font)
    }
}

// MARK: - Separator Cell (draw-based)

private class SeparatorDrawView: NSView {
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        DiffColors.separatorColor.setFill()
        bounds.fill()
    }
}
