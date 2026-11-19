# Third-party notices

Swift-Highlight contains HighlightKit by Phrase (MIT), revision
`524c185b0553756498c1b6a1765e8d119c4623a6`. The complete original
license is in `Licenses/HighlightKit-MIT.txt`. HighlightKit ports
highlight.js 11.11.1, commit `08cb242e7d4aee787114eb04cc7ab18314d82f92`.
Its engine semantics, language grammars, fixtures and GitHub themes derive
from highlight.js. Its full BSD-3-Clause license is in
`Licenses/highlight.js-BSD-3-Clause.txt`. The Xcode themes originated in
HighlightKit; adaptive variants remain included. Both notices and license
texts must accompany source and binary distributions. The Apache-2.0 root
license applies to new project contributions, not as a replacement for the
licenses of imported material.

The original 1.0.0 fixture corpus was imported from HighlightKit. A byte-level
inventory against the pinned highlight.js checkout found 354 exact matches and
21 files without exact matches. Fifteen of those have high textual similarity
to a reference fixture and two extend a reference fixture. The remaining four
are byte-identical to files from later highlight.js commits, each with the same
BSD-3-Clause root license; exact revisions appear in
`Documentation/FIXTURE-PROVENANCE.md`. Similarity does not prove attribution.
Exact matches do not by themselves prove ownership of all contributed material.

After 1.0.0, `erlang/sigil.code.txt`, `erlang/triple_quote_string.code.txt`,
and `xml/document-type-variations.code.txt` were changed to use neutral example
text in place of the identified quotations and named example. Their syntax
coverage remains checked against the pinned highlight.js reference. The 1.0.0
tag and imported Git history still contain the original material, including
attributed quotations and the named example. Those earlier copies were traced
to the pinned HighlightKit and highlight.js fixtures; this does not establish
additional rights in their contents or constitute a completed legal review.
