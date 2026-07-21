import Foundation
import Testing
@testable import ToolKitFiles

// REQ: FR-075 — list_folder.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("Lists files and directories, directories first")
func listsEntries() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "x".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)

    let tool = ListFolderTool(root: root)
    let output = try await tool.call(arguments: .init(path: "."))
    let lines = output.components(separatedBy: "\n")
    #expect(lines.first?.hasPrefix("dir") == true)
    #expect(output.contains("file.txt"))
}

@Test("recursive lists nested entries up to the depth cap")
func recursiveListing() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("a/b/c", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try "x".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

    let tool = ListFolderTool(root: root)
    let output = try await tool.call(arguments: .init(path: ".", recursive: true))
    #expect(output.contains("deep.txt"))
}

@Test("A missing directory throws FileToolError.notFound")
func missingDirectory() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = ListFolderTool(root: root)
    await #expect(throws: FileToolError.notFound(path: "nope")) {
        _ = try await tool.call(arguments: .init(path: "nope"))
    }
}

@Test("An empty directory reads as an explicit notice")
func emptyDirectory() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = ListFolderTool(root: root)
    let output = try await tool.call(arguments: .init(path: "."))
    #expect(output == "[Empty directory]")
}
