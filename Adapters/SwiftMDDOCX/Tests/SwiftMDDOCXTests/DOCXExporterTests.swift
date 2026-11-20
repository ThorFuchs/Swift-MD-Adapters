// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import SwiftMDDOCX

final class DOCXExporterTests: XCTestCase {
    private func parts(_ data: Data) throws -> [String: Data] {
        // Read local ZIP records independently of the producer; the integration
        // verification also checks the central directory and CRC with Python zipfile.
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i+1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i+2) << 16 }
        var offset = 0, output: [String: Data] = [:]
        while offset + 30 <= bytes.count && u32(offset) == 0x04034b50 {
            XCTAssertEqual(u16(offset + 8), 0, "entries must use ZIP store")
            let size = u32(offset + 18), length = u16(offset + 26), extra = u16(offset + 28)
            let start = offset + 30 + length + extra
            guard start + size <= bytes.count,
                  let name = String(bytes: bytes[(offset+30)..<(offset+30+length)], encoding: .utf8) else {
                throw DOCXError.unsupported("invalid ZIP record")
            }
            XCTAssertNil(output[name])
            output[name] = Data(bytes[start..<(start+size)])
            offset = start + size
        }
        return output
    }

    func testFixtureStructureAndSemantics() throws {
        let fixture = try String(contentsOf: Bundle.module.url(forResource: "example", withExtension: "md", subdirectory: "Fixtures")!, encoding: .utf8)
        let data = try DOCXExporter().render(fixture)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(data, try DOCXExporter().render(fixture), "output is deterministic")
        let entries = try parts(data)
        XCTAssertEqual(Set(entries.keys), Set(["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/_rels/document.xml.rels", "word/styles.xml", "word/numbering.xml", "word/settings.xml"]))
        for (name, content) in entries { XCTAssertTrue(XMLParser(data: content).parse(), "invalid XML: \(name)") }
        let doc = try XCTUnwrap(String(data: XCTUnwrap(entries["word/document.xml"]), encoding: .utf8))
        let styles = try XCTUnwrap(String(data: XCTUnwrap(entries["word/styles.xml"]), encoding: .utf8))
        let settings = String(decoding: try XCTUnwrap(entries["word/settings.xml"]), as: UTF8.self)
        let rels = String(decoding: try XCTUnwrap(entries["word/_rels/document.xml.rels"]), as: UTF8.self)
        let contentTypes = String(decoding: try XCTUnwrap(entries["[Content_Types].xml"]), as: UTF8.self)
        XCTAssertTrue(settings.contains("w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\""))
        XCTAssertTrue(rels.contains("relationships/settings\" Target=\"settings.xml\""))
        XCTAssertTrue(contentTypes.contains("PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\""))
        let numbering = try XCTUnwrap(String(data: XCTUnwrap(entries["word/numbering.xml"]), encoding: .utf8))
        for text in ["SwiftMD — Grüße 世界 🐉", "bold", "italic", "inline code", "First item", "Nested item", "Third", "Äpfel", "猫", "Hallo &amp; &lt;Welt&gt;", "A quotation."] {
            XCTAssertTrue(doc.contains(text), "missing \(text)")
        }
        let ordered = ["SwiftMD — Grüße", "First item", "Third", "Äpfel", "Hallo &amp;"]
        var position = doc.startIndex
        for text in ordered {
            let range = try XCTUnwrap(doc.range(of: text, range: position..<doc.endIndex))
            position = range.upperBound
        }
        for value in ["Heading1", "Heading2", "<w:b/>", "<w:i/>", "<w:br/>", "<w:tbl>", "<w:numPr>", "w:w=\"11906\"", "w:h=\"16838\""] { XCTAssertTrue(doc.contains(value), value) }
        for level in 1...6 { XCTAssertTrue(styles.contains("w:styleId=\"Heading\(level)\"")) }
        XCTAssertTrue(styles.contains("w:styleId=\"Normal\"")); XCTAssertTrue(styles.contains("w:styleId=\"Code\""))
        XCTAssertTrue(numbering.contains("w:val=\"bullet\"")); XCTAssertTrue(numbering.contains("w:val=\"decimal\"")); XCTAssertTrue(numbering.contains("<w:start w:val=\"3\"/>"))
        if let path = ProcessInfo.processInfo.environment["SWIFTMDDOCX_TEST_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func testPaperAndStyleValidation() throws {
        var style = DOCXStyle(paper: .letter, bodyFont: "A & B", headingPageBreak: true)
        let entries = try parts(DOCXExporter().render("# Heading", style: style))
        let document = String(decoding: try XCTUnwrap(entries["word/document.xml"]), as: UTF8.self)
        let styles = String(decoding: try XCTUnwrap(entries["word/styles.xml"]), as: UTF8.self)
        XCTAssertTrue(document.contains("w:w=\"12240\" w:h=\"15840\""))
        XCTAssertTrue(styles.contains("A &amp; B")); XCTAssertTrue(styles.contains("<w:pageBreakBefore/>"))
        style.bodyFontSize = 0
        XCTAssertThrowsError(try DOCXExporter().render("text", style: style))
        style.bodyFontSize = 11; style.bodyFont = "a\u{1}b"
        XCTAssertThrowsError(try DOCXExporter().render("text", style: style)) { XCTAssertEqual($0 as? DOCXError, .invalidXMLCharacter) }
    }

    func testParagraphListAndTableSpacing() throws {
        let style = DOCXStyle(paragraphSpacingTwips: 160, listSpacingTwips: 35, tableCellPaddingTwips: 90)
        let tight = try parts(DOCXExporter().render("# Heading\n\n- One\n- Two\n\n| A | B |\n| :--- | ---: |\n| 1 | 2 |", style: style))
        let doc = String(decoding: try XCTUnwrap(tight["word/document.xml"]), as: UTF8.self)
        let styles = String(decoding: try XCTUnwrap(tight["word/styles.xml"]), as: UTF8.self)
        XCTAssertTrue(styles.contains("<w:spacing w:after=\"160\"/>"))
        XCTAssertTrue(styles.contains("<w:spacing w:before=\"240\" w:after=\"80\"/>"))
        XCTAssertEqual(doc.components(separatedBy: "<w:spacing w:after=\"35\"/>").count - 1, 2)
        XCTAssertTrue(doc.contains("<w:tblCellMar><w:top w:w=\"90\" w:type=\"dxa\"/>"))
        XCTAssertTrue(doc.contains("<w:spacing w:after=\"0\"/><w:jc"))
        let loose = try parts(DOCXExporter().render("- One\n\n- Two", style: style))
        let looseDoc = String(decoding: try XCTUnwrap(loose["word/document.xml"]), as: UTF8.self)
        XCTAssertEqual(looseDoc.components(separatedBy: "<w:spacing w:after=\"160\"/>").count - 1, 2)
        var invalid = style
        invalid.tableCellPaddingTwips = -1
        XCTAssertThrowsError(try DOCXExporter().render("text", style: invalid))
        invalid = style; invalid.listSpacingTwips = 2001
        XCTAssertThrowsError(try DOCXExporter().render("text", style: invalid))
    }

    func testUnsupportedContentFailsExplicitly() throws {
        for source in ["![alt](image.png)", "Text <span>raw</span>", "<div>raw</div>"] {
            XCTAssertThrowsError(try DOCXExporter().render(source), source) { XCTAssertNotNil($0 as? DOCXError) }
        }
    }

    func testNestedRunPropertiesAndEscaping() throws {
        let result = try parts(DOCXExporter().render("***bold italic `code`*** & <https://example.org/?a=1&b=2>"))
        let document = String(decoding: try XCTUnwrap(result["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(document.contains("<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/><w:b/><w:i/>"))
        XCTAssertTrue(document.contains("&amp;"))
        XCTAssertFalse(document.contains("<w:hyperlink"), "fallback is visible, not an active link")
    }

    func testRichSourceFallbackIsLabelled() throws {
        let result = try parts(DOCXExporter().render("```math\nx^2\n```\n\n```mermaid\nA--&gt;B\n```"))
        let document = String(decoding: try XCTUnwrap(result["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(document.contains("[math source]")); XCTAssertTrue(document.contains("[mermaid source]"))
    }
}
