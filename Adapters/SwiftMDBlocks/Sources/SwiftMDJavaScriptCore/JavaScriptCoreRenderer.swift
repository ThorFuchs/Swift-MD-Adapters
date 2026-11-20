// SPDX-License-Identifier: Apache-2.0
#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import SwiftGFM
import SwiftMD
import SwiftMDBlocks
import SwiftMDHighlight

/// Errors from a trusted JavaScriptCore renderer configuration or execution.
public enum JavaScriptCoreRendererError: Error, Sendable {
    case unavailable, invalidScript, invalidPrefix, inputTooLarge, outputTooLarge, invalidOutput
    case execution(String)
}

/// A context is only accessed under its lock. Scripts are trusted configuration;
/// Markdown and TeX are passed as call arguments, never interpolated into code.
private final class Runtime: @unchecked Sendable {
    private let lock = NSLock()
    private let context: JSContext
    private let function: JSValue

    init(script: String, wrapper: String) throws {
        guard let context = JSContext() else { throw JavaScriptCoreRendererError.unavailable }
        context.evaluateScript(script)
        guard context.exception == nil else { throw JavaScriptCoreRendererError.invalidScript }
        guard let function = context.evaluateScript(wrapper), context.exception == nil, !function.isUndefined else {
            throw JavaScriptCoreRendererError.invalidScript
        }
        self.context = context
        self.function = function
    }

    func call(_ arguments: [Any]) throws -> String {
        try lock.withLock {
            context.exception = nil
            let value = function.call(withArguments: arguments)
            if let error = context.exception { throw JavaScriptCoreRendererError.execution(error.toString()) }
            guard let value, value.isString, let output = value.toString(), !output.isEmpty else {
                throw JavaScriptCoreRendererError.invalidOutput
            }
            guard output.utf8.count <= 2_000_000 else { throw JavaScriptCoreRendererError.outputTooLarge }
            return output
        }
    }
}

/// Renders TeX with a caller-supplied, trusted KaTeX JavaScript bundle.
/// This does not parse Markdown delimiters or enforce a hard runtime limit.
public struct KaTeXJavaScriptCoreRenderer: BlockRenderer, MathMLRenderer {
    private let runtime: Runtime
    public init(script: String) throws {
        let wrapper = #"""
        (function(tex, displayMode) { return katex.renderToString(tex, {output:'mathml',displayMode:displayMode,
        trust:false,throwOnError:true,strict:'error',maxExpand:500,maxSize:10}); })
        """#
        runtime = try Runtime(script: script, wrapper: wrapper)
    }
    public func accepts(language: String) -> Bool { language == "math" }
    public func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
        .blockHTML(try renderMath(literal: literal, displayMode: true))
    }
    /// Render TeX directly. Markdown delimiter recognition is not included.
    public func renderMath(literal: String, displayMode: Bool) throws -> String {
        guard literal.utf8.count <= 16_384 else { throw JavaScriptCoreRendererError.inputTooLarge }
        let html = try runtime.call([literal, displayMode])
        guard html.contains("<math") else { throw JavaScriptCoreRendererError.invalidOutput }
        return html
    }
}

private struct DiagramRenderer: BlockRenderer {
    let runtime: Runtime
    let prefix: String
    func accepts(language: String) -> Bool { language == "mermaid" }
    func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
        guard literal.utf8.count <= 16_384 else { throw JavaScriptCoreRendererError.inputTooLarge }
        let id = "\(prefix)-\(index)"
        var svg = try runtime.call([literal, id])
        guard svg.hasPrefix("<svg ") else { throw JavaScriptCoreRendererError.invalidOutput }
        svg.insert(contentsOf: "id=\"\(id)\" ", at: svg.index(svg.startIndex, offsetBy: 5))
        return .validatedSVG(try ValidatedSVG(svg, expectedID: id))
    }
}

/// Apple-platform compiler using trusted KaTeX and Pele scripts in JavaScriptCore.
///
/// The scripts must be supplied by the host and must be trusted. The optional
/// scripts are not downloaded by SwiftPM. JavaScriptCore runs in-process and
/// has no enforced deadline or memory cap here; do not mistake a task timeout
/// for termination of executing JavaScript. The SVG prefix must be unique on
/// the final composed page. Without renderers, core HTML bytes are preserved.
/// Dollar-delimited Markdown math requires `recognizeMath` and a KaTeX script.
public struct SwiftMDAppleRenderer: Sendable {
    private let compiler: BlockCompiler
    private let mathRenderer: KaTeXJavaScriptCoreRenderer?

    public init(configuration: MarkdownConfiguration = .gfm, highlight: Bool = true,
                katexScript: String? = nil, peleScript: String? = nil, svgPrefix: String? = nil,
                recognizeMath: Bool = false) throws {
        guard !recognizeMath || katexScript != nil else { throw MarkdownMathConfigurationError.rendererRequired }
        var renderers: [any BlockRenderer] = []
        var selectedMathRenderer: KaTeXJavaScriptCoreRenderer?
        if let katexScript {
            let renderer = try KaTeXJavaScriptCoreRenderer(script: katexScript)
            renderers.append(renderer)
            if recognizeMath { selectedMathRenderer = renderer }
        }
        if let peleScript {
            guard let prefix = svgPrefix, !prefix.isEmpty, prefix.utf8.count <= 64,
                  prefix.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
                throw JavaScriptCoreRendererError.invalidPrefix
            }
            let wrapper = #"""
            (function(source, id) { return pele.render(source, {idPrefix:id,links:false,images:false,
            now:new Date('2020-01-01T00:00:00Z')}).svg; })
            """#
            let runtime = try Runtime(script: peleScript, wrapper: wrapper)
            renderers.append(DiagramRenderer(runtime: runtime, prefix: prefix))
        } else if svgPrefix != nil {
            throw JavaScriptCoreRendererError.invalidPrefix
        }
        if highlight { renderers.append(HighlightRenderer()) }
        compiler = BlockCompiler(compiler: MarkdownCompiler(configuration: configuration), renderers: renderers)
        self.mathRenderer = selectedMathRenderer
    }

    /// Compile Markdown to HTML and per-block diagnostics.
    public func render(_ markdown: String) throws -> BlockResult {
        if let mathRenderer { return try compiler.renderRecognizingMath(markdown, mathRenderer: mathRenderer) }
        return try compiler.render(markdown)
    }
}
#endif
