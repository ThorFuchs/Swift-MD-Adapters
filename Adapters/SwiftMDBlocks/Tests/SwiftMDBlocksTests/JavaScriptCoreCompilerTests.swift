// SPDX-License-Identifier: Apache-2.0
#if canImport(JavaScriptCore)
import Foundation
import XCTest
import SwiftMD
import SwiftMDCompiler
import SwiftMDJavaScriptCore

final class JavaScriptCoreCompilerTests: XCTestCase {
    func scripts() throws -> (String, String) {
        let env = ProcessInfo.processInfo.environment
        guard let katex = env["SWIFTMD_KATEX_JS"], let pele = env["SWIFTMD_PELE_GLOBAL_JS"] else {
            throw XCTSkip("Set SWIFTMD_KATEX_JS and SWIFTMD_PELE_GLOBAL_JS to the real bundled scripts")
        }
        return (try String(contentsOfFile: katex, encoding: .utf8), try String(contentsOfFile: pele, encoding: .utf8))
    }

    func testNoExtensionsPreservesCore() throws {
        let source = "# Hello\n\n```math\nx^2\n```\n"
        let result = try SwiftMDAppleRenderer(highlight: false).render(source)
        XCTAssertEqual(result.html, try MarkdownCompiler().render(source).html)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testCombinedAndFallbackWithRealScripts() throws {
        let (katex, pele) = try scripts()
        let renderer = try SwiftMDAppleRenderer(katexScript: katex, peleScript: pele, svgPrefix: "apple-page")
        let source = "| A | B |\n| - | - |\n| x | y |\n\n```swift\nlet x = 1\n```\n\n```math\nx^2\n```\n\n```mermaid\nflowchart LR\nA-->B\n```\n"
        let result = try renderer.render(source)
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result.diagnostics)")
        for marker in ["<table>", "hljs-keyword", "<math", "<svg", "viewBox=", "id=\"apple-page-2\""] {
            XCTAssertTrue(result.html.contains(marker), marker)
        }
        let failed = try renderer.render("```math\n\\badcommand{<script>}\n```\n")
        XCTAssertEqual(failed.diagnostics.count, 1)
        XCTAssertTrue(failed.html.contains("&lt;script&gt;"))
        XCTAssertFalse(failed.html.contains("<script>"))
    }

    func testInvalidScriptAndPrefixRejected() throws {
        let (_, pele) = try scripts()
        XCTAssertThrowsError(try SwiftMDAppleRenderer(katexScript: ")"))
        XCTAssertThrowsError(try SwiftMDAppleRenderer(peleScript: pele, svgPrefix: "bad prefix"))
    }

    func testRealDiagramTypesAndStableIDs() throws {
        let (_, pele) = try scripts()
        let renderer = try SwiftMDAppleRenderer(highlight: false, peleScript: pele, svgPrefix: "apple-test")
        let samples = ["flowchart LR\nA-->B", "sequenceDiagram\nAlice->>Bob: Hello", "classDiagram\nA <|-- B", "stateDiagram-v2\n[*] --> Active", "erDiagram\nUSER ||--o{ POST : writes", "gantt\n title A\n dateFormat YYYY-MM-DD\n section X\n Task :a, 2020-01-01, 2d", "pie\n \"A\" : 2\n \"B\" : 3", "mindmap\n  root((Root))\n    Child"]
        for sample in samples {
            let result = try renderer.render("```mermaid\n\(sample)\n```\n")
            XCTAssertTrue(result.diagnostics.isEmpty, "\(sample): \(result.diagnostics)")
            XCTAssertTrue(result.html.contains("<svg"), sample)
        }
        let block = "```mermaid\nflowchart LR\naccTitle: Diagram\naccDescr: Two nodes\nA-->B\n```\n"
        let first = try renderer.render(block + "\n" + block)
        XCTAssertTrue(first.diagnostics.isEmpty, "\(first.diagnostics)")
        XCTAssertTrue(first.html.contains("id=\"apple-test-0\""))
        XCTAssertTrue(first.html.contains("id=\"apple-test-1\""))
        XCTAssertEqual(first.html, try renderer.render(block + "\n" + block).html)
    }

    func testNodeAndJavaScriptCoreProduceSameCombinedHTML() throws {
        let (katex, pele) = try scripts()
        let env = ProcessInfo.processInfo.environment
        guard let node = env["SWIFTMD_NODE"], let katexModule = env["SWIFTMD_KATEX"], let peleModule = env["SWIFTMD_PELE"] else {
            throw XCTSkip("Set real Node renderer paths for cross-backend comparison")
        }
        let source = "```swift\nlet value = 1\n```\n\n```math\nx^2\n```\n\n```mermaid\nflowchart LR\nA-->B\n```\n"
        let apple = try SwiftMDAppleRenderer(katexScript: katex, peleScript: pele, svgPrefix: "same-page").render(source)
        let nodeResult = try SwiftMDRenderer(math: NodeModule(node: node, module: katexModule), mermaid: MermaidOptions(runtime: NodeModule(node: node, module: peleModule), svgPrefix: "same-page")).render(source)
        XCTAssertTrue(apple.diagnostics.isEmpty && nodeResult.diagnostics.isEmpty)
        XCTAssertEqual(apple.html, nodeResult.html)
    }

    func testConcurrentUseOfOneJavaScriptCoreRenderer() async throws {
        let (katex, pele) = try scripts()
        let renderer = try SwiftMDAppleRenderer(katexScript: katex, peleScript: pele, svgPrefix: "concurrent")
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for number in 0..<12 {
                group.addTask {
                    let result = try renderer.render("```math\nx_\(number)^2\n```\n\n```mermaid\nflowchart LR\nA-->B\n```\n")
                    return result.diagnostics.isEmpty && result.html.contains("<math") && result.html.contains("id=\"concurrent-1\"")
                }
            }
            for try await passed in group { XCTAssertTrue(passed) }
        }
    }
}
#endif
