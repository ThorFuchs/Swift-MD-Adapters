// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import SwiftMDBlocks
import SwiftMDHighlight
import SwiftMDKaTeXNode
import SwiftMDPeleNode

final class NodeTests: XCTestCase {
    func renderers() throws -> (KaTeXNodeRenderer, PeleNodeRenderer) {
        let env = ProcessInfo.processInfo.environment
        guard let node = env["SWIFTMD_NODE"], let katex = env["SWIFTMD_KATEX"], let pele = env["SWIFTMD_PELE"] else { throw XCTSkip("Set SWIFTMD_NODE, SWIFTMD_KATEX and SWIFTMD_PELE for real renderer tests") }
        return (try KaTeXNodeRenderer(node: node, module: katex), try PeleNodeRenderer(node: node, module: pele, prefix: "page"))
    }
    func testRealCombinedAndStableRepeatedDiagrams() throws {
        let (math, diagram) = try renderers()
        let source = """
        | a | b |
        | - | - |
        | x | [link](https://example.com) |

        ```swift
        let x = "<hello>"
        ```

        ```math
        x^2 + y^2
        ```

        ```mermaid
        flowchart LR
        A[Hello] --> B[World]
        ```

        ```mermaid
        flowchart LR
        A[Hello] --> B[World]
        ```
        """
        let compiler = BlockCompiler(renderers: [math, diagram, HighlightRenderer()])
        let result = try compiler.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertTrue(result.html.contains("<table>")); XCTAssertTrue(result.html.contains("hljs-keyword"))
        XCTAssertTrue(result.html.contains("<math")); XCTAssertTrue(result.html.contains("viewBox="))
        XCTAssertTrue(result.html.contains("id=\"page-2\"")); XCTAssertTrue(result.html.contains("id=\"page-3\""))
        XCTAssertEqual(result.html, try compiler.render(source).html)
    }
    func testFailuresKeepEscapedOriginal() throws {
        let (math, diagram) = try renderers()
        let result = try BlockCompiler(renderers: [math, diagram]).render("```math\n\\badcommand{<script>}\n```\n\n```mermaid\nnot a diagram <script>\n```")
        XCTAssertEqual(result.diagnostics.count, 2)
        XCTAssertFalse(result.html.contains("<script>"))
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
    }
    func testEightRealDiagramTypes() throws {
        let (_, diagram) = try renderers()
        let samples = ["flowchart LR\nA-->B", "sequenceDiagram\nAlice->>Bob: Hello", "classDiagram\nA <|-- B", "stateDiagram-v2\n[*] --> Active", "erDiagram\nUSER ||--o{ POST : writes", "gantt\n title A\n dateFormat YYYY-MM-DD\n section X\n Task :a, 2020-01-01, 2d", "pie\n \"A\" : 2\n \"B\" : 3", "mindmap\n  root((Root))\n    Child"]
        for sample in samples {
            let result = try BlockCompiler(renderers: [diagram]).render("```mermaid\n\(sample)\n```\n")
            XCTAssertTrue(result.diagnostics.isEmpty, "\(sample): \(result.diagnostics)")
            XCTAssertTrue(result.html.contains("<svg"), sample)
        }
    }
    func testAccessibleTitlesAndDescriptionsHaveUniqueReferences() throws {
        let (_, diagram) = try renderers()
        let block = "```mermaid\nflowchart LR\naccTitle: Architecture\naccDescr: Two nodes\nA-->B\n```\n"
        let result = try BlockCompiler(renderers: [diagram]).render(block + "\n" + block)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        for index in 0...1 {
            XCTAssertTrue(result.html.contains("aria-labelledby=\"page-\(index)-title\""))
            XCTAssertTrue(result.html.contains("aria-describedby=\"page-\(index)-desc\""))
            XCTAssertTrue(result.html.contains("<title id=\"page-\(index)-title\">Architecture</title>"))
            XCTAssertTrue(result.html.contains("<desc id=\"page-\(index)-desc\">Two nodes</desc>"))
        }
    }
    func testSeparatelyRenderedPagesHaveDistinctNamespaces() throws {
        let env = ProcessInfo.processInfo.environment
        guard let node = env["SWIFTMD_NODE"], let pele = env["SWIFTMD_PELE"] else { throw XCTSkip("Set real renderer paths") }
        let source = "```mermaid\nflowchart LR\naccTitle: Diagram\nA-->B\n```\n"
        let first = try BlockCompiler(renderers: [PeleNodeRenderer(node: node, module: pele, prefix: "document-one")]).render(source)
        let second = try BlockCompiler(renderers: [PeleNodeRenderer(node: node, module: pele, prefix: "document-two")]).render(source)
        XCTAssertTrue(first.diagnostics.isEmpty && second.diagnostics.isEmpty)
        XCTAssertTrue(first.html.contains("id=\"document-one-0\""))
        XCTAssertTrue(second.html.contains("id=\"document-two-0\""))
        XCTAssertTrue(first.html.contains("aria-labelledby=\"document-one-0-title\""))
        XCTAssertTrue(second.html.contains("aria-labelledby=\"document-two-0-title\""))
        XCTAssertFalse(first.html.contains("document-two-0"))
        XCTAssertFalse(second.html.contains("document-one-0"))
    }
    func testInputAndPostExitOutputLimits() throws {
        let (math, diagram) = try renderers()
        let huge = String(repeating: "x", count: 16_385)
        XCTAssertThrowsError(try math.render(literal: huge, language: "math", index: 0))
        XCTAssertThrowsError(try diagram.render(literal: huge, language: "mermaid", index: 0))
        let node = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTMD_NODE"])
        let accepted = try NodeProcess.run(node: node, script: "process.stdout.write('a'.repeat(2000000))", request: [:])
        XCTAssertEqual(accepted.utf8.count, 2_000_000)
        XCTAssertThrowsError(try NodeProcess.run(node: node, script: "process.stdout.write('a'.repeat(2000001))", request: [:]))
        XCTAssertThrowsError(try NodeProcess.run(node: node, script: "process.stdout.write(Buffer.from([255]))", request: [:]))
        XCTAssertThrowsError(try NodeProcess.run(node: node, script: "process.stderr.write('e'.repeat(10000));process.exitCode=1", request: [:])) { error in
            guard case NodeRendererError.processFailed(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(message.utf8.count, 4096)
        }
    }
    func testPeleDisablesExternalLinksAndImages() throws {
        let (_, diagram) = try renderers()
        let input = "flowchart LR\nA[Click] --> B[Target]\nclick A \"https://evil.test\""
        let result = try BlockCompiler(renderers: [diagram]).render("```mermaid\n\(input)\n```\n")
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertTrue(result.html.contains("<svg"))
        XCTAssertFalse(result.html.contains("https://evil.test"))
        XCTAssertFalse(result.html.contains("<a "))
        XCTAssertFalse(result.html.contains("<image"))
        let image = "flowchart LR\nA@{ img: \"https://evil.test/image.png\", label: \"picture\" }"
        let imageResult = try BlockCompiler(renderers: [diagram]).render("```mermaid\n\(image)\n```\n")
        if imageResult.diagnostics.isEmpty {
            XCTAssertFalse(imageResult.html.contains("<image"))
            XCTAssertFalse(imageResult.html.contains("https://evil.test"))
        } else {
            XCTAssertTrue(imageResult.html.contains("https://evil.test"))
            XCTAssertTrue(imageResult.html.contains("<code"))
        }
    }
    func testSVGRejectsDangerousContent() throws {
        let start = "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"page-0\" viewBox=\"0 0 10 10\">"
        XCTAssertNoThrow(try ValidatedSVG(start + "<text>hello</text></svg>", expectedID: "page-0"))
        XCTAssertNoThrow(try ValidatedSVG(start.replacingOccurrences(of: "viewBox=", with: "aria-label=\"a > b\" viewBox=") + "</svg>", expectedID: "page-0"))
        let attacks = ["<script>alert(1)</script>", "<foreignObject><div>bad</div></foreignObject>", "<animate attributeName=\"x\"/>", "<use href=\"#page-0\"/>", "<image href=\"https://evil.test/a\"/>", "<a href=\"javascript:alert(1)\"><text>x</text></a>", "<rect onload=\"alert(1)\"/>", "<rect style=\"fill:url(https://evil.test)\"/>", "<rect style=\"fill:u\\72l(https://evil.test)\"/>", "<g id=\"page-0\"/>", "<g xmlns=\"http://www.w3.org/1999/xhtml\"/>", "<svg viewBox=\"0 0 1 1\"/>", "<path fill=\"url(#other)\"/>",
                       "<path fill=\"&#117;rl(https://evil.test/a)\"/>",
                       "<path fill=\"u/**/rl(https://evil.test/a)\"/>",
                       "<rect style=\"--_x/**/:red;fill:var(--_x)\"/>",
                       "<path fill=\"var(--x,u&#114;l(https://evil.test/a))\"/>",
                       "<rect style=\"fill:u&#92;72l(https://evil.test/a)\"/>",
                       "<rect style=\"fill:image(https://evil.test/a)\"/>",
                       "<rect width=\"Infinity\"/>", "<path transform=\"url(https://evil.test)\"/>"]
        for attack in attacks { XCTAssertThrowsError(try ValidatedSVG(start + attack + "</svg>", expectedID: "page-0"), attack) }
        XCTAssertThrowsError(try ValidatedSVG(start + String(repeating: "a", count: 2_000_001) + "</svg>", expectedID: "page-0"))
        let labelled = start.replacingOccurrences(of: "viewBox=", with: "aria-labelledby=\"page-0-title\" viewBox=")
        XCTAssertNoThrow(try ValidatedSVG(labelled + "<title id=\"page-0-title\">safe</title></svg>", expectedID: "page-0"))
        for attack in ["<title id=\"page-0-title\">a</title><title id=\"page-0-title\">b</title>", "<title id=\"page-0-title\"><g/></title>", "<title id=\"other\">x</title>", "<g id=\"page-0-title\"/>"] {
            XCTAssertThrowsError(try ValidatedSVG(labelled + attack + "</svg>", expectedID: "page-0"), attack)
        }
        XCTAssertThrowsError(try ValidatedSVG(labelled + "</svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start.replacingOccurrences(of: "viewBox=", with: "aria-labelledby=\"other\" viewBox=") + "</svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start.replacingOccurrences(of: "0 0 10 10", with: "0 0 0 10") + "</svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG("<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + start + "&x;</svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start + "<![CDATA[<script>]]></svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start + "</svg><script>alert(1)</script>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start + "</svg><script>alert(1)</script>" + start + "</svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start + "</svg>trailing text", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(String(start.dropLast()) + "/><script>alert(1)</script></svg>", expectedID: "page-0"))
        XCTAssertThrowsError(try ValidatedSVG(start + "<path xmlns:xlink=\"http://www.w3.org/1999/xlink\" xlink:href=\"https://evil.test/a\"/></svg>", expectedID: "page-0"))
    }
}
