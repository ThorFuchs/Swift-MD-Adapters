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
| SwiftGFM | 1.0.1, tag commit 2cb9450cf755858d338525fe64081b5f04864a2d | Apache-2.0; see SwiftGFM-NOTICE.txt and cmark-gfm-COPYING.txt |
| cmark-gfm | 27d942c8b0a62d192f616e5bf3578f4b6a89e180 | See cmark-gfm-COPYING.txt; fixtures have separate CC BY-SA notice |
| Swift-Highlight | 1.0.1, tag commit 71d23c52a4afe154acdcc3b8aee968f0bf1b8564 | Apache-2.0; imported HighlightKit MIT and highlight.js BSD-3-Clause, see included notices |
| SwiftSoup | d86f244ed497d48012782e2f59c985a55e77b3f5 (2.11.3) | Vendored library source without fixtures, MIT; jsoup MIT reference notice retained; see SwiftSoup-SOURCE-AUDIT.md |
| LRUCache | 1.3.0 | MIT |
| swift-atomics | 1.3.1 | Apache-2.0 |
| KaTeX | npm 0.19.1 | MIT; the renderer also identifies React adaptations under Apache-2.0 and glyph-derived SVG material under SIL OFL 1.1; see KaTeX-THIRD-PARTY.md |
| Pele | npm 1.13.0 | MIT, with Lucide ISC notice, esbuild MIT runtime helpers, lexer rules ported from Mermaid, and d3-related Gantt behavior; see Pele-THIRD-PARTY.md |
| commander | npm 15.1.0 | MIT |

Swift-Highlight 1.0.1 replaces identified fixture quotations and a named
example with neutral text. Its 1.0.0 tag and Git history still contain the
originals. Fixture provenance and rights in imported material still require
review before distribution; see the included upstream third-party notice.
