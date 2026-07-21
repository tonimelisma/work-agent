import Foundation
import Testing
import ZIPFoundation
@testable import ToolKitFiles

// REQ: FR-074 — read_file across text, paging, PDF, and docx.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("A plain text file reads back with cat -n style line numbers")
func readsTextWithLineNumbers() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "first\nsecond\nthird".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    let output = try await tool.call(arguments: .init(path: "a.txt"))
    #expect(output == "1\tfirst\n2\tsecond\n3\tthird")
}

@Test("offset/limit page a file and note there's more")
func pagesLargeFile() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let lines = (1 ... 50).map { "line \($0)" }.joined(separator: "\n")
    try lines.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    let output = try await tool.call(arguments: .init(path: "big.txt", offset: 10, limit: 5))
    #expect(output.contains("10\tline 10"))
    #expect(output.contains("14\tline 14"))
    #expect(!output.contains("15\tline 15"))
    #expect(output.contains("PARTIAL view"))
}

@Test("An offset past the end of the file is a clean notice, not an error")
func offsetPastEndOfFile() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "one\ntwo".write(to: root.appendingPathComponent("short.txt"), atomically: true, encoding: .utf8)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    let output = try await tool.call(arguments: .init(path: "short.txt", offset: 100))
    #expect(output.contains("past the end"))
}

@Test("An empty file reads as an explicit notice")
func emptyFile() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "".write(to: root.appendingPathComponent("empty.txt"), atomically: true, encoding: .utf8)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    let output = try await tool.call(arguments: .init(path: "empty.txt"))
    #expect(output == "[Empty file]")
}

@Test("A missing file throws FileToolError.notFound")
func missingFile() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    await #expect(throws: FileToolError.notFound(path: "missing.txt")) {
        _ = try await tool.call(arguments: .init(path: "missing.txt"))
    }
}

@Test("Reading marks the path in the ledger, satisfying edit_file's read-before-write rule")
func readingMarksLedger() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("a.txt")
    try "content".write(to: path, atomically: true, encoding: .utf8)

    let ledger = FileReadLedger()
    let tool = ReadFileTool(root: root, ledger: ledger)
    _ = try await tool.call(arguments: .init(path: "a.txt"))
    #expect(await ledger.hasRead(path.standardizedFileURL.resolvingSymlinksInPath().path))
}

@Test("A .docx reads as paragraph text with headings and a table")
func readsDocxWithHeadingsAndTable() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let docxURL = root.appendingPathComponent("doc.docx")
    try DocxFixture.write(to: docxURL)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    let output = try await tool.call(arguments: .init(path: "doc.docx"))
    #expect(output.contains("# Report"))
    #expect(output.contains("Body paragraph."))
    #expect(output.contains("| A | B |"))
}

@Test(".xlsx is an honest not-yet-supported error, not a silent failure")
func xlsxIsUnsupported() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("sheet.xlsx"))

    let tool = ReadFileTool(root: root, ledger: FileReadLedger())
    await #expect(throws: FileToolError.unsupportedFormat("xlsx")) {
        _ = try await tool.call(arguments: .init(path: "sheet.xlsx"))
    }
}

/// Builds a minimal, real .docx (a zip container) in-memory for tests, so we don't
/// need to commit a binary fixture or depend on Word having produced one.
enum DocxFixture {
    static func write(to url: URL) throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Report</w:t></w:r></w:p>
        <w:p><w:r><w:t>Body paragraph.</w:t></w:r></w:p>
        <w:tbl>
        <w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>
        <w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl>
        </w:body>
        </w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        try archive.addEntry(
            with: "[Content_Types].xml", type: .file, uncompressedSize: Int64(contentTypes.utf8.count),
            provider: { position, size in Data(contentTypes.utf8)[Int(position) ..< Int(position) + size] }
        )
        try archive.addEntry(
            with: "word/document.xml", type: .file, uncompressedSize: Int64(documentXML.utf8.count),
            provider: { position, size in Data(documentXML.utf8)[Int(position) ..< Int(position) + size] }
        )
    }
}
