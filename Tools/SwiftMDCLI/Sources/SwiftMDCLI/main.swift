// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftMD
import SwiftGFM
import SwiftMDBlocks
import SwiftMDHighlight
import SwiftMDKaTeXNode
import SwiftMDPeleNode
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let message): return message } }
}
func writeError(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
func run() throws {
    var args = Array(CommandLine.arguments.dropFirst()), input: String?, output: String?
    var nodeK: String?, moduleK: String?, nodeP: String?, moduleP: String?, prefix: String?
    var highlight = false, document = false, strict = false, unsafe = false
    while !args.isEmpty {
        let arg = args.removeFirst()
        func value() throws -> String { guard !args.isEmpty else { throw CLIError.message("Missing value for \(arg)") }; return args.removeFirst() }
        switch arg {
        case "--help", "-h": print("Usage: swift-md [--highlight] [--katex-node PATH --katex-module PATH] [--pele-node PATH --pele-module PATH --svg-prefix ID] [--document] [--unsafe-html] [--strict] [--output PATH] [INPUT]"); return
        case "--version": print("SwiftMD 1.0.0; SwiftGFM 1.0.1 (2cb9450cf755858d338525fe64081b5f04864a2d); cmark-gfm \(MarkdownEngine.backendVersion) \(MarkdownEngine.backendRevision)"); return
        case "--output", "-o": output = try value()
        case "--katex-node": nodeK = try value()
        case "--katex-module": moduleK = try value()
        case "--pele-node": nodeP = try value()
        case "--pele-module": moduleP = try value()
        case "--svg-prefix": prefix = try value()
        case "--highlight": highlight = true
        case "--document": document = true
        case "--strict": strict = true
        case "--unsafe-html": unsafe = true
        default:
            guard !arg.hasPrefix("-"), input == nil else { throw CLIError.message("Unexpected argument: \(arg)") }; input = arg
        }
    }
    guard (nodeK == nil) == (moduleK == nil) else { throw CLIError.message("KaTeX requires --katex-node and --katex-module") }
    guard (nodeP == nil && moduleP == nil && prefix == nil) || (nodeP != nil && moduleP != nil && prefix != nil) else { throw CLIError.message("Pele requires --pele-node, --pele-module and --svg-prefix") }
    let bytes = try input.map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? FileHandle.standardInput.readToEnd() ?? Data()
    guard let source = String(data: bytes, encoding: .utf8) else { throw CLIError.message("Input must be valid UTF-8") }
    var renderers: [any BlockRenderer] = []
    if let nodeK, let moduleK { renderers.append(try KaTeXNodeRenderer(node: nodeK, module: moduleK)) }
    if let nodeP, let moduleP, let prefix { renderers.append(try PeleNodeRenderer(node: nodeP, module: moduleP, prefix: prefix)) }
    if highlight { renderers.append(HighlightRenderer()) }
    let config = MarkdownConfiguration(options: unsafe ? [.allowUnsafeHTML] : [])
    let result = try BlockCompiler(compiler: MarkdownCompiler(configuration: config), renderers: renderers).render(source)
    for diagnostic in result.diagnostics { writeError("block \(diagnostic.blockIndex) [\(diagnostic.language)]: \(diagnostic.message)") }
    if strict && !result.diagnostics.isEmpty { throw CLIError.message("Rendering failed in strict mode") }
    let html = document ? "<!doctype html>\n<html><head><meta charset=\"utf-8\"></head><body>\n" + result.html + "\n</body></html>\n" : result.html
    if let output { try Data(html.utf8).write(to: URL(fileURLWithPath: output), options: .atomic) }
    else { FileHandle.standardOutput.write(Data(html.utf8)) }
}
do { try run() } catch { writeError("swift-md: \(error)"); exit(1) }
