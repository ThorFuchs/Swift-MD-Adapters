// SPDX-License-Identifier: Apache-2.0
import XCTest
import SwiftMDBlocks
import SwiftMDHighlight
import SwiftMDSoup
import SwiftMD
import SwiftGFM

final class BlocksTests: XCTestCase {
    func testRealHighlightAndLiteralReconstruction() throws {
        let input = "```swift metadata\nlet word = \"<hello> 😀 &\" // comment\n```\n"
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render(input)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let code = try XCTUnwrap(SwiftMDSoup.parseBodyFragment(result.html).select("pre > code").first())
        XCTAssertEqual(try code.text(trimAndNormaliseWhitespace: false), "let word = \"<hello> 😀 &\" // comment\n")
        XCTAssertFalse(try code.select("span.hljs-keyword").isEmpty())
        XCTAssertFalse(try code.select("span.hljs-string").isEmpty())
        XCTAssertFalse(try code.select("span.hljs-comment").isEmpty())
    }

    func testUnknownAndReservedLanguagesFallBack() throws {
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render("```madeuplanguage\n<test>\n```\n\n```math\nx^2\n```\n")
        XCTAssertEqual(result.diagnostics.count, 2)
        XCTAssertEqual(result.diagnostics[0].kind, .renderFailed)
        XCTAssertEqual(result.diagnostics[1].kind, .unsupportedLanguage)
        let blocks = try SwiftMDSoup.parseBodyFragment(result.html).select("pre > code").array()
        XCTAssertEqual(try blocks[0].text(trimAndNormaliseWhitespace: false), "<test>\n")
        XCTAssertEqual(try blocks[1].text(trimAndNormaliseWhitespace: false), "x^2\n")
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
        let doc = try SwiftMDSoup.parseBodyFragment(result.html)
        XCTAssertEqual(try doc.select("pre span.hljs-keyword").size(), 2)
        XCTAssertEqual(try doc.select("table").size(), 1)
        XCTAssertEqual(try doc.select("a").first()?.attr("href"), "https://example.com")
        XCTAssertEqual(try doc.select("pre").first()?.attr("lang"), "swift")
        XCTAssertFalse(try doc.select("pre").first()?.attr("data-sourcepos").isEmpty ?? true)
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
        let blocks = try SwiftMDSoup.parseBodyFragment(result.html).select("pre > code").array()
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(try blocks[0].text(trimAndNormaliseWhitespace: false), "let a = \"&\"\n")
        XCTAssertEqual(try blocks[1].text(trimAndNormaliseWhitespace: false), "")
        XCTAssertEqual(try blocks[2].text(trimAndNormaliseWhitespace: false), "let a = \"&\"\n")
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
        let code = try XCTUnwrap(SwiftMDSoup.parseBodyFragment(failed.html).select("pre > code").first())
        XCTAssertEqual(try code.text(trimAndNormaliseWhitespace: false), "original & text\n")
        XCTAssertEqual(try code.select("span").size(), 0)
    }

    func testAliasAndAdversarialCodeRemainText() throws {
        let source = "```js\nconst x = \"</code><script>alert(1)</script> & 😀\";\n```\n"
        let result = try BlockCompiler(renderers: [HighlightRenderer()]).render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let doc = try SwiftMDSoup.parseBodyFragment(result.html)
        XCTAssertEqual(try doc.select("script").size(), 0)
        let code = try XCTUnwrap(doc.select("pre > code").first())
        XCTAssertEqual(try code.text(trimAndNormaliseWhitespace: false), "const x = \"</code><script>alert(1)</script> & 😀\";\n")
        XCTAssertFalse(try code.select("span.hljs-keyword").isEmpty())
    }

    func testRawHTMLWithNestedCodeContentIsNotRewritten() throws {
        let config = MarkdownConfiguration(options: [.allowUnsafeHTML])
        let source = "<pre><code class=\"language-swift\">let <em>x</em> = 1</code></pre>\n"
        let result = try BlockCompiler(compiler: MarkdownCompiler(configuration: config), renderers: [HighlightRenderer()]).render(source)
        XCTAssertEqual(result.diagnostics.first?.kind, .unsupportedContent)
        XCTAssertEqual(try SwiftMDSoup.parseBodyFragment(result.html).select("pre code em").size(), 1)
    }
}
