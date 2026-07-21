import Foundation

// REQ: tool-architecture.md §3 — "We don't have folders. Permissions come later."
// There is no folder-grant model: tools take ordinary paths, canonicalized, with a
// per-task working directory as the relative-path base. The trace is the
// accountability mechanism until the permissions increment exists — not a sandbox
// enforced here.

public enum FileToolError: LocalizedError, Equatable, Sendable {
    case notFound(path: String)
    case notReadBeforeWrite(path: String)
    case ambiguousMatch(path: String, count: Int)
    case noMatch(path: String)
    case unsupportedFormat(String)
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(path):
            "No such file: \(path)"
        case let .notReadBeforeWrite(path):
            "Read \(path) before editing it, so changes are never blind."
        case let .ambiguousMatch(path, count):
            "The text to replace appears \(count) times in \(path); include more " +
                "surrounding context to make it unique, or pass replace_all."
        case let .noMatch(path):
            "The text to replace was not found in \(path)."
        case let .unsupportedFormat(ext):
            "Reading .\(ext) files isn't supported yet."
        case let .invalidArguments(message):
            message
        }
    }
}

public enum FileToolPath {
    /// Resolves `path` against `root` when relative; an absolute path is used as
    /// given (canonicalized) — there is no sandbox to escape here, by design.
    public static func resolve(_ path: String, root: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// A path relative to `root`, computed via path components rather than string
    /// prefix stripping — robust to enumerators that return paths through a
    /// slightly different (but equivalent) symlink resolution than `root` itself.
    public static func relative(_ url: URL, to root: URL) -> String {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let urlComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.path
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}

/// Which paths this conversation has read — the precondition for `edit_file`'s
/// read-before-write rule (tool-architecture.md §3, Claude Code's contract).
public actor FileReadLedger {
    private var readPaths: Set<String> = []

    public init() {}

    public func markRead(_ path: String) {
        readPaths.insert(path)
    }

    public func hasRead(_ path: String) -> Bool {
        readPaths.contains(path)
    }
}

enum FileKind {
    case text, pdf, docx, image
    case unsupported(String)

    static func of(_ url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "docx": .docx
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp": .image
        case "xlsx", "pptx", "doc", "xls", "ppt": .unsupported(url.pathExtension.lowercased())
        default: .text
        }
    }
}

/// Token budgeting, applied uniformly by every file tool (tool-architecture.md §2's
/// runner budgets, reapplied per-tool here since ToolKit doesn't depend on Recorder).
enum OutputBudget {
    static func truncate(_ text: String, maximumCharacters: Int, recoveryHint: String) -> String {
        guard text.count > maximumCharacters else { return text }
        let prefix = String(text.prefix(maximumCharacters))
        return "\(prefix)\n\n[Output truncated at \(maximumCharacters) characters. \(recoveryHint)]"
    }
}
