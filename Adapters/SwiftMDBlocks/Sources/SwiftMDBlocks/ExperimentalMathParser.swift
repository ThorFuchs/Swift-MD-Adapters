// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftGFM

extension BlockCompiler {
    /// Explicitly recognize supported dollar-delimited Markdown mathematics.
    /// Unsafe raw HTML, NUL and malformed display blocks produce an escaped
    /// document fallback and a diagnostic. This profile does not sanitize HTML.
    public func renderRecognizingMath(_ source: String, mathRenderer: any MathMLRenderer) throws -> BlockResult {
        let parsed: MarkdownMathDocument
        do {
            parsed = try MarkdownEngine(configuration: compiler.configuration).renderRecognizingMath(source)
        } catch let error as MarkdownMathError {
            // The parser cannot safely identify a partial formula on document
            // failure. Preserve the complete original source as escaped text;
            // callers can reject diagnostics in their strict mode.
            let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return BlockResult(html: "<pre><code>\(escaped)</code></pre>\n",
                               diagnostics: [.init(kind: .renderFailed, blockIndex: 0,
                                                   language: "math", message: String(describing: error))])
        }
        let parts: [MathDocumentPart] = parsed.parts.map { part in
            switch part {
            case .html(let html): .html(html)
            case .math(let math): .math(.init(index: math.index, literal: math.literal,
                                               source: math.source, displayMode: math.displayMode))
            }
        }
        // Preserve the existing block profile when the parser found no math.
        if !parsed.parts.contains(where: { if case .math = $0 { true } else { false } }) {
            return try render(source)
        }
        return try render(parts, mathRenderer: mathRenderer)
    }
}
