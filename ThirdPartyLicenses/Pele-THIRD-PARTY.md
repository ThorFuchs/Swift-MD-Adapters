# Notices and build evidence for Pele 1.13.0

Pele's upstream `LICENSE` contains its MIT license and the ISC notice for the
Lucide icon; the unmodified text is in `Pele-MIT.txt` and is included alongside
the bundled resources.

On 18 November 2026, Pele's `1.13.0` tag was checked at commit
`3a2f075ee0c3d914f0fad3545fc0f193693975ac`. Using esbuild 0.28.2 from the
upstream lockfile and the upstream build settings, the ESM and IIFE files were
rebuilt byte-for-byte against the SHA-512-verified npm archive:

| File | SHA-256 |
| --- | --- |
| `dist/pele.js` | `37bea5005aa6d2dde929032ced5d2958cf642667cbc1fe675f9dfacf4ba15a51` |
| `dist/pele.global.js` | `0b0a46c57a5a6971670c09f5ec4066705bd78505f90fd11adf6260325efa0910` |

The macOS ARM64 esbuild binary came from the upstream-locked
`@esbuild/darwin-arm64@0.28.2` npm archive with integrity
`sha512-n4KqkOQrraxHJcgjM1RvwbigfQKIKJVpM7xp+KsxiyUSrRdIXnt73VhrPAx0fV44hgfmIVKjxMN9J1t5jySVkw==`.
From a disposable checkout of the pinned Pele commit, the equivalent commands are:

```sh
ESBUILD=/absolute/path/to/verified/esbuild
"$ESBUILD" src/index.ts --bundle --format=esm --target=es2022 --minify \
  --charset=utf8 --legal-comments=none --metafile=esm-meta.json --outfile=pele.js
"$ESBUILD" src/index.ts --bundle --format=iife --global-name=pele --target=es2021 \
  --minify --charset=utf8 --legal-comments=none \
  '--banner:js=/*! Pele 1.13.0 | MIT License | https://github.com/obsidianmd/pele */' \
  --metafile=global-meta.json --outfile=pele.global.js
```

Compare the resulting bytes with the files in the locked Pele npm archive; do
not overwrite or commit upstream outputs when performing this check.

The esbuild metafiles record 243 inputs each: Pele's `src/` files and its
`package.json`; no `node_modules` source files were included. The global
build's metafile also identifies esbuild's synthetic `<runtime>` helpers.
The esbuild 0.28.2 MIT license is retained as `Pele-esbuild-MIT.txt` and is
included with the resources. It was copied from the npm archive whose SHA-512
integrity is specified in Pele's pinned `package-lock.json`; its SHA-256 is
`b40ec5baec7bb34fa5b1c09521fa3cd52d5fad7adafed74932a2010d3612a681`.

Pele's `src/diagrams/common/scan.ts` describes shared lexer rules as ported
from Mermaid's compiled Jison journey and timeline rules. The file is imported
by both diagram lexers. As a precaution, `Pele-Mermaid-MIT.txt` retains
Mermaid's MIT license and copyright notice with the bundled resources. It is
the unmodified `LICENSE` from Mermaid commit
`1fb7869866dd619168d840291c9c54b4f129758b` (tag `mermaid@12.2.0`), SHA-256
`ec9fb67dcb25eccc416ed56e1aab819222c805a2a4bfe4cb19e7556bf2ffde80`.
The Pele comment does not identify a Mermaid revision, so this is a documented
license reference, not a claim that 12.2.0 was the source of the port.

At that Mermaid reference commit, the individual grammar headers identify the
following additional notices:

* `packages/mermaid/src/diagrams/user-journey/parser/journey.jison`:
  Copyright (c) 2015 Knut Sveidqvist, MIT license.
* `packages/mermaid/src/diagrams/timeline/parser/timeline.jison`:
  Copyright (c) 2023 Knut Sveidqvist, MIT license.

The grammar files are evidence of the upstream rules and their notices, not
proof that this specific Mermaid commit was used for Pele's port. These notices
are included with the renderer resources along with `Pele-Mermaid-MIT.txt`.
Their SHA-256 digests at that commit are respectively
`2230b9f958f7c2f2381149b0e484cd203ff919cf43abd065beba7ab6b5a660a5` and
`65a1aaa24f2a9f5416b89b9774847e832cc2e810bb4233d77ad756c94f8baf8f`.

Pele's `src/diagrams/gantt/axis.ts` says its time-axis behavior follows
`d3-time`, `d3-time-format` and d3's time scale. The esbuild metafiles contain
no d3 `node_modules` source files; this observation does not establish whether
any Pele code is derived from those projects. As a precaution, the following
unmodified ISC notices are included alongside the bundled renderer:

* `Pele-d3-time-ISC.txt`: d3-time `v3.1.0`, commit
  `d66bba6f83801b2f3a3e6440dba8df3357669c73`, SHA-256
  `faa682e3e430941f958d26180458f5934a62f58dac4d70ccdd15608c15d0f884`.
* `Pele-d3-time-format-and-scale-ISC.txt`: d3-time-format `v4.1.0`, commit
  `76cfef1da81b70404c0226ec9db9b0d56fa09461`, and d3-scale `v4.0.2`, commit
  `83555bd759c7314420bd4240642beda5e258db9e`. Their license files are
  byte-identical, SHA-256
  `e008c5e25a6be382593089c29bfabbc553c6378eee02895aec46ce396cc404ee`.

These are documented reference versions, not a claim that the Pele author
used these exact commits.

The build settings omit legal comments. This inventory and reproducibility
evidence do not establish the origin or licensing of every upstream source
fragment and are not a legal clearance to publish the mirror.
