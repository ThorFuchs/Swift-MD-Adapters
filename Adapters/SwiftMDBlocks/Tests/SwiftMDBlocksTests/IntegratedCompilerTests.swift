// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import SwiftMD
import SwiftMDCompiler

final class IntegratedCompilerTests: XCTestCase {
    func testDisabledExtensionsPreserveCoreBytes() throws {
        let source = "# Test\n\n```swift\nlet value = 1\n```\n"
        let result = try SwiftMDRenderer(highlight: false).render(source)
        XCTAssertEqual(result.html, try MarkdownCompiler().render(source).html)
        XCTAssertTrue(result.diagnostics.isEmpty)
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
        let source = "| A | B |\n| - | - |\n| x | y |\n\n```swift\nlet x = 1\n```\n\n```math\nx^2\n```\n\n```mermaid\nflowchart LR\nA-->B\n```\n"
        let result = try renderer.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        for marker in ["<table>", "hljs-keyword", "<math", "<svg", "viewBox=", "id=\"integrated-2\""] {
            XCTAssertTrue(result.html.contains(marker), marker)
        }
        let failure = try renderer.render("```math\n\\badcommand{<script>}\n```\n")
        XCTAssertEqual(failure.diagnostics.count, 1)
        XCTAssertTrue(failure.html.contains("&lt;script&gt;"))
        XCTAssertFalse(failure.html.contains("<script>"))
    }

    func testRejectsUntrustedPathShapesAndInvalidPrefix() {
        XCTAssertThrowsError(try SwiftMDRenderer(math: NodeModule(node: "node", module: "/tmp/module")))
        XCTAssertThrowsError(try SwiftMDRenderer(mermaid: MermaidOptions(runtime: NodeModule(node: "/usr/bin/node", module: "/tmp/module"), svgPrefix: "bad prefix")))
    }
}
