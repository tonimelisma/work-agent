import Foundation
import FoundationModels

// REQ: FR-075 — list_folder: directory entries, optionally recursive (depth-capped).
@Generable
public struct ListFolderArguments: Sendable {
    @Guide(description: "Absolute path, or relative to the tool's working directory")
    public var path: String
    @Guide(description: "List subdirectories too, to a maximum depth of 3")
    public var recursive: Bool?

    public init(path: String, recursive: Bool? = nil) {
        self.path = path
        self.recursive = recursive
    }
}

public struct ListFolderTool: Tool, Sendable {
    public let name = "list_folder"
    public let description = """
    List a directory's entries: name, kind, size, and modified date. Hidden entries \
    are skipped by default. Capped at 300 entries; narrow with find_files if truncated.
    """

    private let root: URL
    private let maximumDepth: Int
    private let maximumEntries: Int

    public init(root: URL, maximumDepth: Int = 3, maximumEntries: Int = 300) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
    }

    public func call(arguments: ListFolderArguments) async throws -> String {
        let url = FileToolPath.resolve(arguments.path, root: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileToolError.notFound(path: arguments.path)
        }

        var entries: [(name: String, isDirectory: Bool, size: Int, modified: Date)] = []
        try collect(url, depth: 0, recursive: arguments.recursive ?? false, into: &entries)

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.modified > rhs.modified
        }

        let truncated = entries.count > maximumEntries
        let shown = entries.prefix(maximumEntries)
        let formatter = ISO8601DateFormatter()
        let lines = shown.map { entry in
            let kind = entry.isDirectory ? "dir" : "file"
            return "\(kind)\t\(entry.size)\t\(formatter.string(from: entry.modified))\t\(entry.name)"
        }.joined(separator: "\n")

        if truncated {
            return lines + "\n\n[Showing \(maximumEntries) of \(entries.count) entries. " +
                "Narrow with find_files.]"
        }
        return lines.isEmpty ? "[Empty directory]" : lines
    }

    private func collect(
        _ directory: URL, depth: Int, recursive: Bool,
        into entries: inout [(name: String, isDirectory: Bool, size: Int, modified: Date)]
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            ])
            let isDirectory = values.isDirectory ?? false
            let relativeName = FileToolPath.relative(url, to: root)
            entries.append((
                name: relativeName,
                isDirectory: isDirectory,
                size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            ))
            if recursive, isDirectory, depth + 1 <= maximumDepth {
                try collect(url, depth: depth + 1, recursive: recursive, into: &entries)
            }
        }
    }
}
