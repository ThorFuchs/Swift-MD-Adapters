// SPDX-License-Identifier: Apache-2.0
#if os(macOS) || os(Linux)
import Foundation
import SwiftMDBlocks

/// Runs the explicitly supplied, trusted Node executable and KaTeX installation.
/// This is not a sandbox: no execution-time or memory limit is enforced.
public struct KaTeXNodeRenderer: BlockRenderer {
    public let node: String
    public let module: String
    public init(node: String, module: String) throws {
        guard node.hasPrefix("/"), module.hasPrefix("/") else { throw NodeRendererError.absolutePathsRequired }
        self.node = node
        self.module = module
    }
    public func accepts(language: String) -> Bool { language == "math" }
    public func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
        guard literal.utf8.count <= 16_384 else { throw NodeRendererError.inputTooLarge }
        let script = #"""
        const fs = require('node:fs');
        const request = JSON.parse(fs.readFileSync(0, 'utf8'));
        const katex = require(request.module);
        process.stdout.write(katex.renderToString(request.text, {
          output:'mathml', displayMode:true, trust:false, throwOnError:true,
          strict:'error', maxExpand:500, maxSize:10
        }));
        """#
        let html = try NodeProcess.run(node: node, script: script, request: ["module": module, "text": literal])
        guard html.contains("<math"), !html.isEmpty else { throw NodeRendererError.invalidOutput }
        return .blockHTML(html)
    }
}

public enum NodeRendererError: Error { case absolutePathsRequired, inputTooLarge, outputTooLarge, invalidOutput, processFailed(String) }

/// Files rather than pipes avoid deadlocks when a renderer writes large output.
public enum NodeProcess {
    public static func run(node: String, script: String, request: [String: String]) throws -> String {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("swiftmd-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input"), output = dir.appendingPathComponent("output"), error = dir.appendingPathComponent("error")
        try JSONSerialization.data(withJSONObject: request).write(to: input)
        guard fm.createFile(atPath: output.path, contents: nil), fm.createFile(atPath: error.path, contents: nil) else { throw NodeRendererError.invalidOutput }
        let inputHandle = try FileHandle(forReadingFrom: input), outputHandle = try FileHandle(forWritingTo: output), errorHandle = try FileHandle(forWritingTo: error)
        defer { try? inputHandle.close(); try? outputHandle.close(); try? errorHandle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: node); process.arguments = ["-e", script]
        process.standardInput = inputHandle; process.standardOutput = outputHandle; process.standardError = errorHandle
        try process.run(); process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let reader = try FileHandle(forReadingFrom: error); defer { try? reader.close() }
            let data = try reader.read(upToCount: 4096) ?? Data(); throw NodeRendererError.processFailed(String(decoding: data, as: UTF8.self))
        }
        let size = try fm.attributesOfItem(atPath: output.path)[.size] as? NSNumber
        guard let size, size.intValue <= 2_000_000 else { throw NodeRendererError.outputTooLarge }
        // The file may grow after the metadata check (for example if a child
        // inherited stdout). Bound the bytes actually read into this process too.
        let reader = try FileHandle(forReadingFrom: output); defer { try? reader.close() }
        var data = Data()
        while data.count <= 2_000_000 {
            let remaining = 2_000_001 - data.count
            let chunk = try reader.read(upToCount: min(remaining, 65_536)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= 2_000_000 else { throw NodeRendererError.outputTooLarge }
        guard let result = String(data: data, encoding: .utf8) else { throw NodeRendererError.invalidOutput }
        return result
    }
}
#endif
