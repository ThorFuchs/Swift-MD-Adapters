// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftGFM

/// Errors are surfaced to callers; an incomplete document is never returned as success.
public enum DOCXError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupported(String)
    case invalidStyle(String)
    case invalidXMLCharacter
    case nestingLimit
    case archiveTooLarge

    public var description: String {
        switch self {
        case .unsupported(let feature): "Unsupported DOCX content: \(feature)"
        case .invalidStyle(let detail): "Invalid DOCX style: \(detail)"
        case .invalidXMLCharacter: "Text contains a character forbidden by XML 1.0"
        case .nestingLimit: "DOCX nesting limit exceeded"
        case .archiveTooLarge: "DOCX exceeds the non-ZIP64 archive limits"
        }
    }
}

public enum DOCXPaper: Sendable { case a4, letter }

/// A small semantic theme. Font size is in points; margins and spacing are in twips.
public struct DOCXStyle: Sendable {
    public var paper: DOCXPaper
    public var bodyFont: String
    public var bodyFontSize: Int
    public var headingFont: String
    public var marginTwips: Int
    public var paragraphSpacingTwips: Int
    public var listSpacingTwips: Int
    public var tableCellPaddingTwips: Int
    public var headingPageBreak: Bool

    public init(paper: DOCXPaper = .a4, bodyFont: String = "Calibri", bodyFontSize: Int = 11,
                headingFont: String = "Calibri", marginTwips: Int = 1440,
                paragraphSpacingTwips: Int = 120, headingPageBreak: Bool = false,
                listSpacingTwips: Int = 40, tableCellPaddingTwips: Int = 100) {
        self.paper = paper; self.bodyFont = bodyFont; self.bodyFontSize = bodyFontSize
        self.headingFont = headingFont; self.marginTwips = marginTwips
        self.paragraphSpacingTwips = paragraphSpacingTwips; self.headingPageBreak = headingPageBreak
        self.listSpacingTwips = listSpacingTwips; self.tableCellPaddingTwips = tableCellPaddingTwips
    }
    public static let `default` = DOCXStyle()
}

/// A portable, native DOCX projection of SwiftGFM's semantic AST.
public struct DOCXExporter: Sendable {
    public init() {}
    public func render(_ markdown: String, style: DOCXStyle = .default) throws -> Data {
        guard (6...72).contains(style.bodyFontSize), (0...4000).contains(style.marginTwips),
              (0...2000).contains(style.paragraphSpacingTwips), (0...2000).contains(style.listSpacingTwips),
              (0...2000).contains(style.tableCellPaddingTwips),
              !style.bodyFont.isEmpty, !style.headingFont.isEmpty else {
            throw DOCXError.invalidStyle("font size, margins, spacing or font name out of range")
        }
        let tree = try MarkdownEngine().parse(markdown)
        var projection = Projection(style: style)
        let document = try projection.document(tree.root)
        return try StoredZIP.create([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRelationships.utf8)),
            ("word/document.xml", Data(document.utf8)),
            ("word/_rels/document.xml.rels", Data(documentRelationships.utf8)),
            ("word/styles.xml", Data(try styles(style).utf8)),
            ("word/settings.xml", Data(settings.utf8)),
            ("word/numbering.xml", Data(projection.numbering().utf8)),
        ])
    }
}

private let xmlHeader = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
"""
private let wordNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
private let relationshipNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
private let contentTypes = xmlHeader + """
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
"""
private let rootRelationships = xmlHeader + """
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
"""
private let documentRelationships = xmlHeader + """
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>
"""

// Without an explicit setting Word defaults to the Word 2007 feature set.
// https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/90138c4d-eb18-4edc-aa6c-dfb799cb1d0d
private let settings = xmlHeader + """
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
"""

private func escape(_ value: String) throws -> String {
    for c in value.unicodeScalars {
        let n = c.value
        guard n == 9 || n == 10 || n == 13 || (0x20...0xd7ff).contains(n) ||
              (0xe000...0xfffd).contains(n) || (0x10000...0x10ffff).contains(n) else {
            throw DOCXError.invalidXMLCharacter
        }
    }
    return value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

private func styles(_ style: DOCXStyle) throws -> String {
    let body = try escape(style.bodyFont), heading = try escape(style.headingFont)
    let sizes = [32, 28, 24, 22, 20, 18]
    var result = xmlHeader + "<w:styles xmlns:w=\"\(wordNS)\">"
    result += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"\(style.paragraphSpacingTwips)\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"\(body)\" w:hAnsi=\"\(body)\"/><w:sz w:val=\"\(style.bodyFontSize * 2)\"/></w:rPr></w:style>"
    for level in 1...6 {
        result += "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:pPr><w:keepNext/>\(style.headingPageBreak ? "<w:pageBreakBefore/>" : "")<w:spacing w:before=\"240\" w:after=\"80\"/><w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"\(heading)\" w:hAnsi=\"\(heading)\"/><w:b/><w:sz w:val=\"\(sizes[level-1])\"/></w:rPr></w:style>"
    }
    result += "<w:style w:type=\"paragraph\" w:styleId=\"Code\"><w:name w:val=\"Code\"/><w:basedOn w:val=\"Normal\"/><w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/></w:rPr></w:style>"
    return result + "</w:styles>"
}

private struct Projection {
    let style: DOCXStyle
    private var lists: [(style: MarkdownListStyle, depth: Int)] = []
    init(style: DOCXStyle) { self.style = style }

    mutating func document(_ root: MarkdownNode) throws -> String {
        let body = try blocks(root.children, depth: 0, quote: false)
        let page = style.paper == .a4 ? (11906, 16838) : (12240, 15840)
        let margin = style.marginTwips
        return xmlHeader + "<w:document xmlns:w=\"\(wordNS)\" xmlns:r=\"\(relationshipNS)\"><w:body>" + body +
            "<w:sectPr><w:pgSz w:w=\"\(page.0)\" w:h=\"\(page.1)\"/><w:pgMar w:top=\"\(margin)\" w:right=\"\(margin)\" w:bottom=\"\(margin)\" w:left=\"\(margin)\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
    }

    mutating func blocks(_ nodes: [MarkdownNode], depth: Int, quote: Bool) throws -> String {
        guard depth <= 32 else { throw DOCXError.nestingLimit }
        var result = ""
        for node in nodes {
            switch node.kind {
            case .paragraph:
                result += try paragraph(node.children, quote: quote)
            case .heading(let level):
                guard (1...6).contains(level) else { throw DOCXError.unsupported("heading level \(level)") }
                result += try paragraph(node.children, properties: "<w:pStyle w:val=\"Heading\(level)\"/>", quote: quote)
            case .blockQuote:
                result += try blocks(node.children, depth: depth + 1, quote: true)
            case .codeBlock(let literal, let info, _):
                let language = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                let label = ["math", "mermaid"].contains(language.lowercased()) ? "[\(language) source]\n" : ""
                result += try "<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr>\(run(label + literal, properties: RunStyle()))</w:p>"
            case .list(let listStyle, let tight):
                lists.append((listStyle, depth))
                let listID = lists.count
                for item in node.children {
                    let marker: String
                    switch item.kind {
                    case .listItem: marker = ""
                    case .taskListItem(_, let checked): marker = checked ? "☒ " : "☐ "
                    default: throw DOCXError.unsupported("list child")
                    }
                    let spacing = tight ? style.listSpacingTwips : style.paragraphSpacingTwips
                    let properties = "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(listID)\"/></w:numPr><w:spacing w:after=\"\(spacing)\"/>"
                    var first = true
                    for child in item.children {
                        if first, case .paragraph = child.kind {
                            result += try paragraph(child.children, properties: properties, prefix: marker, quote: quote)
                        } else {
                            if first { result += try paragraph([], properties: properties, prefix: marker, quote: quote) }
                            result += try blocks([child], depth: depth + 1, quote: quote)
                        }
                        first = false
                    }
                    if first { result += try paragraph([], properties: properties, prefix: marker, quote: quote) }
                }
            case .table(let alignments):
                result += try table(node, alignments: alignments)
            case .thematicBreak:
                result += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"1\" w:color=\"auto\"/></w:pBdr></w:pPr></w:p>"
            case .htmlBlock: throw DOCXError.unsupported("raw HTML block")
            case .customBlock: throw DOCXError.unsupported("custom block")
            case .footnoteDefinition: throw DOCXError.unsupported("footnote definition")
            default: throw DOCXError.unsupported("unexpected block \(node.kind)")
            }
        }
        return result
    }

    func paragraph(_ children: [MarkdownNode], properties: String = "", prefix: String = "", quote: Bool = false) throws -> String {
        let p = properties + (quote ? "<w:ind w:left=\"720\"/>" : "")
        let runs = try (prefix.isEmpty ? "" : run(prefix, properties: RunStyle())) + inline(children, properties: RunStyle(), depth: 0)
        return "<w:p>\(p.isEmpty ? "" : "<w:pPr>\(p)</w:pPr>")\(runs)</w:p>"
    }

    func inline(_ nodes: [MarkdownNode], properties: RunStyle, depth: Int) throws -> String {
        guard depth <= 32 else { throw DOCXError.nestingLimit }
        var result = ""
        for node in nodes {
            switch node.kind {
            case .text(let text): result += try run(text, properties: properties)
            case .code(let text): result += try run(text, properties: properties.withCode())
            case .softBreak, .lineBreak: result += "<w:r>\(properties.xml)<w:br/></w:r>"
            case .strong: result += try inline(node.children, properties: properties.withBold(), depth: depth + 1)
            case .emphasis: result += try inline(node.children, properties: properties.withItalic(), depth: depth + 1)
            case .strikethrough: result += try inline(node.children, properties: properties.withStrike(), depth: depth + 1)
            case .link(let destination, let title):
                result += try inline(node.children, properties: properties, depth: depth + 1)
                result += try run(" (\(destination)\(title.isEmpty ? "" : " — \(title)"))", properties: properties)
            case .image: throw DOCXError.unsupported("image")
            case .htmlInline: throw DOCXError.unsupported("raw inline HTML")
            case .customInline: throw DOCXError.unsupported("custom inline content")
            case .footnoteReference: throw DOCXError.unsupported("footnote reference")
            default: throw DOCXError.unsupported("unexpected inline node \(node.kind)")
            }
        }
        return result
    }

    func run(_ text: String, properties: RunStyle) throws -> String {
        var contents = "", chunk = ""
        func flush() throws {
            if !chunk.isEmpty { contents += "<w:t xml:space=\"preserve\">\(try escape(chunk))</w:t>"; chunk = "" }
        }
        for char in text {
            switch char {
            case "\n": try flush(); contents += "<w:br/>"
            case "\t": try flush(); contents += "<w:tab/>"
            case "\r": try flush(); contents += "<w:br/>"
            default: chunk.append(char)
            }
        }
        try flush()
        return "<w:r>\(properties.xml)\(contents)</w:r>"
    }

    func table(_ node: MarkdownNode, alignments: [MarkdownTableAlignment]) throws -> String {
        var result = "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/><w:insideV w:val=\"single\" w:sz=\"4\"/></w:tblBorders><w:tblCellMar><w:top w:w=\"\(style.tableCellPaddingTwips)\" w:type=\"dxa\"/><w:left w:w=\"\(style.tableCellPaddingTwips)\" w:type=\"dxa\"/><w:bottom w:w=\"\(style.tableCellPaddingTwips)\" w:type=\"dxa\"/><w:right w:w=\"\(style.tableCellPaddingTwips)\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
        result += "<w:tblGrid>" + alignments.map { _ in "<w:gridCol w:w=\"2400\"/>" }.joined() + "</w:tblGrid>"
        for row in node.children {
            guard case .tableRow(let header) = row.kind else { throw DOCXError.unsupported("table row") }
            result += "<w:tr>\(header ? "<w:trPr><w:tblHeader/></w:trPr>" : "")"
            for (index, cell) in row.children.enumerated() {
                guard case .tableCell = cell.kind else { throw DOCXError.unsupported("table cell") }
                let alignment = index < alignments.count ? alignments[index] : .none
                let value: String
                switch alignment { case .none: value = ""; case .left: value = "left"; case .center: value = "center"; case .right: value = "right" }
                let properties = "<w:spacing w:after=\"0\"/>" + (value.isEmpty ? "" : "<w:jc w:val=\"\(value)\"/>")
                result += try "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr>\(paragraph(cell.children, properties: properties))</w:tc>"
            }
            result += "</w:tr>"
        }
        return result + "</w:tbl>"
    }

    func numbering() -> String {
        var result = xmlHeader + "<w:numbering xmlns:w=\"\(wordNS)\">"
        for (i, list) in lists.enumerated() {
            let start: Int, format: String, marker: String
            switch list.style {
            case .bullet: start = 1; format = "bullet"; marker = "•"
            case .ordered(let value, let delimiter): start = value; format = "decimal"; marker = delimiter == .period ? "%1." : "%1)"
            }
            let left = min(list.depth + 1, 32) * 720
            result += "<w:abstractNum w:abstractNumId=\"\(i)\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"\(start)\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(marker)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(left)\"/></w:tabs><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr></w:lvl></w:abstractNum>"
        }
        for i in lists.indices { result += "<w:num w:numId=\"\(i+1)\"><w:abstractNumId w:val=\"\(i)\"/></w:num>" }
        return result + "</w:numbering>"
    }
}

// WordprocessingML requires run properties in schema order even when Markdown
// emphasis is nested in a different order.
private struct RunStyle {
    var code = false, bold = false, italic = false, strike = false
    func withCode() -> Self { var s = self; s.code = true; return s }
    func withBold() -> Self { var s = self; s.bold = true; return s }
    func withItalic() -> Self { var s = self; s.italic = true; return s }
    func withStrike() -> Self { var s = self; s.strike = true; return s }
    var xml: String {
        let content = (code ? "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/>" : "") +
            (bold ? "<w:b/>" : "") + (italic ? "<w:i/>" : "") + (strike ? "<w:strike/>" : "")
        return content.isEmpty ? "" : "<w:rPr>\(content)</w:rPr>"
    }
}
