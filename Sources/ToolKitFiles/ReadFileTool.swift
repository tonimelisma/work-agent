import Foundation
import FoundationModels
import PDFKit
import ZIPFoundation

// REQ: FR-074 — read_file: text (paged), PDF, and docx content from a path.
// Image support is deliberately not in this increment (would need a multi-modal
// Tool.Output type); .xlsx/.pptx stay an honest "not yet" error.
@Generable
public struct ReadFileArguments: Sendable {
    @Guide(description: "Absolute path, or relative to the tool's working directory")
    public var path: String
    @Guide(description: "1-based line to start from (text files only)")
    public var offset: Int?
    @Guide(description: "Maximum number of lines to return (text files only, default 2000)")
    public var limit: Int?

    public init(path: String, offset: Int? = nil, limit: Int? = nil) {
        self.path = path
        self.offset = offset
        self.limit = limit
    }
}

public struct ReadFileTool: Tool, Sendable {
    public let name = "read_file"
    public let description = """
    Read a file's content. Text files return cat -n style numbered lines, paged via \
    offset/limit (2,000 lines and 2,000 characters/line by default; a partial view \
    says so and how to continue). PDFs return full text if 10 pages or fewer, else \
    require a page range. .docx returns paragraph text with headings and tables as \
    markdown. .xlsx and .pptx are not supported yet.
    """

    private let root: URL
    private let ledger: FileReadLedger
    private let maximumLines: Int
    private let maximumLineCharacters: Int
    private let maximumOutputCharacters: Int

    public init(
        root: URL,
        ledger: FileReadLedger,
        maximumLines: Int = 2_000,
        maximumLineCharacters: Int = 2_000,
        maximumOutputCharacters: Int = 16_000
    ) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.ledger = ledger
        self.maximumLines = maximumLines
        self.maximumLineCharacters = maximumLineCharacters
        self.maximumOutputCharacters = maximumOutputCharacters
    }

    public func call(arguments: ReadFileArguments) async throws -> String {
        let url = FileToolPath.resolve(arguments.path, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileToolError.notFound(path: arguments.path)
        }
        await ledger.markRead(url.path)

        let output: String
        switch FileKind.of(url) {
        case .text:
            output = try readText(url: url, offset: arguments.offset, limit: arguments.limit)
        case .pdf:
            output = try readPDF(url: url)
        case .docx:
            output = try readDocx(url: url)
        case .image:
            throw FileToolError.unsupportedFormat("image (vision) — not in this increment")
        case let .unsupported(ext):
            throw FileToolError.unsupportedFormat(ext)
        }
        return OutputBudget.truncate(
            output, maximumCharacters: maximumOutputCharacters,
            recoveryHint: "Narrow with offset/limit or a page range."
        )
    }

    private func readText(url: URL, offset: Int?, limit: Int?) throws -> String {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw FileToolError.notFound(path: url.path)
        }
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw FileToolError.unsupportedFormat("binary")
        }
        if content.isEmpty { return "[Empty file]" }

        let allLines = content.components(separatedBy: .newlines)
        let start = max(0, (offset ?? 1) - 1)
        guard start < allLines.count else {
            return "[Offset \(offset ?? 1) is past the end of the file (\(allLines.count) lines)]"
        }
        let end = min(allLines.count, start + (limit ?? maximumLines))
        let slice = allLines[start ..< end]

        let numbered = slice.enumerated().map { index, line -> String in
            let lineNumber = start + index + 1
            let truncatedLine = line.count > maximumLineCharacters
                ? String(line.prefix(maximumLineCharacters)) + " [line truncated]"
                : line
            return "\(lineNumber)\t\(truncatedLine)"
        }.joined(separator: "\n")

        if end < allLines.count {
            return numbered + "\n\n[PARTIAL view: showing lines \(start + 1)–\(end) of " +
                "\(allLines.count). Use offset/limit to continue.]"
        }
        return numbered
    }

    private func readPDF(url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw FileToolError.notFound(path: url.path)
        }
        guard document.pageCount <= 10 else {
            throw FileToolError.invalidArguments(
                "This PDF has \(document.pageCount) pages; reading more than 10 at once " +
                    "isn't supported yet. (Page ranges are a future increment.)"
            )
        }
        var text = ""
        for index in 0 ..< document.pageCount {
            if let page = document.page(at: index) {
                text += (page.string ?? "") + "\n"
            }
        }
        return text
    }

    private func readDocx(url: URL) throws -> String {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil),
              let entry = archive["word/document.xml"] else {
            throw FileToolError.invalidArguments("Couldn't open \(url.lastPathComponent) as a .docx (zip) container.")
        }
        var xmlData = Data()
        _ = try archive.extract(entry) { data in xmlData.append(data) }
        return try DocxTextExtractor.text(fromDocumentXML: xmlData)
    }
}
