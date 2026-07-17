# F4 Task 1 — Networking: case aggregates + LibraryPage

**Status: DONE**

## Files changed

- `ios/CaseRoom/Networking/Models.swift` — added `avgRating: Double?`,
  `runCount: Int?`, `doneForYou: Bool?` to `CaseSummary` and `CaseDetail`
  (optional, no `CodingKeys`; `.convertFromSnakeCase` maps `avg_rating`/
  `run_count`/`done_for_you`). Added `struct LibraryPage: Codable, Equatable`
  (`cases`, `total`, `openCount`, `doneCount`) — decodes the
  `/api/v1/cases` list response directly (`open_count`/`done_count` map via
  the same snake-case strategy).
- `ios/CaseRoom/Networking/APIClient.swift` — added
  `func library(query: CaseQuery = CaseQuery()) async throws -> LibraryPage`,
  GETing `/api/v1/cases` with the same query-item construction as
  `cases(query:)` (duplicated intentionally per the plan's compile-order
  note — `cases(query:)` stays untouched until Task 4 removes its last
  caller). `caseDetail(id:)` unchanged; now decodes the three new optional
  fields for free.
- `ios/CaseRoomTests/LibraryDecodingTests.swift` (new) — 5 tests, all
  hitting the real `APIClient.library`/`caseDetail` pipeline via the shared
  `StubURLProtocol` (from `APIClientTests.swift`) rather than a private
  decode mirror, per the task's "prefer testing the public models" note:
  - `testLibraryRequestAndDecode_WithAggregates` — full aggregate JSON →
    `page.openCount`/`doneCount` + a case's `avgRating`/`runCount`/
    `doneForYou` populate.
  - `testLibraryRequestAndDecode_MissingAggregateKeysStillDecodesNil` —
    back-compat: JSON without `avg_rating`/`run_count`/`done_for_you` still
    decodes, those three fields nil.
  - `testLibraryRequestBuildsSameQueryItemsAsCases` — asserts `library()`
    sends the same query items (`q`, `case_type`, `limit`) as `cases()`.
  - `testCaseDetailRequestAndDecode_WithAggregates` — `/api/v1/cases/{id}`
    JSON → aggregates + `previewUrls`/`pdfUrl` decode.
  - `testCaseDetailRequestAndDecode_MissingAggregateKeysStillDecodesNil` —
    same back-compat check for the detail endpoint.

### Incidental fixes (required for compile, not scope creep)

Adding non-defaulted fields to `CaseSummary`/`CaseDetail`'s memberwise init
broke three existing test call sites that construct these structs directly.
Updated each to pass `avgRating: nil, runCount: nil, doneForYou: nil`:
- `ios/CaseRoomTests/CasesViewModelTests.swift` (`makeCase` helper)
- `ios/CaseRoomTests/IntentsTests.swift` (3 call sites: a `CaseSummary`, a
  `CaseDetail`, and a `CaseSummary` array-builder)

No other `CaseSummary(`/`CaseDetail(` construction sites exist in the repo
(confirmed via grep across `ios/`).

## Build/test evidence

`xcodegen generate` regenerated `CaseRoom.xcodeproj` (gitignored; `git
status` confirms `project.yml` did not change — no commit needed for it).

```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thomaskgould/dev/fe-f4/ios
xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom \
  -destination 'platform=iOS Simulator,id=49C5BC31-F364-44C0-BFAB-2CAAAD4B23ED' test
```

Tail:
```
Test Suite 'CaseRoomTests.xctest' passed at 2026-07-17 13:37:11.400.
	 Executed 318 tests, with 0 failures (0 unexpected) in 4.252 (4.342) seconds
Test Suite 'All tests' passed at 2026-07-17 13:37:11.400.
	 Executed 318 tests, with 0 failures (0 unexpected) in 4.252 (4.344) seconds
** TEST SUCCEEDED **
```

313 baseline + 5 new `LibraryDecodingTests` = 318, 0 failures.

## Deviations

None from the task brief. `LibraryPage` was made `Codable` (not just
`Equatable` as literally listed) so it can be the direct decode target for
`send(path:method:queryItems:)` — the field names (`cases`, `total`,
`open_count`→`openCount`, `done_count`→`doneCount`) match the endpoint
exactly, so no private response mirror was needed, matching the task's
preferred approach.
