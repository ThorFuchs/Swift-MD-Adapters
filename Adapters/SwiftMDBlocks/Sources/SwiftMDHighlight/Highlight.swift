// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftMDBlocks
import SwiftHighlight
import SwiftHighlightHTML

/// Uses the pinned Swift-Highlight implementation. Access through this adapter
/// is serialized because upstream currently reports concurrent grammar warnings.
public struct HighlightRenderer: BlockRenderer {
    private static let lock = NSLock()
    private static let highlighter = Highlighter()
    public init() {}
    public func accepts(language: String) -> Bool { language != "math" && language != "mermaid" }
    public func render(literal: String, language: String, index: Int) throws -> BlockReplacement {
        try Self.lock.withLock {
            let result = try Self.highlighter.highlightStrict(literal, as: language)
            return .codeHTML(try HTMLHighlightRenderer().render(literal, result: result))
        }
    }
}
