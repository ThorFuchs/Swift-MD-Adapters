# SwiftMDDOCX (experimental)

This optional SwiftPM package projects the typed SwiftGFM AST to editable
WordprocessingML and an in-memory OPC ZIP. It does not change SwiftMD Core or
require Node, an HTML renderer, a browser, a zip executable, or Apple-only
frameworks. Word decides pagination. The adapter is a bounded spike, not a
complete GFM-to-Word converter or a compatibility certification.

```swift
import Foundation
import SwiftMDDOCX

let document = try DOCXExporter().render("# Hello\n\n**SwiftMD**")
try document.write(to: URL(fileURLWithPath: "example.docx"), options: .atomic)
// Or: DOCXStyle(paper: .letter, bodyFont: "Calibri", headingPageBreak: true)
```

The source package is `Adapters/SwiftMDDOCX`; the canonical adapter-mirror
generator includes its product for a future generated distribution. No mirror
or version containing this spike is published merely by building the source.
The adapter depends on SwiftGFM 1.0.1 and preserves its default GFM parsing.

Supported: paragraphs, soft and hard breaks (both become Word line breaks),
headings 1–6, bold, italic, strikethrough, inline and block code, blockquotes,
ordered/bullet/task lists, simple GFM tables, thematic breaks, A4/Letter, a
small style set, spacing and margins. `paragraphSpacingTwips`,
`listSpacingTwips`, and `tableCellPaddingTwips` configure paragraph spacing,
tight-list spacing, and table cell padding; loose lists use paragraph spacing.
Headings have a small fixed before/after spacing. Lists have independent
numbering and restart at the specified GFM start. Paragraphs and text remain
editable.

Links are rendered as editable visible text followed by their destination and,
when present, title; they are not active hyperlinks. A `math` or `mermaid`
code fence is clearly labelled as source and is not converted to MathML,
Office Math or a diagram. Other code fence info strings do not trigger syntax
highlighting. Images, raw HTML, custom nodes, footnotes, and unrecognized
nodes throw `DOCXError.unsupported` instead of silently losing content.
Blockquotes are indented; nested blockquotes share the same indentation. Text
layout, fonts, and line wrapping are determined by the opening application.

The package includes a Word settings part with compatibility mode `15`
(Word 2013 feature set). Without it, Word treats this export as a legacy
Word 2007-compatible document. This setting does not certify compatibility
with other Word versions or applications.

The ZIP writer implements only deterministic, uncompressed, non-ZIP64 entries
for the adapter's fixed internal part names. It performs no filesystem access.
An invalid style, an XML 1.0 forbidden character, excessive nesting, or an
archive beyond the non-ZIP64 limits throws rather than returning empty data.
It has no configurable input or memory budget: isolate or bound untrusted
inputs at the application boundary. A successful export is not a sanitization
claim, a security audit, or proof of compatibility with every Office version.

## Verification

```sh
swift build --package-path Adapters/SwiftMDDOCX
swift test --package-path Adapters/SwiftMDDOCX
SWIFTMDDOCX_TEST_OUTPUT=/tmp/swiftmd-example.docx swift test --package-path Adapters/SwiftMDDOCX --filter DOCXExporterTests/testFixtureStructureAndSemantics
python3 Scripts/check-docx-fixture.py /tmp/swiftmd-example.docx
```

The independently authored fixture covers Unicode, ordering, styles, lists,
tables, and code. The Python verifier uses the standard-library ZIP and XML
parsers to check CRCs, package parts and internal relationship targets.

## Reuse and provenance

The existing RhoeMarkdown writer and renderer were reviewed for architectural
context; they target a different model and use a `zip` subprocess with a silent
empty-data failure path. RhoeLiquid's ZIP/package types are coupled to its
broader framework and include an archive reader; RhoeLiquidKit also contains a
larger DOCX implementation. None of their source code or fixtures was copied.
The adapter and its test fixture are new SwiftMD source, under this repository's
Apache-2.0 license. SwiftGFM is an independent Apache-2.0 dependency. GitHub did not identify a license for the reviewed private Rhoe repositories.
Their source is not redistributed here; copying it would require a separate
provenance and licensing review.
