import Foundation
import FoundationModels

// REQ: FR-077 — search_files: content grep, native Swift, no bundled binary
// ("I generally prefer native Swift", then "do it" — tool-architecture.md §6).
@Generable
public struct SearchFilesArguments: Sendable {
    @Guide(description: "Regular expression to search for")
    public var pattern: String
    @Guide(description: "Root to search under; defaults to the tool's working directory")
    public var path: String?
    @Guide(description: "Only search files matching this glob, e.g. *.md")
    public var glob: String?
    @Guide(description: "files_with_matches (default), content, or count")
    public var mode: String?

    public init(pattern: String, path: String? = nil, glob: String? = nil, mode: String? = nil) {
        self.pattern = pattern
        self.path = path
        self.glob = glob
        self.mode = mode
    }
}

public struct SearchFilesTool: Tool, Sendable {
    public let name = "search_files"
    public let description = """
    Search file contents by regular expression. mode: files_with_matches (default, \
    just paths), content (file:line and the matching line), or count. Stops at 100 \
    matches. Skips files larger than 2 MB or that aren't text.
    """

    private let root: URL
    private let maximumMatches: Int
    private let maximumFileSize: Int

    public init(root: URL, maximumMatches: Int = 100, maximumFileSize: Int = 2_000_000) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.maximumMatches = maximumMatches
        self.maximumFileSize = maximumFileSize
    }

    public func call(arguments: SearchFilesArguments) async throws -> String {
        guard let regex = try? NSRegularExpression(pattern: arguments.pattern) else {
            throw FileToolError.invalidArguments("'\(arguments.pattern)' isn't a valid regular expression.")
        }
        let searchRoot = arguments.path.map { FileToolPath.resolve($0, root: root) } ?? root
        let mode = arguments.mode ?? "files_with_matches"

        guard let enumerator = FileManager.default.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FileToolError.notFound(path: arguments.path ?? ".")
        }

        var filesWithMatches: [String] = []
        var contentLines: [String] = []
        var matchCount = 0

        outer: while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory != true else { continue }
            guard (values.fileSize ?? 0) <= maximumFileSize else { continue }
            let relativePath = FileToolPath.relative(url, to: searchRoot)
            if let glob = arguments.glob, !GlobMatcher.matches(pattern: glob, path: relativePath) { continue }
            guard let data = FileManager.default.contents(atPath: url.path),
                  let text = String(data: data, encoding: .utf8) else { continue }

            var fileMatched = false
            for (lineNumber, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex ..< line.endIndex, in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { continue }
                fileMatched = true
                matchCount += 1
                if mode == "content" {
                    contentLines.append("\(relativePath):\(lineNumber + 1): \(line)")
                }
                if matchCount >= maximumMatches { break outer }
            }
            if fileMatched { filesWithMatches.append(relativePath) }
        }

        switch mode {
        case "count":
            return "\(matchCount) match\(matchCount == 1 ? "" : "es") across \(filesWithMatches.count) file(s)"
        case "content":
            return contentLines.isEmpty ? "[No matches]" : contentLines.joined(separator: "\n")
        default:
            return filesWithMatches.isEmpty ? "[No matches]" : filesWithMatches.joined(separator: "\n")
        }
    }
}
