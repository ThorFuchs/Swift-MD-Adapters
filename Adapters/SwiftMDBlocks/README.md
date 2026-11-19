# Experimental block adapters

The local `SwiftMDCompiler` product provides a unified API over the existing
renderers. Node and module paths must be explicitly supplied as trusted
absolute paths; install the pinned modules with `npm ci --ignore-scripts` in
`Tools/NodeDependencies`. No adapter mirror has been published yet.

```swift
import SwiftMDCompiler

let renderer = try SwiftMDRenderer(
    math: NodeModule(node: "/trusted/path/to/node", module: "/trusted/path/to/katex"),
    mermaid: MermaidOptions(
        runtime: NodeModule(node: "/trusted/path/to/node", module: "/trusted/path/to/pele/dist/pele.js"),
        svgPrefix: "unique-page-id"
    )
)
let result = try renderer.render(markdown)
print(result.html)
for diagnostic in result.diagnostics { print(diagnostic.message) }
```

Highlighting is enabled by default; pass `highlight: false` to turn it off.
Math and Mermaid are enabled independently by supplying their configuration.
With all three disabled, output is byte-identical to the core. Renderer errors
produce diagnostics and preserve escaped source; check diagnostics rather than
assuming every requested block rendered successfully. Prefixes must be unique
across all fragments placed on the same HTML page.

The separate `SwiftMDJavaScriptCore` product is an experimental Apple backend.
It runs trusted KaTeX and Pele scripts in JavaScriptCore without Node or a
WebView and uses the same SVG validator and fallback policy. Supply the KaTeX
UMD build and Pele global build explicitly. In-process JavaScript has no hard
deadline or memory cap; cancellation does not stop a synchronous JavaScript
call. The backend and the caller must not be treated as a sandbox.

The mirror generator's `--include-locked-renderers` option prepares an
experimental `SwiftMDBundled` product: it downloads the npm archives pinned in
the source lockfile, verifies their integrity, embeds the selected unchanged
renderer files and licenses as SwiftPM resources, and records their hashes and
provenance. This does not check generated dependencies into the source repo.
It is not yet a published package. Apple hosts use JavaScriptCore; Linux still
requires a trusted absolute Node executable. The embedded artifact and its
complete third-party notices must be reviewed before any distribution release.

`SwiftMDBlocks` is an opt-in HTML profile: it parses and reserializes the
SwiftGFM HTML with SwiftSoup and processes matching `pre > code` elements.
With no renderers it bypasses parsing and returns the exact core bytes. Source
provenance cannot be established from HTML, so author-written matching raw HTML
is processed too. Nested non-text code content is retained with a diagnostic.
This profile does not sanitize Markdown or raw HTML. A trusted renderer is a
trust boundary. Renderers run in registration order and the first match wins;
errors preserve the original escaped code and return a diagnostic.

`SwiftMDHighlight` reserves `math` and `mermaid`, validates the highlighter's
UTF-16 token ranges and source identity, and serializes its own calls. Its lock
does not coordinate independent Swift-Highlight users. Version 1.0.1 has
targeted Linux Thread Sanitizer coverage; that is not proof of blanket race
freedom. Highlighting has no hard execution time limit.

`SwiftMDKaTeXNode` accepts `math` fences. It uses JSON over stdin, KaTeX's
MathML-only display mode, `trust: false`, strict errors, `maxExpand: 500` and
`maxSize: 10`. `SwiftMDPeleNode` accepts `mermaid` fences, disables links and
images, fixes the Gantt clock and derives IDs from a caller-specified page-unique
prefix and block index. SVG is accepted only through a deliberately restrictive
XML, element, attribute and CSS allowlist, and inserted byte for byte after
validation. Presentation values use a restricted CSS grammar that rejects
escapes, comments, URLs and unknown functions; geometry attributes use narrow
numeric grammars. The only permitted internal references are root ARIA links
to uniquely named, direct-child `title` and `desc` elements for that block.
Unknown constructs and other references are rejected, preserving the original
block. Validation rejects fragments over 2,000,000 UTF-8 bytes. The allowlist and Pele filtering are not a general SVG sanitizer
or a security audit; host CSS and raw HTML remain separate trust boundaries.

The Node executable, module path and inherited process environment are trusted
configuration; `NODE_OPTIONS` can preload code before the renderer. Both
adapters reject input above 16,384 UTF-8 bytes and check output size after
process exit. The Swift read is also bounded if the output file grows after its
metadata check. This does not prevent a child from continuing to write to disk.
They do **not** themselves enforce a hard time, memory, disk or live output limit.
On Linux, `Scripts/run-linux-constrained.sh` is an optional outer worker: GNU
`timeout` kills the process group at a deadline and `prlimit` applies address-space
and individual file-size limits to each process. This limits the CLI and its Node
children, not their aggregate memory, and descendants that leave the process group
can escape the timeout. A deadline kills the whole worker, so it cannot return
block diagnostics and may leave temporary files. It is not a sandbox. V8 reserves virtual address space,
so too-small address-space limits can prevent Node from starting. Use cgroups and
an OS sandbox for aggregate memory and stronger isolation.
The optional package currently resolves Swift-Highlight even for other products;
the root Core package avoids that dependency. Swift-Highlight is pinned to its
public 1.0.1 tag (commit 71d23c52a4afe154acdcc3b8aee968f0bf1b8564). SwiftPM remote adapter distribution is not yet
available. No `$$` or inline mathematics is implemented.
