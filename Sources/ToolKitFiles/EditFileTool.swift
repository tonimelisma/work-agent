import Foundation
import FoundationModels

// REQ: FR-079 — edit_file: exact-match string replacement, read-before-edit
// enforced. Chosen over Codex's apply_patch because patch-fluency is
// GPT-training-specific; exact-string-replace is model-agnostic (tool-architecture.md §3).
@Generable
public struct EditFileArguments: Sendable {
    @Guide(description: "Absolute path, or relative to the tool's working directory")
    public var path: String
    @Guide(description: "The exact text to replace")
    public var oldString: String
    @Guide(description: "The text to replace it with")
    public var newString: String
    @Guide(description: "Replace every occurrence instead of requiring a unique match")
    public var replaceAll: Bool?

    public init(path: String, oldString: String, newString: String, replaceAll: Bool? = nil) {
        self.path = path
        self.oldString = oldString
        self.newString = newString
        self.replaceAll = replaceAll
    }
}

public struct EditFileTool: Tool, Sendable {
    public let name = "edit_file"
    public let description = """
    Replace exact text in a file that's already been read this conversation. The \
    old text must match exactly once unless replace_all is set — an ambiguous or \
    missing match fails with a message telling you how to fix the call.
    """

    private let root: URL
    private let ledger: FileReadLedger

    public init(root: URL, ledger: FileReadLedger) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.ledger = ledger
    }

    public func call(arguments: EditFileArguments) async throws -> String {
        let url = FileToolPath.resolve(arguments.path, root: root)
        guard await ledger.hasRead(url.path) else {
            throw FileToolError.notReadBeforeWrite(path: arguments.path)
        }
        guard let data = FileManager.default.contents(atPath: url.path),
              let content = String(data: data, encoding: .utf8) else {
            throw FileToolError.notFound(path: arguments.path)
        }

        let occurrences = content.components(separatedBy: arguments.oldString).count - 1
        guard occurrences > 0 else {
            throw FileToolError.noMatch(path: arguments.path)
        }
        if occurrences > 1, arguments.replaceAll != true {
            throw FileToolError.ambiguousMatch(path: arguments.path, count: occurrences)
        }

        let replaceAll = arguments.replaceAll ?? false
        let updated: String
        if replaceAll {
            updated = content.replacingOccurrences(of: arguments.oldString, with: arguments.newString)
        } else if let range = content.range(of: arguments.oldString) {
            updated = content.replacingCharacters(in: range, with: arguments.newString)
        } else {
            updated = content
        }

        try Data(updated.utf8).write(to: url, options: .atomic)
        return "Replaced \(occurrences) occurrence\(occurrences == 1 ? "" : "s") in \(arguments.path)"
    }
}
