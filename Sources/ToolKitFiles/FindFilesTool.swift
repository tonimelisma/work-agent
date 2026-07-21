import Foundation
import FoundationModels

// REQ: FR-076 — find_files: glob-match paths under a root. No gitignore semantics —
// meaningless for document folders (tool-architecture.md §3).
@Generable
public struct FindFilesArguments: Sendable {
    @Guide(description: "Glob pattern, e.g. **/*.docx")
    public var pattern: String
    @Guide(description: "Root to search under; defaults to the tool's working directory")
    public var path: String?

    public init(pattern: String, path: String? = nil) {
        self.pattern = pattern
        self.path = path
    }
}

public struct FindFilesTool: Tool, Sendable {
    public let name = "find_files"
    public let description = "Find files by glob pattern (e.g. **/*.docx). Capped at 100 matches, sorted by most recently modified."

    private let root: URL
    private let maximumMatches: Int

    public init(root: URL, maximumMatches: Int = 100) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.maximumMatches = maximumMatches
    }

    public func call(arguments: FindFilesArguments) async throws -> String {
        let searchRoot = arguments.path.map { FileToolPath.resolve($0, root: root) } ?? root
        guard let enumerator = FileManager.default.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FileToolError.notFound(path: arguments.path ?? ".")
        }

        var matches: [(path: String, modified: Date)] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values.isDirectory != true else { continue }
            let relativePath = FileToolPath.relative(url, to: searchRoot)
            guard GlobMatcher.matches(pattern: arguments.pattern, path: relativePath) else { continue }
            matches.append((relativePath, values.contentModificationDate ?? .distantPast))
        }

        matches.sort { $0.modified > $1.modified }
        let truncated = matches.count > maximumMatches
        let shown = matches.prefix(maximumMatches).map(\.path).joined(separator: "\n")

        if truncated {
            return shown + "\n\n[Showing \(maximumMatches) of \(matches.count) matches.]"
        }
        return shown.isEmpty ? "[No matches]" : shown
    }
}

/// A small glob matcher: `*` (any run within a segment), `**` (any run across
/// segments), `?` (one character). No dependency — about 30 lines.
enum GlobMatcher {
    static func matches(pattern: String, path: String) -> Bool {
        let regexPattern = translate(pattern)
        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else { return false }
        let range = NSRange(path.startIndex ..< path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private static func translate(_ pattern: String) -> String {
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let char = pattern[index]
            if char == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    let afterDoubleStar = pattern.index(after: next)
                    if afterDoubleStar < pattern.endIndex, pattern[afterDoubleStar] == "/" {
                        // "**/" matches zero or more whole path segments, including
                        // none — so "**/*.docx" also matches a top-level "top.docx".
                        result += "(?:.*/)?"
                        index = pattern.index(after: afterDoubleStar)
                        continue
                    }
                    result += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                result += "[^/]*"
            } else if char == "?" {
                result += "[^/]"
            } else if ".\\^$|()[]{}+".contains(char) {
                result += "\\\(char)"
            } else {
                result.append(char)
            }
            index = pattern.index(after: index)
        }
        return result
    }
}
