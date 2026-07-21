import Foundation
import Testing
@testable import ToolKitFiles

// REQ: FR-078, FR-079 — write_file and edit_file, including the read-before-write rule.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("write_file creates a new file, no read required")
func writeCreatesNewFile() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = WriteFileTool(root: root, ledger: FileReadLedger())
    let result = try await tool.call(arguments: .init(path: "new.txt", content: "hello"))
    #expect(result.contains("Created"))
    #expect(try String(contentsOf: root.appendingPathComponent("new.txt"), encoding: .utf8) == "hello")
}

@Test("write_file rejects overwriting a file that hasn't been read")
func writeRejectsBlindOverwrite() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("existing.txt")
    try "old".write(to: path, atomically: true, encoding: .utf8)

    let tool = WriteFileTool(root: root, ledger: FileReadLedger())
    await #expect(throws: FileToolError.notReadBeforeWrite(path: "existing.txt")) {
        _ = try await tool.call(arguments: .init(path: "existing.txt", content: "new"))
    }
}

@Test("write_file allows overwriting a file that was read first")
func writeAllowsOverwriteAfterRead() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("existing.txt")
    try "old".write(to: path, atomically: true, encoding: .utf8)

    let ledger = FileReadLedger()
    _ = try await ReadFileTool(root: root, ledger: ledger).call(arguments: .init(path: "existing.txt"))
    let result = try await WriteFileTool(root: root, ledger: ledger)
        .call(arguments: .init(path: "existing.txt", content: "new"))
    #expect(result.contains("Replaced"))
    #expect(try String(contentsOf: path, encoding: .utf8) == "new")
}

@Test("edit_file requires the file to have been read first")
func editRequiresRead() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "hello world".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = EditFileTool(root: root, ledger: FileReadLedger())
    await #expect(throws: FileToolError.notReadBeforeWrite(path: "a.txt")) {
        _ = try await tool.call(arguments: .init(path: "a.txt", oldString: "hello", newString: "hi"))
    }
}

@Test("edit_file replaces a unique match")
func editReplacesUniqueMatch() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("a.txt")
    try "hello world".write(to: path, atomically: true, encoding: .utf8)

    let ledger = FileReadLedger()
    _ = try await ReadFileTool(root: root, ledger: ledger).call(arguments: .init(path: "a.txt"))
    _ = try await EditFileTool(root: root, ledger: ledger)
        .call(arguments: .init(path: "a.txt", oldString: "hello", newString: "goodbye"))
    #expect(try String(contentsOf: path, encoding: .utf8) == "goodbye world")
}

@Test("edit_file rejects an ambiguous match unless replace_all is set")
func editRejectsAmbiguousMatch() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("a.txt")
    try "cat cat cat".write(to: path, atomically: true, encoding: .utf8)

    let ledger = FileReadLedger()
    _ = try await ReadFileTool(root: root, ledger: ledger).call(arguments: .init(path: "a.txt"))
    let tool = EditFileTool(root: root, ledger: ledger)
    await #expect(throws: FileToolError.ambiguousMatch(path: "a.txt", count: 3)) {
        _ = try await tool.call(arguments: .init(path: "a.txt", oldString: "cat", newString: "dog"))
    }

    _ = try await tool.call(arguments: .init(path: "a.txt", oldString: "cat", newString: "dog", replaceAll: true))
    #expect(try String(contentsOf: path, encoding: .utf8) == "dog dog dog")
}

@Test("edit_file reports a clean error when the text isn't found")
func editRejectsNoMatch() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("a.txt")
    try "hello world".write(to: path, atomically: true, encoding: .utf8)

    let ledger = FileReadLedger()
    _ = try await ReadFileTool(root: root, ledger: ledger).call(arguments: .init(path: "a.txt"))
    let tool = EditFileTool(root: root, ledger: ledger)
    await #expect(throws: FileToolError.noMatch(path: "a.txt")) {
        _ = try await tool.call(arguments: .init(path: "a.txt", oldString: "nope", newString: "x"))
    }
}
