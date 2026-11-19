// SPDX-License-Identifier: Apache-2.0
#if os(macOS) || os(Linux)
import Foundation
import SwiftMDBlocks
import SwiftMDKaTeXNode

public struct PeleNodeRenderer: BlockRenderer {
    public let node: String, module: String, prefix: String
    public init(node: String, module: String, prefix: String) throws {
        guard node.hasPrefix("/"), module.hasPrefix("/") else { throw NodeRendererError.absolutePathsRequired }
        guard !prefix.isEmpty, prefix.utf8.count <= 64, prefix.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw NodeRendererError.invalidOutput }
        self.node = node; self.module = module; self.prefix = prefix
    }
    public func accepts(language: String) -> Bool { language == "mermaid" }
    public func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
        guard literal.utf8.count <= 16_384 else { throw NodeRendererError.inputTooLarge }
        let id = "\(prefix)-\(index)"
        let script = #"""
        const fs = require('node:fs'); const {pathToFileURL} = require('node:url');
        const input = JSON.parse(fs.readFileSync(0, 'utf8'));
        (async () => {
          const pele = await import(pathToFileURL(input.module).href);
          const result = pele.render(input.text, {idPrefix: input.id, links:false, images:false, now: new Date('2020-01-01T00:00:00Z')});
          if (!result.svg.startsWith('<svg ')) throw new Error('Missing SVG root');
          process.stdout.write(result.svg.replace('<svg ', '<svg id="' + input.id + '" '));
        })().catch(e => { console.error(String(e)); process.exitCode=1 });
        """#
        let svg = try NodeProcess.run(node: node, script: script, request: ["module": module, "text": literal, "id": id])
        return .validatedSVG(try ValidatedSVG(svg, expectedID: id))
    }
}
#endif
