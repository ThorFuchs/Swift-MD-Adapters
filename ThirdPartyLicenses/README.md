# Dependency provenance and notices

The root and adapter `Package.resolved` and `Tools/NodeDependencies/package-lock.json`
are the source of exact dependency identities and npm integrity hashes. Copied
notices here do not replace review before distribution.

`SwiftGFM-NOTICE.txt` is the upstream notice, copied without changing its
original paths. In a SwiftMD archive its `Vendor/GitHubCMark/COPYING` reference
corresponds to `cmark-gfm-COPYING.txt` in this directory. SwiftMD's separately
retained cmark fixtures and published GFM snapshot are test material, with
provenance and CC BY-SA notices under `Tests/`; the candidate binary archive and
generated adapter mirror do not include those fixtures. Reassess the notices
and any fixture licensing whenever the distributed file set changes.

| Dependency | Selected identity | License / notes |
| --- | --- | --- |
| SwiftGFM | 1.1.0, tag commit 9a4176be3bda0953f4ddb91ec63de77d1ad230fa | Apache-2.0; see SwiftGFM-NOTICE.txt and cmark-gfm-COPYING.txt |
| cmark-gfm | 27d942c8b0a62d192f616e5bf3578f4b6a89e180 | See cmark-gfm-COPYING.txt; fixtures have separate CC BY-SA notice |
| Swift-Highlight | 1.0.1, tag commit 71d23c52a4afe154acdcc3b8aee968f0bf1b8564 | Apache-2.0; imported HighlightKit MIT and highlight.js BSD-3-Clause, see included notices |
| SwiftHTML | 0.1.1, public tag commit 54eb43255083dcfcb9beca6c519c56389e7baaa5 | Apache-2.0; see SwiftHTML-Apache-2.0.txt |
| SwiftSoup via SwiftHTML | 2.14.4, commit 8397a860c6955924b584c50c5265c6aac0970015 | Fixture-free source; MIT including jsoup notice in SwiftHTML-SwiftSoup-2.14.4-MIT.txt |
| LRUCache via SwiftSoup | Source vendored by SwiftSoup 2.14.4 | MIT, Copyright 2021 Nick Lockwood; see SwiftHTML-LRUCache-MIT.txt |
| SwiftSoup in released SwiftMD 1.0.0 | d86f244ed497d48012782e2f59c985a55e77b3f5 (2.11.3) | Historical released distribution; see SwiftSoup-SOURCE-AUDIT.md |
| KaTeX | npm 0.19.1 | MIT; the renderer also identifies React adaptations under Apache-2.0 and glyph-derived SVG material under SIL OFL 1.1; see KaTeX-THIRD-PARTY.md |
| Pele | npm 1.13.0 | MIT, with Lucide ISC notice, esbuild MIT runtime helpers, lexer rules ported from Mermaid, and d3-related Gantt behavior; see Pele-THIRD-PARTY.md |
| commander | npm 15.1.0 | MIT |

Swift-Highlight 1.0.1 replaces identified fixture quotations and a named
example with neutral text. Its 1.0.0 tag and Git history still contain the
originals. Fixture provenance and rights in imported material still require
review before distribution; see the included upstream third-party notice.
