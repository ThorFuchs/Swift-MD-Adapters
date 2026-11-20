// SPDX-License-Identifier: Apache-2.0
// This target is built only by a mirror generated with --include-locked-renderers.
import Foundation
import SwiftMDBlocks
#if canImport(JavaScriptCore)
import SwiftMDJavaScriptCore
#elseif os(Linux)
import SwiftMDCompiler
#endif

public enum IntegratedRendererError: Error, Sendable {
    case missingResource(String)
    case nodeExecutableRequired
    case unsupportedPlatform
}

/// A convenience entry point using locked, bundled KaTeX and Pele scripts.
///
/// Apple platforms use JavaScriptCore. Linux requires an explicitly supplied,
/// trusted absolute Node executable. These backends execute code at compile
/// time and do not provide hard time or memory limits. `svgPrefix` must be
/// unique across all fragments placed on a page. Diagnostics must be checked.
/// `recognizeMath` separately opts in to dollar-delimited Markdown mathematics.
public struct SwiftMDIntegrated: Sendable {
    private let renderImpl: @Sendable (String) throws -> BlockResult

    /// Reuse only for documents on separate pages: a shared prefix causes ID
    /// collisions if multiple results are placed on the same page.
    public init(svgPrefix: String, nodeExecutable: String? = nil, recognizeMath: Bool = false) throws {
        #if canImport(JavaScriptCore)
        let katex = try String(contentsOf: Self.resource("katex", "cjs"), encoding: .utf8)
        let pele = try String(contentsOf: Self.resource("pele.global", "js"), encoding: .utf8)
        let renderer = try SwiftMDAppleRenderer(katexScript: katex, peleScript: pele, svgPrefix: svgPrefix, recognizeMath: recognizeMath)
        renderImpl = { try renderer.render($0) }
        #elseif os(Linux)
        guard let nodeExecutable else { throw IntegratedRendererError.nodeExecutableRequired }
        let katex = try Self.resource("katex", "cjs").path
        let pele = try Self.resource("pele", "mjs").path
        let renderer = try SwiftMDRenderer(math: NodeModule(node: nodeExecutable, module: katex),
                                           mermaid: MermaidOptions(runtime: NodeModule(node: nodeExecutable, module: pele), svgPrefix: svgPrefix),
                                           recognizeMath: recognizeMath)
        renderImpl = { try renderer.render($0) }
        #else
        throw IntegratedRendererError.unsupportedPlatform
        #endif
    }

    public func render(_ markdown: String) throws -> BlockResult { try renderImpl(markdown) }

    /// Compile a single document without retaining a renderer instance.
    public static func render(_ markdown: String, svgPrefix: String, nodeExecutable: String? = nil, recognizeMath: Bool = false) throws -> BlockResult {
        try SwiftMDIntegrated(svgPrefix: svgPrefix, nodeExecutable: nodeExecutable, recognizeMath: recognizeMath).render(markdown)
    }

    private static func resource(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "RendererAssets") else {
            throw IntegratedRendererError.missingResource("\(name).\(ext)")
        }
        return url
    }
}
