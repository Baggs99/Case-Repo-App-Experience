# F4 Task 2 — LibraryViewModel + LibraryCase mapping

Status: DONE.

## Files
- `ios/CaseRoom/State/LibraryViewModel.swift` (new) — `LibraryService` protocol +
  `extension APIClient: LibraryService`, `LibraryType`, `LibraryDone`, `LibraryCase`
  (+ `.from(_:ordinal:)`, `.detailMeta`), `LibraryRow`, `LibraryViewModel`.
- `ios/CaseRoomTests/LibraryViewModelTests.swift` (new) — 19 tests.
- `CasesViewModel.swift` untouched (still backs `CasesListView`/`CaseDetailView`
  until Task 4, per the plan's compile-order resolution #4).
- `project.yml` / `.xcodeproj`: regenerated via `xcodegen generate`, no diff
  (globbed group already covers `State/` and `CaseRoomTests/`).

## case_type DB-spelling assumption (flag for reviewer)
`LibraryType.caseTypeFilter` maps chips to `CaseQuery.caseType` using the DB
spellings given in the task brief: all→nil, marketEntry→"Market Entry",
profitability→"Profitability", ma→"M&A", sizing→"Market Sizing". I checked
`pipeline/exporters/case_type_backfill.py` (the canonical case_type backfill
table) for confirmation:
- "Market Entry", "Profitability", "M&A" all appear as canonical output values
  in that table — reasonably confirmed.
- "Market Sizing" (or any "sizing" variant) does **not** appear anywhere in
  that file — unconfirmed. It's a best-guess spelling per the task brief.

Server match is exact-equality, so if "Market Sizing" is wrong, the Sizing
chip silently returns an empty set (not a crash) — no test can catch a wrong
guess against live data. Recommend a live smoke check against the DB's
`SELECT DISTINCT case_type` (or `SearchFilters`) before Task 3 ships the chip
row, or logging a seam note for the orchestrator.

## Derivation notes
- `kicker`: `[caseType, "\(school) \(year)"]` joined " · ", uppercased,
  omitting whichever half is missing (built from two arrays so a missing
  school or missing year alone doesn't leave a stray space).
- `meta` (row): `"D\(Int(difficultyScore))"`, else the difficulty word, else
  `""`. `detailMeta` (Task 4 reuse) appends `" · rated by N candidates"`.
- `avgRating`: `String(format: "%g", _)` or `"—"` when nil (matches the task
  brief literally, e.g. 4.7 → "4.7").
- `pdfLabel`: `"Case PDF — N pages"` or `"Case PDF"` when `pageCount` nil.
- Ordinals: assigned once in `load()` from the fetched page's descending
  index (`String(format:"%02d", total - index)`), stored on `allCases`; the
  `done` toggle only re-filters `allCases` (no reload), so ordinals are
  stable across toggle changes — verified by test.
- `countLine`/`filteredRows` share a private `shownGroups` helper so the
  divider presence and the count always agree.

## Deviations from the brief
None. `enum LibraryType: CaseIterable` / `enum LibraryDone: CaseIterable`
used exactly as specified (Swift's real `CaseIterable` protocol).

## Test command + result
```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thomaskgould/dev/fe-f4/ios
xcodegen generate
xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom \
  -destination 'platform=iOS Simulator,id=49C5BC31-F364-44C0-BFAB-2CAAAD4B23ED' test
```
Tail:
```
Test Suite 'CaseRoomTests.xctest' passed at 2026-07-17 13:43:33.990.
	 Executed 337 tests, with 0 failures (0 unexpected) in 4.070 (4.162) seconds
Test Suite 'All tests' passed at 2026-07-17 13:43:33.990.
	 Executed 337 tests, with 0 failures (0 unexpected) in 4.070 (4.162) seconds
** TEST SUCCEEDED **
```
Baseline was 318; 318 + 19 new `LibraryViewModelTests` = 337, 0 failures.
`LibraryViewModelTests` suite alone: 19/19 passed.
