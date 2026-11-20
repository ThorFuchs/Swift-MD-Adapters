// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import SwiftMD
import SwiftMDCompiler
import SwiftMDBlocks

final class IntegratedCompilerTests: XCTestCase {
    func testDisabledExtensionsPreserveCoreBytes() throws {
        let samples = ["# Test\n\n```swift\nlet value = 1\n```\n",
                       "Inline $x^2$; price $5 and $10.\n\n$$\ny^2\n$$\n",
                       "`$code$` and \\$escaped\\$.\n\n```math\nx^2\n```\n"]
        let renderer = try SwiftMDRenderer(highlight: false)
        for source in samples {
            let result = try renderer.render(source)
            XCTAssertEqual(result.html, try MarkdownCompiler().render(source).html)
            XCTAssertTrue(result.diagnostics.isEmpty)
        }
    }

    func testRealCombinedRenderersAndFailureFallback() throws {
        let env = ProcessInfo.processInfo.environment
        guard let node = env["SWIFTMD_NODE"], let katex = env["SWIFTMD_KATEX"], let pele = env["SWIFTMD_PELE"] else {
            throw XCTSkip("Set SWIFTMD_NODE, SWIFTMD_KATEX and SWIFTMD_PELE for real renderer tests")
        }
        let renderer = try SwiftMDRenderer(
            math: NodeModule(node: node, module: katex),
            mermaid: MermaidOptions(runtime: NodeModule(node: node, module: pele), svgPrefix: "integrated")
        )
        let source = "Inline $x^2$ stays literal.\n\n| A | B |\n| - | - |\n| x | y |\n\n```swift\nlet x = 1\n```\n\n```math\nx^2\n```\n\n```mermaid\nflowchart LR\nA-->B\n```\n"
        let result = try renderer.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertTrue(result.html.contains("Inline $x^2$ stays literal."))
        for marker in ["<table>", "hljs-keyword", "<math", "<svg", "viewBox=", "id=\"integrated-2\""] {
            XCTAssertTrue(result.html.contains(marker), marker)
        }
        let failure = try renderer.render("```math\n\\badcommand{<script>}\n```\n")
        XCTAssertEqual(failure.diagnostics.count, 1)
        XCTAssertTrue(failure.html.contains("&lt;script&gt;"))
        XCTAssertFalse(failure.html.contains("<script>"))
    }

    func testRejectsUntrustedPathShapesAndInvalidPrefix() {
        XCTAssertThrowsError(try SwiftMDRenderer(recognizeMath: true)) { error in
            XCTAssertEqual(error as? MarkdownMathConfigurationError, .rendererRequired)
        }
        XCTAssertThrowsError(try SwiftMDRenderer(math: NodeModule(node: "node", module: "/tmp/module")))
        XCTAssertThrowsError(try SwiftMDRenderer(mermaid: MermaidOptions(runtime: NodeModule(node: "/usr/bin/node", module: "/tmp/module"), svgPrefix: "bad prefix")))
    }

    func testOptInMarkdownMathWithRealRenderers() throws {
        let env = ProcessInfo.processInfo.environment
        guard let node = env["SWIFTMD_NODE"], let katex = env["SWIFTMD_KATEX"], let pele = env["SWIFTMD_PELE"] else {
            throw XCTSkip("Set real Node, KaTeX and Pele paths")
        }
        let renderer = try SwiftMDRenderer(math: NodeModule(node: node, module: katex),
            mermaid: MermaidOptions(runtime: NodeModule(node: node, module: pele), svgPrefix: "math-document"), recognizeMath: true)
        let source = #"""
        | A | B |
        | - | - |
        | x | [link](https://example.com) |

        Inline $x^2$ and code `$no_math$`.

        $$
        \frac{x}{2}
        $$

        ```math
        y^2
        ```

        ```swift
        let x = 1
        ```

        ```mermaid
        flowchart LR
        A-->B
        ```
        """#
        let result = try renderer.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        XCTAssertEqual(result.html.components(separatedBy: "<math ").count - 1, 3)
        XCTAssertEqual(result.html.components(separatedBy: "display=\"block\"").count - 1, 2)
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("$no_math$"))
        XCTAssertTrue(result.html.contains("hljs-keyword"))
        XCTAssertTrue(result.html.contains("<svg"))
        XCTAssertFalse(result.html.contains("SWIFTGFMMATH"))
        let invalid = try renderer.render(#"Broken $\badcommand{<script>}$ here."#)
        XCTAssertEqual(invalid.diagnostics.count, 1)
        XCTAssertTrue(invalid.html.contains("&lt;script&gt;"))
        XCTAssertFalse(invalid.html.contains("<script>"))
    }
}
