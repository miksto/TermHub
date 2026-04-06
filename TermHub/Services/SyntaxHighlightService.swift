import AppKit
import Highlightr

// MARK: - Syntax Highlight Service

@MainActor
enum SyntaxHighlightService {
    private static let highlightr: Highlightr? = {
        guard let h = Highlightr() else { return nil }
        h.setTheme(to: "atom-one-dark")
        return h
    }()

    /// Maximum number of lines to highlight. Files larger than this fall back to plain text.
    static let maxLineCount = 10_000

    /// Highlights an array of source lines and returns per-line attributed strings.
    /// Returns `nil` if highlighting is unavailable or the language is unknown.
    static func highlight(
        lines: [String],
        language: String?,
        font: NSFont
    ) -> [NSAttributedString]? {
        guard let highlightr, let language, !lines.isEmpty else { return nil }
        guard lines.count <= maxLineCount else { return nil }

        let joined = lines.joined(separator: "\n")
        guard let highlighted = highlightr.highlight(joined, as: language, fastRender: true) else {
            return nil
        }

        // Override the font to match the diff view's monospace font
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            mutable.addAttribute(.font, value: font, range: range)
        }

        return splitAttributedString(mutable, lineCount: lines.count)
    }

    /// Splits a multi-line attributed string into per-line attributed strings.
    private static func splitAttributedString(_ attrStr: NSAttributedString, lineCount: Int) -> [NSAttributedString] {
        let full = attrStr.string as NSString
        var result: [NSAttributedString] = []
        var searchStart = 0

        for i in 0..<lineCount {
            let lineEnd: Int
            if i == lineCount - 1 {
                lineEnd = full.length
            } else {
                let newlineRange = full.range(of: "\n", options: [], range: NSRange(location: searchStart, length: full.length - searchStart))
                lineEnd = newlineRange.location != NSNotFound ? newlineRange.location : full.length
            }

            let range = NSRange(location: searchStart, length: lineEnd - searchStart)
            result.append(attrStr.attributedSubstring(from: range))
            searchStart = lineEnd + 1 // skip the newline
        }

        return result
    }

    /// Maps a file extension to a Highlightr language identifier.
    static func language(forExtension ext: String) -> String? {
        let map: [String: String] = [
            // Common languages
            "swift": "swift",
            "rs": "rust",
            "go": "go",
            "py": "python",
            "rb": "ruby",
            "js": "javascript",
            "jsx": "javascript",
            "ts": "typescript",
            "tsx": "typescript",
            "java": "java",
            "kt": "kotlin",
            "kts": "kotlin",
            "c": "c",
            "h": "c",
            "cpp": "cpp",
            "cc": "cpp",
            "cxx": "cpp",
            "hpp": "cpp",
            "hh": "cpp",
            "m": "objectivec",
            "mm": "objectivec",
            "cs": "csharp",

            // Web
            "html": "xml",
            "htm": "xml",
            "xml": "xml",
            "css": "css",
            "scss": "scss",
            "less": "less",
            "json": "json",
            "vue": "xml",
            "svelte": "xml",

            // Shell / Config
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash",
            "fish": "fish",
            "yml": "yaml",
            "yaml": "yaml",
            "toml": "ini",
            "ini": "ini",
            "conf": "ini",
            "env": "bash",

            // Data / Docs
            "md": "markdown",
            "markdown": "markdown",
            "sql": "sql",
            "graphql": "graphql",
            "gql": "graphql",
            "proto": "protobuf",

            // Other
            "r": "r",
            "lua": "lua",
            "pl": "perl",
            "pm": "perl",
            "php": "php",
            "ex": "elixir",
            "exs": "elixir",
            "erl": "erlang",
            "hs": "haskell",
            "scala": "scala",
            "clj": "clojure",
            "dart": "dart",
            "dockerfile": "dockerfile",
            "tf": "hcl",
            "cmake": "cmake",
            "makefile": "makefile",
            "mk": "makefile",
            "gradle": "gradle",
            "groovy": "groovy",
            "diff": "diff",
            "patch": "diff",
        ]
        return map[ext.lowercased()]
    }

    /// Extracts the file extension from a path, with special handling for dotfiles.
    static func language(forPath path: String) -> String? {
        let filename = (path as NSString).lastPathComponent.lowercased()

        // Special filenames
        switch filename {
        case "dockerfile": return "dockerfile"
        case "makefile", "gnumakefile": return "makefile"
        case "cmakelists.txt": return "cmake"
        case "podfile", "gemfile", "rakefile", "fastfile", "appfile", "matchfile":
            return "ruby"
        case "package.json", "tsconfig.json", "jsconfig.json":
            return "json"
        default: break
        }

        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return language(forExtension: ext)
    }
}

// MARK: - Highlight Cache

@MainActor
final class SyntaxHighlightCache {
    struct CacheKey: Hashable {
        let filePath: String
        let contentHash: Int
    }

    struct CacheEntry {
        let oldLines: [NSAttributedString]?
        let newLines: [NSAttributedString]?
    }

    private var cache: [CacheKey: CacheEntry] = [:]

    func get(filePath: String, contentHash: Int) -> CacheEntry? {
        cache[CacheKey(filePath: filePath, contentHash: contentHash)]
    }

    func set(filePath: String, contentHash: Int, entry: CacheEntry) {
        cache[CacheKey(filePath: filePath, contentHash: contentHash)] = entry
    }

    func clear() {
        cache.removeAll()
    }
}
