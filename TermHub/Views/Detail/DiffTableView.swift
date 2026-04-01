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

// MARK: - Selection Model

enum DiffSelectionSide {
    case left, right, unified
}

struct DiffTextPosition: Comparable {
    let row: Int
    let charOffset: Int

    static func < (lhs: DiffTextPosition, rhs: DiffTextPosition) -> Bool {
        (lhs.row, lhs.charOffset) < (rhs.row, rhs.charOffset)
    }
}

struct DiffSelection {
    let side: DiffSelectionSide
    let anchor: DiffTextPosition
    var extent: DiffTextPosition

    var start: DiffTextPosition { min(anchor, extent) }
    var end: DiffTextPosition { max(anchor, extent) }
}

// MARK: - Row Heights

enum DiffMetrics {
    static let lineRowHeight: CGFloat = 20
    static let fileHeaderRowHeight: CGFloat = 28
    static let hunkHeaderRowHeight: CGFloat = 22
    static let separatorRowHeight: CGFloat = 1
    static let gutterWidth: CGFloat = 44
    static let prefixWidth: CGFloat = 14
}

// MARK: - Row Builder

enum DiffRowBuilder {
    static func buildRows(
        from diff: GitDiff,
        sideBySide: Bool,
        expandedFiles: Set<String> = [],
        fileContentsCache: [String: [String]] = [:]
    ) -> [DiffRow] {
        var rows: [DiffRow] = []
        for (fileIdx, file) in diff.files.enumerated() {
            rows.append(DiffRow(kind: .fileHeader(file), hunkIndex: nil, fileIndex: fileIdx))

            let filePath = file.newPath
            if expandedFiles.contains(filePath), let fileLines = fileContentsCache[filePath] {
                rows += buildExpandedRows(for: file, fileLines: fileLines, sideBySide: sideBySide, fileIndex: fileIdx)
            } else if !file.isBinary {
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

    /// Builds rows for an expanded file: all file lines visible with gap context lines filled in.
    /// Hunk header rows are omitted — the continuous context makes them redundant.
    private static func buildExpandedRows(
        for file: DiffFile,
        fileLines: [String],
        sideBySide: Bool,
        fileIndex: Int
    ) -> [DiffRow] {
        var rows: [DiffRow] = []
        var currentOldLine = 1
        var currentNewLine = 1

        for (hunkIdx, hunk) in file.hunks.enumerated() {
            // Fill gap context lines before this hunk
            while currentNewLine < hunk.newStart {
                let content = currentNewLine <= fileLines.count ? fileLines[currentNewLine - 1] : ""
                let gap = DiffLine(type: .context, content: content, oldLineNumber: currentOldLine, newLineNumber: currentNewLine)
                if sideBySide {
                    rows.append(DiffRow(kind: .sideBySideLine(old: gap, new: gap), hunkIndex: nil, fileIndex: fileIndex))
                } else {
                    rows.append(DiffRow(kind: .unifiedLine(gap), hunkIndex: nil, fileIndex: fileIndex))
                }
                currentOldLine += 1
                currentNewLine += 1
            }

            // Emit hunk lines with their existing diff styling
            let oldCount = hunk.lines.filter { $0.oldLineNumber != nil }.count
            let newCount = hunk.lines.filter { $0.newLineNumber != nil }.count
            if sideBySide {
                for pair in pairLines(hunk.lines) {
                    rows.append(DiffRow(kind: .sideBySideLine(old: pair.old, new: pair.new), hunkIndex: hunkIdx, fileIndex: fileIndex))
                }
            } else {
                for line in hunk.lines {
                    rows.append(DiffRow(kind: .unifiedLine(line), hunkIndex: hunkIdx, fileIndex: fileIndex))
                }
            }
            currentOldLine = hunk.oldStart + oldCount
            currentNewLine = hunk.newStart + newCount
        }

        // Fill trailing context lines after the last hunk
        while currentNewLine <= fileLines.count {
            let content = fileLines[currentNewLine - 1]
            let gap = DiffLine(type: .context, content: content, oldLineNumber: currentOldLine, newLineNumber: currentNewLine)
            if sideBySide {
                rows.append(DiffRow(kind: .sideBySideLine(old: gap, new: gap), hunkIndex: nil, fileIndex: fileIndex))
            } else {
                rows.append(DiffRow(kind: .unifiedLine(gap), hunkIndex: nil, fileIndex: fileIndex))
            }
            currentOldLine += 1
            currentNewLine += 1
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
        delegate.rebuildRows(for: scrollView.frame.width, clearExpandState: true)
        delegate.tableView = tableView
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
        delegate.rebuildRows(for: scrollView.frame.width, clearExpandState: true)
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
            if newSideBySide != delegate.isSideBySide {
                delegate.rebuildRows(for: width)
                tableView.reloadData()
            } else if delegate.lineWrapping, abs(width - delegate.lastWidth) > 1 {
                delegate.lastWidth = width
                delegate.invalidateHeightCache()
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<delegate.rows.count))
            }
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
    var lastWidth: CGFloat = 0
    var lineWrapping: Bool = true
    var selection: DiffSelection?
    var workingDir: String = ""
    weak var tableView: NSTableView?
    private var expandedFiles: Set<String> = []
    private var fileContentsCache: [String: [String]] = [:]
    /// Cached row heights keyed by row index, invalidated on width/row changes.
    private var heightCache: [Int: CGFloat] = [:]

    // MARK: Scroll Anchor

    private struct ScrollAnchor {
        let offsetFromViewportTop: CGFloat
        let identifier: RowIdentifier
    }

    private enum RowIdentifier {
        case fileHeader(fileIndex: Int)
        case hunkHeader(fileIndex: Int, newStart: Int)
        case line(fileIndex: Int, newLineNumber: Int?, oldLineNumber: Int?)
        case separator(fileIndex: Int)
    }

    func rebuildRows(for width: CGFloat, clearExpandState: Bool = false) {
        if clearExpandState {
            expandedFiles.removeAll()
            fileContentsCache.removeAll()
        }
        lastWidth = width
        isSideBySide = width >= 800
        rows = DiffRowBuilder.buildRows(
            from: diff,
            sideBySide: isSideBySide,
            expandedFiles: expandedFiles,
            fileContentsCache: fileContentsCache
        )
        heightCache.removeAll(keepingCapacity: true)
        selection = nil
    }

    func isFileExpanded(_ file: DiffFile) -> Bool {
        expandedFiles.contains(file.newPath)
    }

    func toggleExpand(for file: DiffFile, fromHunk hunk: DiffHunk? = nil) {
        let anchor: ScrollAnchor?

        if let hunk {
            // Clicked from a hunk header — anchor to the first line of this hunk
            if let hunkHeaderIdx = rows.firstIndex(where: { row in
                guard case .hunkHeader(let h, let f) = row.kind else { return false }
                return f.newPath == file.newPath && h.newStart == hunk.newStart
            }), hunkHeaderIdx + 1 < rows.count {
                anchor = buildAnchor(forRow: hunkHeaderIdx + 1)
            } else {
                anchor = nil
            }
        } else {
            // Clicked from file header — anchor to the file header itself
            if let fileHeaderIdx = rows.firstIndex(where: { row in
                guard case .fileHeader(let f) = row.kind else { return false }
                return f.newPath == file.newPath
            }) {
                anchor = buildAnchor(forRow: fileHeaderIdx)
            } else {
                anchor = nil
            }
        }

        let path = file.newPath
        if expandedFiles.contains(path) {
            expandedFiles.remove(path)
        } else {
            let fullPath = (workingDir as NSString).appendingPathComponent(path)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return }
            var lines = content.components(separatedBy: .newlines)
            // Remove trailing empty element that results from a final newline
            if lines.last == "" { lines.removeLast() }
            fileContentsCache[path] = lines
            expandedFiles.insert(path)
        }
        rebuildRows(for: lastWidth)
        tableView?.reloadData()

        if let anchor {
            restoreScrollAnchor(anchor)
        }
    }

    func selectionRange(forRow row: Int) -> (start: Int, end: Int)? {
        guard let sel = selection else { return nil }
        let start = sel.start
        let end = sel.end
        guard row >= start.row, row <= end.row else { return nil }

        let content: String?
        switch rows[row].kind {
        case .unifiedLine(let line):
            content = line.content
        case .sideBySideLine(let old, let new):
            switch sel.side {
            case .left: content = old?.content
            case .right: content = new?.content
            case .unified: content = nil
            }
        default:
            return nil
        }
        guard let text = content else { return nil }

        let startChar: Int
        let endChar: Int

        if row == start.row && row == end.row {
            startChar = start.charOffset
            endChar = end.charOffset
        } else if row == start.row {
            startChar = start.charOffset
            endChar = text.count
        } else if row == end.row {
            startChar = 0
            endChar = end.charOffset
        } else {
            startChar = 0
            endChar = text.count
        }

        guard startChar < endChar else { return nil }
        return (startChar, endChar)
    }

    func invalidateHeightCache() {
        heightCache.removeAll(keepingCapacity: true)
    }

    // MARK: Scroll Anchor Capture / Restore

    private func buildAnchor(forRow rowIndex: Int) -> ScrollAnchor? {
        guard let tableView, let scrollView = tableView.enclosingScrollView else { return nil }
        let visibleRect = scrollView.contentView.bounds
        let rowRect = tableView.rect(ofRow: rowIndex)
        let offset = rowRect.origin.y - visibleRect.origin.y

        let row = rows[rowIndex]
        let identifier: RowIdentifier
        switch row.kind {
        case .fileHeader:
            identifier = .fileHeader(fileIndex: row.fileIndex)
        case .hunkHeader(let hunk, _):
            identifier = .hunkHeader(fileIndex: row.fileIndex, newStart: hunk.newStart)
        case .unifiedLine(let line):
            identifier = .line(fileIndex: row.fileIndex, newLineNumber: line.newLineNumber, oldLineNumber: line.oldLineNumber)
        case .sideBySideLine(let old, let new):
            identifier = .line(fileIndex: row.fileIndex, newLineNumber: new?.newLineNumber, oldLineNumber: old?.oldLineNumber)
        case .fileSeparator:
            identifier = .separator(fileIndex: row.fileIndex)
        }

        return ScrollAnchor(offsetFromViewportTop: offset, identifier: identifier)
    }

    private func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        guard let tableView, let scrollView = tableView.enclosingScrollView else { return }

        var targetRowIndex: Int?
        var adjustedOffset = anchor.offsetFromViewportTop

        switch anchor.identifier {
        case .fileHeader(let fileIndex):
            targetRowIndex = rows.firstIndex { row in
                if case .fileHeader = row.kind, row.fileIndex == fileIndex { return true }
                return false
            }

        case .separator(let fileIndex):
            targetRowIndex = rows.firstIndex { row in
                if case .fileSeparator = row.kind, row.fileIndex == fileIndex { return true }
                return false
            }

        case .hunkHeader(let fileIndex, let newStart):
            // Try to find the hunk header (still present when collapsing)
            targetRowIndex = rows.firstIndex { row in
                if case .hunkHeader(let h, _) = row.kind, row.fileIndex == fileIndex, h.newStart == newStart { return true }
                return false
            }
            if targetRowIndex == nil {
                // Hunk header disappeared (expanding) — anchor to the line at newStart.
                // Shift offset so content that was below the header stays in place.
                targetRowIndex = findClosestLineRow(fileIndex: fileIndex, targetNewLine: newStart)
                adjustedOffset += DiffMetrics.hunkHeaderRowHeight
            }

        case .line(let fileIndex, let newLineNumber, let oldLineNumber):
            targetRowIndex = rows.firstIndex { row in
                guard row.fileIndex == fileIndex else { return false }
                switch row.kind {
                case .unifiedLine(let line):
                    return line.newLineNumber == newLineNumber && line.oldLineNumber == oldLineNumber
                case .sideBySideLine(let old, let new):
                    return new?.newLineNumber == newLineNumber && old?.oldLineNumber == oldLineNumber
                default:
                    return false
                }
            }
            if targetRowIndex == nil {
                // Line disappeared (gap context removed on collapse) — find nearest
                if let nl = newLineNumber {
                    targetRowIndex = findClosestLineRow(fileIndex: fileIndex, targetNewLine: nl)
                } else if let ol = oldLineNumber {
                    targetRowIndex = findClosestOldLineRow(fileIndex: fileIndex, targetOldLine: ol)
                }
            }
        }

        guard let rowIndex = targetRowIndex else { return }

        let rowRect = tableView.rect(ofRow: rowIndex)
        let maxY = tableView.bounds.height - scrollView.contentView.bounds.height
        let targetY = max(0, min(rowRect.origin.y - adjustedOffset, maxY))

        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func findClosestLineRow(fileIndex: Int, targetNewLine: Int) -> Int? {
        var bestIndex: Int?
        var bestDist = Int.max
        for (idx, row) in rows.enumerated() {
            guard row.fileIndex == fileIndex else { continue }
            let nl: Int?
            switch row.kind {
            case .unifiedLine(let line): nl = line.newLineNumber
            case .sideBySideLine(_, let new): nl = new?.newLineNumber
            default: continue
            }
            guard let lineNum = nl else { continue }
            let dist = abs(lineNum - targetNewLine)
            if dist < bestDist {
                bestDist = dist
                bestIndex = idx
            }
        }
        return bestIndex
    }

    private func findClosestOldLineRow(fileIndex: Int, targetOldLine: Int) -> Int? {
        var bestIndex: Int?
        var bestDist = Int.max
        for (idx, row) in rows.enumerated() {
            guard row.fileIndex == fileIndex else { continue }
            let ol: Int?
            switch row.kind {
            case .unifiedLine(let line): ol = line.oldLineNumber
            case .sideBySideLine(let old, _): ol = old?.oldLineNumber
            default: continue
            }
            guard let lineNum = ol else { continue }
            let dist = abs(lineNum - targetOldLine)
            if dist < bestDist {
                bestDist = dist
                bestIndex = idx
            }
        }
        return bestIndex
    }

    private func unifiedContentWidth() -> CGFloat {
        lastWidth - DiffMetrics.gutterWidth * 2 - DiffMetrics.prefixWidth - 4
    }

    private func sideBySideContentWidth() -> CGFloat {
        floor(lastWidth / 2) - DiffMetrics.gutterWidth - DiffMetrics.prefixWidth - 4
    }

    /// Fast check: does this line fit in one row without wrapping?
    private func fitsInSingleLine(_ content: String, contentWidth: CGFloat) -> Bool {
        CGFloat(content.count) * DiffFonts.monoCharWidth <= contentWidth
    }

    private func heightForUnifiedLine(_ line: DiffLine, row: Int) -> CGFloat {
        let contentWidth = unifiedContentWidth()
        if fitsInSingleLine(line.content, contentWidth: contentWidth) {
            return DiffMetrics.lineRowHeight
        }
        if let cached = heightCache[row] { return cached }
        let h = DiffDrawing.wrappedTextHeight(line.content, width: contentWidth, font: DiffFonts.mono)
        heightCache[row] = h
        return h
    }

    private func heightForSideBySideLine(old: DiffLine?, new: DiffLine?, row: Int) -> CGFloat {
        let contentWidth = sideBySideContentWidth()
        let oldFits = old.map { fitsInSingleLine($0.content, contentWidth: contentWidth) } ?? true
        let newFits = new.map { fitsInSingleLine($0.content, contentWidth: contentWidth) } ?? true
        if oldFits && newFits {
            return DiffMetrics.lineRowHeight
        }
        if let cached = heightCache[row] { return cached }
        let oldHeight = old.map { DiffDrawing.wrappedTextHeight($0.content, width: contentWidth, font: DiffFonts.mono) } ?? DiffMetrics.lineRowHeight
        let newHeight = new.map { DiffDrawing.wrappedTextHeight($0.content, width: contentWidth, font: DiffFonts.mono) } ?? DiffMetrics.lineRowHeight
        let h = max(oldHeight, newHeight)
        heightCache[row] = h
        return h
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
        case .unifiedLine(let line):
            lineWrapping ? heightForUnifiedLine(line, row: row) : DiffMetrics.lineRowHeight
        case .sideBySideLine(let old, let new):
            lineWrapping ? heightForSideBySideLine(old: old, new: new, row: row) : DiffMetrics.lineRowHeight
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
            cell.isExpanded = isFileExpanded(file)
            cell.onCollapse = { [weak self] in self?.toggleExpand(for: file) }
            cell.needsDisplay = true
            return cell

        case .hunkHeader(let hunk, let file):
            let id = NSUserInterfaceItemIdentifier("hunkHeader")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? HunkHeaderDrawView
                ?? HunkHeaderDrawView(identifier: id)
            cell.hunk = hunk
            cell.onExpandFile = { [weak self] in self?.toggleExpand(for: file, fromHunk: hunk) }
            cell.needsDisplay = true
            return cell

        case .unifiedLine(let line):
            let id = NSUserInterfaceItemIdentifier("unifiedLine")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? UnifiedLineDrawView
                ?? UnifiedLineDrawView(identifier: id)
            cell.line = line
            cell.lineWrapping = lineWrapping
            let selRange = selectionRange(forRow: row)
            cell.selectionStartChar = selRange?.start
            cell.selectionEndChar = selRange?.end
            cell.needsDisplay = true
            return cell

        case .sideBySideLine(let old, let new):
            let id = NSUserInterfaceItemIdentifier("sideBySideLine")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? SideBySideLineDrawView
                ?? SideBySideLineDrawView(identifier: id)
            cell.oldLine = old
            cell.newLine = new
            cell.lineWrapping = lineWrapping
            let selRange = selectionRange(forRow: row)
            cell.selectionSide = selection?.side
            cell.selectionStartChar = selRange?.start
            cell.selectionEndChar = selRange?.end
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
enum DiffFonts {
    static let mono = NSFont(name: "Source Code Pro", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let monoSmall = NSFont(name: "Source Code Pro", size: 11)
        ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let monoMedium = NSFont(name: "Source Code Pro Medium", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    /// Width of a single character in the monospace font, used for fast "will this line wrap?" checks.
    static let monoCharWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: mono]).width
    /// Height of a single line of text in the monospace font.
    static let monoLineHeight: CGFloat = ("Xg" as NSString).boundingRect(
        with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: mono]
    ).height
}

// MARK: - Draw Helpers

@MainActor
enum DiffDrawing {
    static func drawGutterText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, wrap: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let y = wrap ? rect.minY + 2 : rect.midY - size.height / 2
        // Right-align within rect with 4pt padding
        let x = rect.maxX - size.width - 4
        (text as NSString).draw(at: NSPoint(x: max(rect.minX, x), y: y), withAttributes: attrs)
    }

    static func wrappedTextHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        guard width > 0 else { return DiffMetrics.lineRowHeight }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs
        )
        // If it fits in a single line, return the standard row height
        if rect.height <= DiffFonts.monoLineHeight + 1 {
            return DiffMetrics.lineRowHeight
        }
        return ceil(rect.height)
    }

    static func drawText(
        _ text: String, in rect: NSRect, font: NSFont, color: NSColor,
        centered: Bool = false, wrap: Bool = false
    ) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        if centered {
            let y = wrap ? rect.minY + 2 : rect.midY - size.height / 2
            let x = rect.midX - size.width / 2
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        } else if wrap {
            let drawRect = NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: rect.height - 2)
            (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin], attributes: attrs)
        } else {
            let y = rect.midY - size.height / 2
            (text as NSString).draw(
                in: NSRect(x: rect.minX, y: y, width: rect.width, height: size.height),
                withAttributes: attrs
            )
        }
    }

    static func drawSelectionHighlight(
        text: String, contentRect: NSRect, startChar: Int, endChar: Int,
        font: NSFont, wrap: Bool
    ) {
        let clampedStart = max(0, startChar)
        let clampedEnd = min(text.count, endChar)
        guard clampedStart < clampedEnd else { return }

        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()

        if !wrap {
            let charWidth = DiffFonts.monoCharWidth
            let x1 = contentRect.minX + CGFloat(clampedStart) * charWidth
            let x2 = contentRect.minX + CGFloat(clampedEnd) * charWidth
            NSRect(
                x: x1, y: contentRect.minY,
                width: min(x2, contentRect.maxX) - x1, height: contentRect.height
            ).fill()
        } else {
            let storage = NSTextStorage(string: text, attributes: [.font: font])
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: contentRect.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: clampedStart, length: clampedEnd - clampedStart),
                actualCharacterRange: nil
            )
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: glyphRange,
                in: container
            ) { rect, _ in
                let highlightRect = NSRect(
                    x: contentRect.minX + rect.minX,
                    y: contentRect.minY + 2 + rect.minY,
                    width: rect.width,
                    height: rect.height
                )
                highlightRect.fill()
            }
        }
    }

    static func drawLineSide(
        line: DiffLine?, isOld: Bool, in rect: NSRect, font: NSFont, gutterFont: NSFont, wrap: Bool
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
                drawGutterText(String(num), in: gutterRect, font: gutterFont, color: DiffColors.gutterFg, wrap: wrap)
            }

            // Prefix
            drawText(DiffColors.prefix(for: line.type), in: prefixRect, font: font, color: fg, centered: true, wrap: wrap)

            // Content
            drawText(line.content, in: contentRect, font: font, color: fg, wrap: wrap)
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
    var isExpanded: Bool = false {
        didSet {
            collapseButton.isHidden = !isExpanded
            needsDisplay = true
        }
    }
    var onCollapse: (() -> Void)?
    private let collapseButton: ArrowCursorButton

    init(identifier: NSUserInterfaceItemIdentifier) {
        collapseButton = ArrowCursorButton()
        super.init(frame: .zero)
        self.identifier = identifier

        collapseButton.title = "Show diff"
        collapseButton.font = .systemFont(ofSize: 11)
        collapseButton.isBordered = false
        collapseButton.wantsLayer = true
        collapseButton.layer?.cornerRadius = 3
        collapseButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        collapseButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        collapseButton.isHidden = true
        collapseButton.target = self
        collapseButton.action = #selector(collapseTapped)
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collapseButton)
        NSLayoutConstraint.activate([
            collapseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            collapseButton.widthAnchor.constraint(equalToConstant: 66),
            collapseButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func collapseTapped() {
        onCollapse?()
    }

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
        // Right margin accounts for the floating wrap toggle button
        let rightMargin: CGFloat = 46
        let pathRect = NSRect(x: 12, y: pathY, width: bounds.width - 120 - rightMargin, height: pathSize.height)
        (file.displayPath as NSString).draw(with: pathRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: pathAttrs)

        // Stats — when expanded, also reserve space for the "Show diff" collapse button
        // (button is 66pt wide at trailingAnchor -40, so its leading edge is at -106).
        let statsRightMargin: CGFloat = isExpanded ? 114 : rightMargin
        if file.isBinary {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: DiffFonts.monoSmall,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let text = "Binary"
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: NSPoint(x: bounds.maxX - size.width - statsRightMargin, y: bounds.midY - size.height / 2),
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
            let startX = bounds.maxX - totalWidth - statsRightMargin
            let y = bounds.midY - addedSize.height / 2

            (addedStr as NSString).draw(at: NSPoint(x: startX, y: y), withAttributes: addedAttrs)
            (deletedStr as NSString).draw(at: NSPoint(x: startX + addedSize.width, y: y), withAttributes: deletedAttrs)
        }
    }
}

// MARK: - Hunk Header Cell (draw-based)

private class HunkHeaderDrawView: NSView {
    var hunk: DiffHunk?
    var onExpandFile: (() -> Void)?
    private let expandButton: ArrowCursorButton

    init(identifier: NSUserInterfaceItemIdentifier) {
        expandButton = ArrowCursorButton()
        super.init(frame: .zero)
        self.identifier = identifier

        expandButton.title = "Show file"
        expandButton.font = .systemFont(ofSize: 11)
        expandButton.isBordered = false
        expandButton.wantsLayer = true
        expandButton.layer?.cornerRadius = 3
        expandButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        expandButton.contentTintColor = DiffColors.hunkHeaderFg
        expandButton.target = self
        expandButton.action = #selector(expandTapped)
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandButton)
        NSLayoutConstraint.activate([
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            expandButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            expandButton.widthAnchor.constraint(equalToConstant: 66),
            expandButton.heightAnchor.constraint(equalToConstant: 17),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func expandTapped() {
        onExpandFile?()
    }

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

class UnifiedLineDrawView: NSView {
    var line: DiffLine?
    var lineWrapping: Bool = false
    var selectionStartChar: Int?
    var selectionEndChar: Int?

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
        let wrap = lineWrapping

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
            DiffDrawing.drawGutterText(String(num), in: oldGutterRect, font: font, color: DiffColors.gutterFg, wrap: wrap)
        }

        // New gutter background + text
        let newGutterRect = NSRect(x: gw, y: 0, width: gw, height: bounds.height)
        DiffColors.gutterBackground(for: line.type).setFill()
        newGutterRect.fill()
        if let num = line.newLineNumber {
            DiffDrawing.drawGutterText(String(num), in: newGutterRect, font: font, color: DiffColors.gutterFg, wrap: wrap)
        }

        // Prefix
        let prefixRect = NSRect(x: gw * 2, y: 0, width: pw, height: bounds.height)
        DiffDrawing.drawText(DiffColors.prefix(for: line.type), in: prefixRect, font: font, color: fg, centered: true, wrap: wrap)

        // Content
        let contentX = gw * 2 + pw
        let contentRect = NSRect(x: contentX, y: 0, width: bounds.width - contentX - 4, height: bounds.height)
        DiffDrawing.drawText(line.content, in: contentRect, font: font, color: fg, wrap: wrap)

        // Selection highlight
        if let startChar = selectionStartChar, let endChar = selectionEndChar {
            DiffDrawing.drawSelectionHighlight(
                text: line.content, contentRect: contentRect,
                startChar: startChar, endChar: endChar,
                font: font, wrap: wrap
            )
        }
    }
}

// MARK: - Side-by-Side Line Cell (draw-based)

class SideBySideLineDrawView: NSView {
    var oldLine: DiffLine?
    var newLine: DiffLine?
    var lineWrapping: Bool = false
    var selectionSide: DiffSelectionSide?
    var selectionStartChar: Int?
    var selectionEndChar: Int?

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
        DiffDrawing.drawLineSide(line: oldLine, isOld: true, in: leftRect, font: font, gutterFont: font, wrap: lineWrapping)

        // Center divider
        DiffColors.dividerColor.setFill()
        NSRect(x: half, y: 0, width: 1, height: bounds.height).fill()

        // Right side
        let rightRect = NSRect(x: half + 1, y: 0, width: bounds.width - half - 1, height: bounds.height)
        DiffDrawing.drawLineSide(line: newLine, isOld: false, in: rightRect, font: font, gutterFont: font, wrap: lineWrapping)

        // Selection highlight
        if let startChar = selectionStartChar, let endChar = selectionEndChar, let side = selectionSide {
            let gw = DiffMetrics.gutterWidth
            let pw = DiffMetrics.prefixWidth
            let text: String?
            let contentRect: NSRect

            switch side {
            case .left:
                text = oldLine?.content
                let contentX = gw + pw
                contentRect = NSRect(x: contentX, y: 0, width: half - gw - pw - 4, height: bounds.height)
            case .right:
                text = newLine?.content
                let contentX = half + 1 + gw + pw
                contentRect = NSRect(x: contentX, y: 0, width: bounds.width - half - 1 - gw - pw - 4, height: bounds.height)
            case .unified:
                text = nil
                contentRect = .zero
            }

            if let text, !contentRect.isEmpty {
                DiffDrawing.drawSelectionHighlight(
                    text: text, contentRect: contentRect,
                    startChar: startChar, endChar: endChar,
                    font: font, wrap: lineWrapping
                )
            }
        }
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
