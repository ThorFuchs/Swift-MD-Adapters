# SwiftMD adapters

This package is generated from a committed SwiftMD source revision. Do not edit
the mirror directly; develop and report issues in the SwiftMD source repository.
`MIRROR-ORIGIN.json` records the revision, dependency versions and, when
bundled, renderer-archive integrity and file hashes.

Add the mirror to a Swift package with:

```swift
.package(url: "https://github.com/ThorFuchs/Swift-MD-Adapters.git", from: "1.0.0")
```

Add `.product(name: "SwiftMDBundled", package: "Swift-MD-Adapters")` to the
target's dependencies. The source repository remains SwiftMD; mirror releases
are generated from its reviewed commits.

When generated with `--include-locked-renderers`, the `SwiftMDBundled` product
provides a single entry point:

```swift
import SwiftMDBundled

let result = try SwiftMDIntegrated.render(
    markdown,
    svgPrefix: "unique-page-id",
    nodeExecutable: "/trusted/path/to/node" // Linux only; omit on Apple
)
print(result.html)
for diagnostic in result.diagnostics { print(diagnostic.message) }
```

SwiftPM resolves the Swift dependencies and supplies the pinned KaTeX and Pele
scripts as package resources. Apple platforms run those scripts in
JavaScriptCore; Linux needs a separately installed trusted Node executable.
SwiftSoup library sources are included as the internal `SwiftMDSoup` module,
without the upstream test fixtures; the accompanying MIT and jsoup license
notices are included with the package.
MathML and SVG are precomputed and need no client-side JavaScript to display.
Highlighting supplies classes; the host supplies CSS.

`math` and `mermaid` code fences enable the renderers. Inline and `$$` math are
not implemented. Give each separately rendered fragment on a page a distinct
prefix. Check diagnostics; failed blocks retain escaped source. Raw HTML and
third-party renderer output are trust boundaries, and SVG validation is not a
general sanitizer. Neither backend enforces a hard deadline or aggregate memory
cap. See `Documentation/PROCESS_ISOLATION.md` in the source repository.
The [security and resource contract](Documentation/SECURITY_CONTRACT.md)
describes the required trust and deployment boundaries.

The source, bundled scripts and third-party licenses require review before
publishing a mirror. A mirror marked `local_test_only` is never publishable.
