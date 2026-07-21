import Foundation
import Testing
@testable import ToolKitFiles

// REQ: FR-077 — search_files, native regex grep.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("files_with_matches returns just the matching paths")
func filesWithMatchesMode() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "hello world".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "goodbye".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

    let tool = SearchFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "hello"))
    #expect(output.contains("a.txt"))
    #expect(!output.contains("b.txt"))
}

@Test("content mode returns file:line and the matching line")
func contentMode() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "one\nhello there\nthree".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = SearchFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "hello", mode: "content"))
    #expect(output.contains("a.txt:2: hello there"))
}

@Test("count mode reports totals, not matched lines")
func countMode() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "cat\ncat\ndog".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = SearchFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "cat", mode: "count"))
    #expect(output == "2 matches across 1 file(s)")
}

@Test("An invalid regex fails with a precise message")
func invalidRegex() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = SearchFilesTool(root: root)
    await #expect(throws: FileToolError.invalidArguments("'(' isn't a valid regular expression.")) {
        _ = try await tool.call(arguments: .init(pattern: "("))
    }
}

@Test("glob narrows the search to matching file names")
func globFilter() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "match".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
    try "match".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = SearchFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "match", glob: "*.md"))
    #expect(output == "a.md")
}
