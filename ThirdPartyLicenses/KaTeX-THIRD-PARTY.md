# Notices identified in the bundled KaTeX 0.19.1 renderer

The original `dist/katex.js` from the locked npm archive retains the following
upstream attribution in its source comments:

* `src/utils.ts` identifies its `hyphenate` and `escape` functions as adapted
  from Facebook's React under Apache License 2.0. A copy of that license is in
  `SwiftGFM-Apache-2.0.txt` (also available as `Apache-2.0.txt` alongside the
  bundled renderer resource).
* The `src/stretchy.ts` comments identify SVG images adapted from glyphs in
  KaTeX fonts and identify the following copyright holders:
  Copyright (c) 2009–2010 Design Science, Inc. (www.mathjax.org), and
  Copyright (c) 2014–2017 Khan Academy (www.khanacademy.org). The comments
  identify the SIL Open Font License, Version 1.1. Its text is retained as
  `KaTeX-SIL-OFL-1.1.txt`.

The SIL license text is copied verbatim from the SPDX license-list-data
repository at commit `ab9b0904b43db6f4b67431efd8821feb821f1c8b`, file
`text/OFL-1.1.txt`; SHA-256:
`8eea8287e5876b539670cadb82e99f9a7afddec6f6730811be1daf25d2e9bcfd`.
The license steward's official text is at
https://openfontlicense.org/documents/OFL.txt.

This records source evidence, not a legal opinion or proof that all notices
for every transitive component have been identified. Review the complete
distributed artifacts before publishing a mirror.
