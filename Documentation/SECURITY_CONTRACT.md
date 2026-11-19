# Security and resource contract

This contract describes the intended security boundary of the SwiftMD 1.0
release candidate and its optional adapters. It applies only to the identified
implementation and configuration; an application remains responsible for its
deployment environment and the way it displays the output.

## Inputs and trusted configuration

Markdown, language labels, code, TeX and diagram text can be attacker supplied.
Renderer implementations, JavaScript resources, Node executables and module
paths, the process environment, caller-selected configuration and the host page's
HTML/CSS are trusted. The Node process inherits its environment; variables such
as `NODE_OPTIONS` must therefore be controlled by the caller. Never expose
renderer scripts, executable paths or module paths as untrusted input.

The standard Core path returns SwiftGFM's exact HTML bytes for the same
configuration. Enabling block renderers selects a separate structured HTML
profile with different serialization. This profile processes matching
`pre > code` elements, including author-supplied raw HTML when that HTML is
enabled. It does not establish whether an element came from a Markdown fence.
Custom `BlockRenderer` implementations and their HTML replacements are trusted.

## HTML output

SwiftMD is **not an HTML sanitizer**. Raw HTML and unsafe links require an
explicit option; enabling them is not sanitization. An application must apply
an appropriate HTML security policy at its own output boundary, including when
an enabled extension or the host page supplies HTML or CSS. Do not assume the
SVG checks make arbitrary surrounding HTML safe.

The bundled Pele integration disables links and images and accepts only SVG
that passes the narrow `ValidatedSVG` XML, element, attribute, CSS and ID
policy. Validated SVG is embedded byte for byte after HTML serialization. This
policy is not a general SVG sanitizer or a proof against every browser-parser
difference. It does not isolate the result from the host's CSS. Provide a
distinct SVG prefix for each separately compiled fragment on the same page.
KaTeX uses `trust: false`, MathML output and strict error handling; renderer
code itself remains trusted. Renderer failures preserve the source block and
produce a diagnostic. Applications must inspect diagnostics; strict CLI mode
fails without emitting HTML on block diagnostics.

## Resource and execution boundary

The individual KaTeX and Pele inputs are limited to 16,384 UTF-8 bytes. Their
outputs are checked against 2,000,000 bytes **after** the renderer has produced
them; this is not a live memory, disk or CPU bound. The limit does not bound the
full Markdown document, syntax highlighting, the parser or cumulative work
across blocks. Neither bundled backend enforces a hard execution deadline or
aggregate memory cap. JavaScriptCore runs in-process on Apple platforms; task
cancellation does not terminate synchronous JavaScript.

Consequently, the one-call API alone is not an availability or tenant-isolation
boundary for hostile documents. A service handling such inputs must use a
separately configured and tested process/OS isolation policy with appropriate
time, memory, output, filesystem, network and credential restrictions. The
optional Linux systemd/cgroup worker has the specific prerequisites and
remaining gaps described in [PROCESS_ISOLATION.md](PROCESS_ISOLATION.md). It is
not enabled automatically and does not establish equivalent protection on
Apple platforms. A process-local timeout or per-process limit alone is not an
aggregate sandbox.

## Evidence and limits

Tests exercise real renderers, malicious SVG constructs, fallback behavior,
the independent C backend and selected browser behavior. Separate automated
CodeQL analysis checks the critical Swift and Python sources. These checks are
not a penetration test, legal clearance, general sanitizer certification or a
guarantee against undiscovered vulnerabilities. See the
[source repository's security and license review](https://github.com/ThorFuchs/Swift-MD/blob/main/Documentation/SECURITY_LICENSE_REVIEW.md)
for the evidence and release-specific open questions.
