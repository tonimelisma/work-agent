import Foundation

// REQ: FR-074 — .docx → text: unzip the OOXML container, parse word/document.xml,
// emit paragraph text with headings by style id and tables as markdown rows.
enum DocxTextExtractor {
    static func text(fromDocumentXML data: Data) throws -> String {
        let delegate = DocumentXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw FileToolError.invalidArguments("Couldn't parse this .docx's document.xml.")
        }
        return delegate.output
    }
}

private final class DocumentXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var output = ""

    private var currentText = ""
    private var isCapturingText = false
    private var currentParagraphStyle: String?
    private var currentParagraphText = ""
    private var inTableCell = false
    private var currentRowCells: [String] = []
    private var tableRowsEmitted = 0

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "w:t":
            isCapturingText = true
            currentText = ""
        case "w:pStyle":
            currentParagraphStyle = attributeDict["w:val"]
        case "w:p":
            currentParagraphText = ""
            currentParagraphStyle = nil
        case "w:tbl":
            tableRowsEmitted = 0
        case "w:tr":
            currentRowCells = []
        case "w:tc":
            inTableCell = true
        case "w:br", "w:tab":
            currentParagraphText += elementName == "w:tab" ? "\t" : "\n"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingText else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        switch elementName {
        case "w:t":
            isCapturingText = false
            currentParagraphText += currentText
        case "w:tc":
            inTableCell = false
            currentRowCells.append(currentParagraphText.trimmingCharacters(in: .whitespacesAndNewlines))
            currentParagraphText = ""
        case "w:tr":
            if tableRowsEmitted == 0 {
                output += "| " + currentRowCells.joined(separator: " | ") + " |\n"
                output += "| " + currentRowCells.map { _ in "---" }.joined(separator: " | ") + " |\n"
            } else {
                output += "| " + currentRowCells.joined(separator: " | ") + " |\n"
            }
            tableRowsEmitted += 1
        case "w:p":
            guard !inTableCell else { return }
            let trimmed = currentParagraphText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let style = currentParagraphStyle, style.hasPrefix("Heading"),
               let level = Int(style.dropFirst("Heading".count)) {
                output += String(repeating: "#", count: min(max(level, 1), 6)) + " \(trimmed)\n\n"
            } else if !trimmed.isEmpty {
                output += trimmed + "\n\n"
            }
            currentParagraphText = ""
        default:
            break
        }
    }
}
