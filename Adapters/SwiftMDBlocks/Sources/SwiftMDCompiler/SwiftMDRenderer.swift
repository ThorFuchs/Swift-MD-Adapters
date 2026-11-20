// SPDX-License-Identifier: Apache-2.0
#if os(macOS) || os(Linux)
import SwiftGFM
import SwiftMD
import SwiftMDBlocks
import SwiftMDHighlight
import SwiftMDKaTeXNode
import SwiftMDPeleNode

/// Explicit, trusted paths for a locally installed Node module.
public struct NodeModule: Sendable {
    public let node: String
    public let module: String

    public init(node: String, module: String) {
        self.node = node
        self.module = module
    }
}

/// Mermaid configuration. The prefix must be unique across a composed HTML page.
public struct MermaidOptions: Sendable {
    public let runtime: NodeModule
    public let svgPrefix: String

    public init(runtime: NodeModule, svgPrefix: String) {
        self.runtime = runtime
        self.svgPrefix = svgPrefix
    }
}

/// Combines optional renderers with SwiftMD's baseline compiler.
///
/// The extended profile processes HTML and may serialize it differently. When
/// all renderers are disabled, the baseline SwiftGFM bytes are preserved.
/// Renderer failures retain the original escaped block and produce diagnostics.
/// Node and module paths are trusted configuration; Node is not sandboxed.
/// Dollar-delimited Markdown math is separately enabled with `recognizeMath`;
/// enabling it requires a configured math renderer.
public struct SwiftMDRenderer: Sendable {
    private let compiler: BlockCompiler
    private let mathRenderer: KaTeXNodeRenderer?

    public init(
        configuration: MarkdownConfiguration = .gfm,
        highlight: Bool = true,
        math: NodeModule? = nil,
        mermaid: MermaidOptions? = nil,
        recognizeMath: Bool = false
    ) throws {
        guard !recognizeMath || math != nil else { throw MarkdownMathConfigurationError.rendererRequired }
        var renderers: [any BlockRenderer] = []
        var selectedMathRenderer: KaTeXNodeRenderer?
        if let math {
            let renderer = try KaTeXNodeRenderer(node: math.node, module: math.module)
            renderers.append(renderer)
            if recognizeMath { selectedMathRenderer = renderer }
        }
        if let mermaid {
            renderers.append(try PeleNodeRenderer(node: mermaid.runtime.node, module: mermaid.runtime.module, prefix: mermaid.svgPrefix))
        }
        if highlight { renderers.append(HighlightRenderer()) }
        compiler = BlockCompiler(compiler: MarkdownCompiler(configuration: configuration), renderers: renderers)
        self.mathRenderer = selectedMathRenderer
    }

    /// Compile Markdown to HTML and diagnostics in one call.
    public func render(_ markdown: String) throws -> BlockResult {
        if let mathRenderer { return try compiler.renderRecognizingMath(markdown, mathRenderer: mathRenderer) }
        return try compiler.render(markdown)
    }
}
#endif
