import Foundation
import Testing
@testable import ToolKitFiles

// REQ: FR-076 — find_files glob matching.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("** matches across nested directories")
func doubleStarMatchesNested() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("a/b", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try "x".write(to: nested.appendingPathComponent("report.docx"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent("top.docx"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)

    let tool = FindFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "**/*.docx"))
    #expect(output.contains("a/b/report.docx"))
    #expect(output.contains("top.docx"))
    #expect(!output.contains("other.txt"))
}

@Test("A pattern with no matches reads as an explicit notice")
func noMatches() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = FindFilesTool(root: root)
    let output = try await tool.call(arguments: .init(pattern: "*.nonexistent"))
    #expect(output == "[No matches]")
}

@Test("GlobMatcher: single * does not cross a path separator")
func singleStarStaysWithinSegment() {
    #expect(GlobMatcher.matches(pattern: "*.txt", path: "a.txt"))
    #expect(!GlobMatcher.matches(pattern: "*.txt", path: "sub/a.txt"))
    #expect(GlobMatcher.matches(pattern: "**/*.txt", path: "sub/a.txt"))
}
