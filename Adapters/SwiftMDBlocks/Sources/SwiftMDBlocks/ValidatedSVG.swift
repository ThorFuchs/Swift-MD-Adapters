// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Deliberately narrow Pele SVG subset. Unknown elements, attributes and CSS
/// fail closed. This is not a general-purpose SVG sanitizer.
public struct ValidatedSVG: Sendable {
    public let html: String
    public init(_ html: String, expectedID: String) throws {
        guard html.utf8.count <= 2_000_000, !expectedID.isEmpty, expectedID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              !html.contains("<!"), !html.contains("<?"), !html.contains("\\"),
              html.hasPrefix("<svg "), html.contains(" id=\"\(expectedID)\""),
              Self.hasOpenRoot(html), let close = html.range(of: "</svg>"),
              close.upperBound == html.endIndex else { throw SVGError.rejected }
        // FoundationXML on Linux can accept a document while ignoring bytes
        // after the first root. Reject them lexically: nested SVG is already
        // prohibited, and comments, CDATA and processing instructions are banned.
        let validator = SVGValidator(expectedID: expectedID)
        let parser = XMLParser(data: Data(html.utf8)); parser.delegate = validator
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), validator.valid, validator.depth == 0, validator.roots == 1, validator.accessibilityIsConsistent else { throw SVGError.rejected }
        self.html = html
    }

    // Find the end of the root start tag without confusing a quoted `>` with
    // its delimiter; a self-closing root could hide later bytes from XMLParser.
    private static func hasOpenRoot(_ html: String) -> Bool {
        var quote: UInt8?
        var previous: UInt8 = 0
        for byte in html.utf8.dropFirst(4) {
            if let current = quote {
                if byte == current { quote = nil }
            } else if byte == 34 || byte == 39 {
                quote = byte
                previous = byte
            } else if byte == 62 {
                return previous != 47
            } else if byte != 32 && byte != 9 && byte != 10 && byte != 13 {
                previous = byte
            }
        }
        return false
    }
    public enum SVGError: Error { case rejected }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    let expectedID: String
    var valid = true, depth = 0, roots = 0
    var elementStack: [String] = []
    var ids: Set<String> = []
    var labelled = false, described = false
    var accessibilityIsConsistent: Bool {
        labelled == ids.contains(expectedID + "-title") && described == ids.contains(expectedID + "-desc")
    }
    init(expectedID: String) { self.expectedID = expectedID }
    let elements: Set<String> = ["svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "title", "desc"]
    let attributes: Set<String> = ["xmlns", "id", "class", "viewBox", "width", "height", "x", "y", "x1", "x2", "y1", "y2", "cx", "cy", "r", "rx", "ry", "d", "points", "transform", "fill", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap", "stroke-linejoin", "opacity", "fill-opacity", "stroke-opacity", "font-size", "font-weight", "font-family", "text-anchor", "dominant-baseline", "style", "role", "aria-roledescription", "aria-label", "aria-labelledby", "aria-describedby", "data-id", "xml:space"]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attrs: [String : String]) {
        if depth == 0 { roots += 1; if elementName != "svg" || attrs["xmlns"] != "http://www.w3.org/2000/svg" || attrs["id"] != expectedID || attrs["viewBox"] == nil { valid = false } }
        if let parent = elementStack.last, parent == "title" || parent == "desc" { valid = false }
        depth += 1
        if !elements.contains(elementName) || (elementName == "svg" && depth != 1) { valid = false }
        if elementName == "title" || elementName == "desc" {
            if depth != 2 || attrs["id"] != expectedID + "-" + elementName { valid = false }
        }
        elementStack.append(elementName)
        for (key, value) in attrs {
            let lower = value.lowercased()
            if !attributes.contains(key) || (key == "xmlns" && depth != 1) || (key == "id" && !validID(value, element: elementName)) || lower.contains("url(") || lower.contains("expression") || lower.contains("@") || value.contains("\\") || value.contains("{") || value.contains("}") || value.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 && $0.value != 10 && $0.value != 13 }) { valid = false }
            if key == "aria-labelledby" { if depth != 1 || value != expectedID + "-title" { valid = false }; labelled = true }
            if key == "aria-describedby" { if depth != 1 || value != expectedID + "-desc" { valid = false }; described = true }
            if key == "style" && !safeStyle(value) { valid = false }
            if ["fill", "stroke", "font-family", "font-weight"].contains(key) && !safeCSSValue(value) { valid = false }
            if key == "viewBox" && !safeViewBox(value) { valid = false }
            if ["width", "height", "x", "y", "x1", "x2", "y1", "y2", "cx", "cy", "r", "rx", "ry", "stroke-width", "opacity", "fill-opacity", "stroke-opacity", "font-size"].contains(key) && !safeNumber(value) { valid = false }
            if key == "d" && !value.unicodeScalars.allSatisfy({ Self.pathCharacters.contains($0) }) { valid = false }
            if key == "transform" && !safeTransform(value) { valid = false }
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1; _ = elementStack.popLast() }
    func validID(_ value: String, element: String) -> Bool {
        let expected: String
        if depth == 1 && element == "svg" { expected = expectedID }
        else if depth == 2 && (element == "title" || element == "desc") { expected = expectedID + "-" + element }
        else { return false }
        return value == expected && ids.insert(value).inserted
    }
    func safeStyle(_ style: String) -> Bool {
        let names: Set<String> = ["max-width", "height", "color", "font", "font-family", "font-size", "font-weight", "letter-spacing", "word-spacing", "text-transform", "direction", "rx", "fill", "stroke", "stroke-width", "opacity"]
        for declaration in style.split(separator: ";", omittingEmptySubsequences: true) {
            let parts = declaration.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return false }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let custom = name.hasPrefix("--_") && name.utf8.count > 3 && name.utf8.dropFirst(3).allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            }
            guard names.contains(name) || custom else { return false }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard safeCSSValue(value) else { return false }
        }
        return true
    }

    // Accept only a narrow token grammar, never CSS escapes, comments, URLs,
    // strings or arbitrary functions. CSS variables still depend on host CSS.
    func safeCSSValue(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_,.%#() +")
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        var depth = 0
        for character in value {
            if character == "(" { depth += 1; if depth > 8 { return false } }
            if character == ")" { depth -= 1; if depth < 0 { return false } }
        }
        guard depth == 0 else { return false }
        let expression = try! NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_-]*)\s*\("#)
        for match in expression.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range(at: 1), in: value),
                  ["var", "rgb", "rgba", "hsl", "hsla"].contains(value[range].lowercased()) else { return false }
        }
        return true
    }

    func safeNumber(_ value: String) -> Bool {
        guard !value.isEmpty, let number = Double(value), number.isFinite else { return false }
        return value.unicodeScalars.allSatisfy { Self.numberCharacters.contains($0) }
    }
    func safeViewBox(_ value: String) -> Bool {
        let numbers = value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard numbers.count == 4, numbers.allSatisfy(safeNumber),
              let width = Double(numbers[2]), let height = Double(numbers[3]) else { return false }
        return width > 0 && height > 0
    }
    func safeTransform(_ value: String) -> Bool {
        var rest = value
        for name in ["translate", "scale", "rotate", "matrix", "skewX", "skewY"] { rest = rest.replacingOccurrences(of: name, with: "") }
        let allowed = Self.numberCharacters.union(CharacterSet(charactersIn: ", ()"))
        return !value.isEmpty && rest.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
    static let numberCharacters = CharacterSet(charactersIn: "0123456789+-.eE")
    static let pathCharacters = CharacterSet(charactersIn: "0123456789+-.eE ,\n\r\tMmLlHhVvCcSsQqTtAaZz")
}
