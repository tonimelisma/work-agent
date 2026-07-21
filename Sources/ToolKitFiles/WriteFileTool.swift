import Foundation
import FoundationModels

// REQ: FR-078 — write_file: create or atomically replace a file's contents.
@Generable
public struct WriteFileArguments: Sendable {
    @Guide(description: "Absolute path, or relative to the tool's working directory")
    public var path: String
    @Guide(description: "The full content to write")
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct WriteFileTool: Tool, Sendable {
    public let name = "write_file"
    public let description = """
    Create a file, or atomically replace one that was already read this \
    conversation. Overwriting a file that hasn't been read is rejected — read it \
    first so the change is never blind. Intermediate directories are created as needed.
    """

    private let root: URL
    private let ledger: FileReadLedger

    public init(root: URL, ledger: FileReadLedger) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.ledger = ledger
    }

    public func call(arguments: WriteFileArguments) async throws -> String {
        let url = FileToolPath.resolve(arguments.path, root: root)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists {
            guard await ledger.hasRead(url.path) else {
                throw FileToolError.notReadBeforeWrite(path: arguments.path)
            }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(arguments.content.utf8).write(to: url, options: .atomic)
        await ledger.markRead(url.path)
        return exists ? "Replaced \(arguments.path) (\(arguments.content.count) characters)"
            : "Created \(arguments.path) (\(arguments.content.count) characters)"
    }
}
