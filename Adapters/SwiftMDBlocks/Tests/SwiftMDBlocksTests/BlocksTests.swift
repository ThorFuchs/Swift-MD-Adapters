// SPDX-License-Identifier: Apache-2.0
import XCTest
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import SwiftMDBlocks
import SwiftMDHighlight
import SwiftHTML
import SwiftMD
import SwiftGFM

final class BlocksTests: XCTestCase {
    private final class TextCollector: NSObject, XMLParserDelegate {
        var value = ""
        func parser(_ parser: XMLParser, foundCharacters string: String) { value += string }
    }

    /// These controlled highlighter fixtures contain XML-compatible spans and
    /// entities. An independent XML parser checks the complete text, including
    /// whitespace, without relying on SwiftHTML's normalized text accessor.
    private func highlightedText(_ code: HTMLElement) throws -> String {
        let collector = TextCollector()
        let parser = XMLParser(data: Data(("<root>" + (try code.innerHTML()) + "</root>").utf8))
        parser.delegate = collector
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return collector.value
    }

    func testRealHighlightAndLiteralReconstruction() throws {
        let input = "```swift metadata\nlet word = \"<hello> 😀 &\" // comment\n```\n"
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render(input)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let code = try XCTUnwrap(HTMLDocument.parseFragment(result.html).select("pre > code").first)
        XCTAssertEqual(try highlightedText(code), "let word = \"<hello> 😀 &\" // comment\n")
        XCTAssertFalse(try code.select("span.hljs-keyword").isEmpty)
        XCTAssertFalse(try code.select("span.hljs-string").isEmpty)
        XCTAssertFalse(try code.select("span.hljs-comment").isEmpty)
    }

    func testUnknownAndReservedLanguagesFallBack() throws {
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render("```madeuplanguage\n<test>\n```\n\n```math\nx^2\n```\n")
        XCTAssertEqual(result.diagnostics.count, 2)
        XCTAssertEqual(result.diagnostics[0].kind, .renderFailed)
        XCTAssertEqual(result.diagnostics[1].kind, .unsupportedLanguage)
        let blocks = try HTMLDocument.parseFragment(result.html).select("pre > code")
        XCTAssertEqual(blocks[0].directText(), "<test>\n")
        XCTAssertEqual(blocks[1].directText(), "x^2\n")
    }

    func testRawHTMLPolicyAndOptions() throws {
        let config = MarkdownConfiguration(options: [.allowUnsafeHTML, .githubPreLanguage, .sourcePositions, .fullInfoString])
        let compiler = BlockCompiler(compiler: MarkdownCompiler(configuration: config), renderers: [HighlightRenderer()])
        let source = """
        | key | value |
        | --- | ----- |
        | x | [link](https://example.com) |

        ```swift extra
        let x = 1
        ```

        <pre><code class="language-swift">let raw = 2</code></pre>
        """
        let result = try compiler.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let doc = try HTMLDocument.parseFragment(result.html)
        XCTAssertEqual(try doc.select("pre span.hljs-keyword").count, 2)
        XCTAssertEqual(try doc.select("table").count, 1)
        XCTAssertEqual(try doc.select("a").first?.attribute("href"), "https://example.com")
        XCTAssertEqual(try doc.select("pre").first?.attribute("lang"), "swift")
        XCTAssertFalse(try doc.select("pre").first?.attribute("data-sourcepos")?.isEmpty ?? true)
    }

    func testEmptyRendererListIsByteIdentical() throws {
        let source = "<p>unsafe</p>\n\n```swift\nlet x = 1\n```\n"
        let plain = try MarkdownCompiler().render(source).html
        XCTAssertEqual(try BlockCompiler(renderers: []).render(source).html, plain)
    }

    func testNestedRepeatedAndEmptyBlocks() throws {
        let source = "> ~~~SWIFT data\r\n> let a = \"&\"\r\n> ~~~\r\n\r\n```swift\n```\n\n```swift\nlet a = \"&\"\n```"
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let blocks = try HTMLDocument.parseFragment(result.html).select("pre > code")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(try highlightedText(blocks[0]), "let a = \"&\"\n")
        XCTAssertEqual(blocks[1].directText(), "")
        XCTAssertEqual(try highlightedText(blocks[2]), "let a = \"&\"\n")
    }

    func testRendererPriorityAndFailureFallback() throws {
        struct Renderer: BlockRenderer {
            let fails: Bool
            func accepts(language: String) -> Bool { language == "swift" }
            func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
                if fails { throw ExampleError.failed }
                return .codeHTML("<b>first</b>")
            }
        }
        enum ExampleError: Error { case failed }
        let source = "```swift\noriginal & text\n```\n"
        let ok = try BlockCompiler(renderers: [Renderer(fails: false), HighlightRenderer()]).render(source)
        XCTAssertTrue(ok.html.contains("<b>first</b>"))
        let failed = try BlockCompiler(renderers: [Renderer(fails: true), HighlightRenderer()]).render(source)
        XCTAssertEqual(failed.diagnostics.first?.kind, .renderFailed)
        let code = try XCTUnwrap(HTMLDocument.parseFragment(failed.html).select("pre > code").first)
        XCTAssertEqual(code.directText(), "original & text\n")
        XCTAssertEqual(try code.select("span").count, 0)
    }

    func testAliasAndAdversarialCodeRemainText() throws {
        let source = "```js\nconst x = \"</code><script>alert(1)</script> & 😀\";\n```\n"
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let doc = try HTMLDocument.parseFragment(result.html)
        XCTAssertEqual(try doc.select("script").count, 0)
        let code = try XCTUnwrap(doc.select("pre > code").first)
        XCTAssertEqual(try highlightedText(code), "const x = \"</code><script>alert(1)</script> & 😀\";\n")
        XCTAssertFalse(try code.select("span.hljs-keyword").isEmpty)
    }

    func testRawHTMLWithNestedCodeContentIsNotRewritten() throws {
        let config = MarkdownConfiguration(options: [.allowUnsafeHTML])
        let source = "<pre><code class=\"language-swift\">let <em>x</em> = 1</code></pre>\n"
        let result = try BlockCompiler(compiler: MarkdownCompiler(configuration: config), renderers: [HighlightRenderer()]).render(source)
        XCTAssertEqual(result.diagnostics.first?.kind, .unsupportedContent)
        XCTAssertEqual(try HTMLDocument.parseFragment(result.html).select("pre code em").count, 1)
    }

    func testRendererReceivesExactCodeLiteralIncludingFinalNewline() throws {
        enum LiteralError: Error { case mismatch }
        struct ExactLiteralRenderer: BlockRenderer {
            let expected: String
            func accepts(language: String) -> Bool { language == "swift" }
            func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
                guard literal.utf8.elementsEqual(expected.utf8) else { throw LiteralError.mismatch }
                return .codeHTML("<span>literal preserved</span>")
            }
        }
        let literal = "  let x = \"& 😀\"\n\tprint(x)\n"
        let source = "```swift\n" + literal + "```\n"
        let result = try BlockCompiler(renderers: [ExactLiteralRenderer(expected: literal)]).render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertTrue(result.html.contains("<span>literal preserved</span>"))
    }

    func testValidatedSVGFragmentsAreEmbeddedByteForByte() throws {
        struct SVGRenderer: BlockRenderer {
            func accepts(language: String) -> Bool { language == "diagram" }
            func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
                .validatedSVG(try ValidatedSVG(Self.fragment(index), expectedID: "page-\(index)"))
            }
            static func fragment(_ index: Int) -> String {
                "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"page-\(index)\" viewBox=\"0 0 10 10\" aria-label=\"A &amp; B\"><text x=\"1\" y=\"2\">Grüße &amp; 😀</text></svg>"
            }
        }
        let source = "Before\n\n```diagram\na\n```\n\nMiddle\n\n```diagram\na\n```\n\nAfter\n"
        let result = try BlockCompiler(renderers: [SVGRenderer()]).render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        for index in 0..<2 {
            let expected = SVGRenderer.fragment(index)
            XCTAssertEqual(result.html.components(separatedBy: expected).count, 2)
        }
        XCTAssertTrue(result.html.contains("Before"))
        XCTAssertTrue(result.html.contains("Middle"))
        XCTAssertTrue(result.html.contains("After"))
    }

    func testEmptyMathRendererResultIsNotSuccessful() throws {
        struct EmptyMathRenderer: MathMLRenderer {
            func renderMath(literal: String, displayMode: Bool) throws -> String { "" }
        }
        let source = "$<bad> & x$"
        let result = try BlockCompiler(renderers: []).render([
            .html("<p>"), .math(.init(index: 3, literal: "x", source: source, displayMode: false)), .html("</p>")
        ], mathRenderer: EmptyMathRenderer())
        XCTAssertEqual(result.diagnostics.count, 1)
        XCTAssertEqual(result.diagnostics.first?.kind, .renderFailed)
        XCTAssertEqual(result.diagnostics.first?.blockIndex, 3)
        XCTAssertEqual(result.html, "<p>$&lt;bad&gt; &amp; x$</p>")
    }

    func testValidatedSVGPreservesAdjacentCombiningUnicode() throws {
        struct SVGRenderer: BlockRenderer {
            let svg: String
            func accepts(language: String) -> Bool { language == "diagram" }
            func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
                .validatedSVG(try ValidatedSVG(svg, expectedID: "page-0"))
            }
        }
        struct UnusedMathRenderer: MathMLRenderer {
            func renderMath(literal: String, displayMode: Bool) throws -> String { "" }
        }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"page-0\" viewBox=\"0 0 10 10\"><text>x</text></svg>"
        let parts: [MathDocumentPart] = [.html("<pre><code class=\"language-diagram\">x</code></pre>\u{0301}")]
        let result = try BlockCompiler(renderers: [SVGRenderer(svg: svg)]).render(parts, mathRenderer: UnusedMathRenderer())
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertEqual(result.html, svg + "\u{0301}")
    }

    func testRawCodeWithCommentIsNotTreatedAsTextOnly() throws {
        let config = MarkdownConfiguration(options: [.allowUnsafeHTML])
        let source = "<pre><code class=\"language-swift\">let x<!-- comment --> = 1</code></pre>\n"
        let result = try BlockCompiler(compiler: MarkdownCompiler(configuration: config),
                                       renderers: [HighlightRenderer()]).render(source)
        XCTAssertEqual(result.diagnostics.first?.kind, .unsupportedContent)
        XCTAssertTrue(result.html.contains("<!-- comment -->"))
        XCTAssertFalse(result.html.contains("hljs-keyword"))
    }
}
