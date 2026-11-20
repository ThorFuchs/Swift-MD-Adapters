# SwiftSoup source distribution review

**Historical:** This records the published SwiftMD 1.0.0 distribution and its
SwiftSoup 2.11.3 source. The current local SwiftHTML integration uses the
separate SwiftHTML package and SwiftSoup 2.14.4; it does not include the old
`SwiftMDSoup` source. Paths and scripts below describe the 1.0.0 Git tree.

The adapter package now vendors the library sources from SwiftSoup 2.11.3,
commit `d86f244ed497d48012782e2f59c985a55e77b3f5`, as the private
`SwiftMDSoup` module. Its MIT `LICENSE` is retained unchanged as a package
resource and in `SwiftSoup-MIT.txt`. The vendored source has 55 upstream files;
the only content changes are seven `SwiftSoup.` to `SwiftMDSoup.` replacements
in four Swift files, including comments. `Vendor/SwiftSoup/UPSTREAM.json` records
each original and modified SHA-256. `Scripts/audit-vendored-swiftsoup.py` can
independently compare every file and transformation with the upstream Git tree.
The vendored tree contains no test or corpus files. Normal consumers do not
resolve the separate upstream SwiftSoup package. A consumer that deliberately
adds SwiftSoup for its own use resolves that separate package independently.

SwiftSoup's own README says it was ported from Java jsoup. Its pinned README
does not identify the exact jsoup revision. As a conservative additional
notice, `SwiftSoup-jsoup-MIT.txt` and the module's `JSOUP-LICENSE.txt` reproduce
the jsoup `jsoup-1.21.2` MIT license from commit
`b02837b6c77b94799c055f8fa446fb770bfb49f1` (SHA-256
`12f89090b34132ac86980044fba5f6d45cfbc02c1eb08e0b53a22b7cb40be446`).
This is a documented license reference, not a claim that this precise jsoup
revision was used. The original SwiftSoup notice remains included.

## Historical upstream fixture observation

The pinned source snapshot also contains six saved web pages under
`Tests-macOS/corpus/`: Amazon, GitHub, Google, Reuters, Wikipedia and Wirecutter.
For example, `Google.html`, SHA-256
`094d6a66d4540a9539eb02315b830bc7219a4e141893d4dd5f5757125c7fd46c`,
contains an embedded Math.uuid.js comment identifying Robert Kieffer and dual
MIT/GPL licensing, and another comment identifying Closure Authors and
MochiKit. The file also contains material presented as a Google page. Git
history attributes the file's addition to SwiftSoup commit
`5da0b123b9b2223028e97cfd3709bf697a2f6ad0`; that records the import, not the
rights chain of each part of the page.

On 19 November 2026, the newer public SwiftSoup 2.14.4 tag still contained all
six named corpus files. Its `Google.html` has the same Git blob
`a215fa8a4324caae3841af5c78c600c265a877bc` as the pinned 2.11.3 snapshot.
Updating to that tag alone therefore does not remove this particular issue.

ScanCode Toolkit 33.0.0rc1 reported an MIT-or-GPL reference in that Google
fixture. The root package license and this match do not establish the terms
of every external page or embedded component in the corpus. This observation
is not a conclusion of infringement. The vendored SwiftMD distribution omits
the corpus rather than determining its rights. Preserve the distinction between
SwiftMD's distribution and any upstream source independently fetched by a user.

The SwiftSoup library source and its independently fetched package are governed
by their own notices. This file does not modify SwiftSoup or determine the
legal status of any third-party material.
