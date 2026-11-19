// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftMD
import SwiftMDSoup

/// Trusted HTML returned by a block renderer. The caller is responsible for its safety.
public enum BlockReplacement: Sendable {
    /// Replace the contents of the existing code element, preserving its attributes.
    case codeHTML(String)
    /// Replace the entire pre element.
    case blockHTML(String)
    /// A fragment accepted by the strict SVG validator, preserved byte for byte.
    case validatedSVG(ValidatedSVG)
}

/// A synchronous renderer. Calls occur in registration order; the first match wins.
/// Implementations must be safe for concurrent use and must escape untrusted input.
public protocol BlockRenderer: Sendable {
    func accepts(language: String) -> Bool
    func render(literal: String, language: String, index: Int) throws -> BlockReplacement
}

public struct BlockDiagnostic: Sendable, Equatable {
    public enum Kind: Sendable { case unsupportedLanguage, renderFailed, unsupportedContent }
    public let kind: Kind
    public let blockIndex: Int
    public let language: String
    public let message: String
}

public enum BlockProcessingError: Error, Sendable { case missingBody }

public struct BlockResult: Sendable {
    public let html: String
    public let diagnostics: [BlockDiagnostic]
}

/// Explicit opt-in HTML profile. It processes *all* matching pre/code elements,
/// including author-provided raw HTML. Returned HTML is reserialized by SwiftSoup.
public struct BlockCompiler: Sendable {
    public let compiler: MarkdownCompiler
    public let renderers: [any BlockRenderer]

    public init(compiler: MarkdownCompiler = .init(), renderers: [any BlockRenderer]) {
        self.compiler = compiler
        self.renderers = renderers
    }

    public func render(_ source: String) throws -> BlockResult {
        let original = try compiler.render(source).html
        if renderers.isEmpty { return BlockResult(html: original, diagnostics: []) }
        let doc = try SwiftMDSoup.parseBodyFragment(original)
        doc.outputSettings().prettyPrint(pretty: false)
        guard let body = doc.body() else { throw BlockProcessingError.missingBody }
        var diagnostics: [BlockDiagnostic] = []
        var fragments: [(String, String)] = []
        for (index, code) in try body.select("pre > code").array().enumerated() {
            guard let pre = code.parent() else { continue }
            let classes = try code.attr("class").split(whereSeparator: { $0.isWhitespace })
            let preLanguage = try pre.attr("lang").split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            let label = classes.first(where: { $0.hasPrefix("language-") }).map { String($0.dropFirst(9)) }
                ?? preLanguage ?? ""
            let language = label.lowercased()
            guard !language.isEmpty else { continue }
            guard code.getChildNodes().allSatisfy({ $0 is TextNode }) else {
                diagnostics.append(.init(kind: .unsupportedContent, blockIndex: index, language: language, message: "Code element contains non-text nodes"))
                continue
            }
            guard let renderer = renderers.first(where: { $0.accepts(language: language) }) else {
                diagnostics.append(.init(kind: .unsupportedLanguage, blockIndex: index, language: language, message: "No renderer accepts this language"))
                continue
            }
            let literal = code.textNodes().map { $0.getWholeText() }.joined()
            do {
                switch try renderer.render(literal: literal, language: language, index: index) {
                case .codeHTML(let html): _ = try code.html(html)
                case .blockHTML(let html): _ = try pre.before(html); try pre.remove()
                case .validatedSVG(let svg):
                    var marker: String
                    repeat { marker = "SWIFTMD" + UUID().uuidString.replacingOccurrences(of: "-", with: "") } while original.contains(marker)
                    _ = try pre.before(marker); try pre.remove()
                    fragments.append((marker, svg.html))
                }
            } catch {
                diagnostics.append(.init(kind: .renderFailed, blockIndex: index, language: language, message: String(describing: error)))
            }
        }
        var html = try body.html()
        for (marker, fragment) in fragments {
            guard let range = html.range(of: marker), html.range(of: marker, range: range.upperBound..<html.endIndex) == nil else { throw BlockProcessingError.missingBody }
            html.replaceSubrange(range, with: fragment)
        }
        return BlockResult(html: html, diagnostics: diagnostics)
    }
}
