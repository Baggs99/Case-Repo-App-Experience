# F4 Task 5 — Tablet master–detail Library (canvas 2c) · Report

Status: DONE. Focused compile+test green (runner cooperated this run — no thrash wedge). Screenshot
capture is explicitly out of scope for this task (phase lead captures the iPad shot separately, per
brief).

## Files
- `ios/CaseRoom/Views/LibraryMasterDetailView.swift` (new) — the `.regular` size-class body:
  `HStack` `1fr | 470pt`, `palette.hairline` 1px vertical divider on the trailing edge of the left
  column (canvas `border-right:1px solid #C9D2DF` — palette.hairline is the exact token match, same
  hex the canvas uses for its horizontal hairlines elsewhere in the file). Left column = no H1 (shell
  draws the centered "Library" tab label on `.regular`) + `LibraryTypeChipRow` + `LibraryToggleRow` +
  `LibraryRowsList` with `onRowTap: { viewModel.selectedID = libraryCase.id }` (select, never push) and
  `selectedID: viewModel.selectedID` (drives `LibraryRowView`'s glass-chip fill). Right column (fixed
  470pt) = `CaseDetailContent(layout: .tablet, libraryCase: viewModel.selectedCaseWithHistory)`,
  always visible, inside its own `ScrollView`. Outer padding 28 sides / 18 top / 96 bottom (clears the
  560pt floating tab bar).
- `ios/CaseRoom/Views/CasesListView.swift` (edit) — extracted `LibraryTypeChipRow`, `LibraryToggleRow`,
  `LibraryRowsList` out of the private phone-only methods into standalone (internal) `View` structs
  parameterized by `viewModel` (+ `onRowTap`/`selectedID` for the rows list) so both the phone list and
  Task 5's tablet left column bind the SAME components to the same `LibraryViewModel` — no duplicated
  chip/toggle/row-rendering code. `sizeClassBody` now branches `hSize == .regular` →
  `LibraryMasterDetailView(viewModel:)` vs phone → `phoneList`; `.task { load() }` +
  `.onChange(of: viewModel.type)` moved up to `sizeClassBody` so both branches reload identically
  (previously only attached inside `phoneList`, which happened to also be what `.regular` rendered).
  `.compact` phone list is otherwise byte-for-byte unchanged (H1, chip row, toggle row, rows list, push
  on row tap).
- `ios/CaseRoom/State/LibraryViewModel.swift` (edit) — added `recentSessions: [SessionSummary]` +
  `selectedCaseWithHistory: LibraryCase?`.
- `ios/CaseRoomTests/LibraryViewModelTests.swift` (edit) — 5 new tests for the history-attachment logic
  (below).

## History attachment (tablet right pane)
`LibraryViewModel.load()` now also calls `service.recentSessions()` — but only once per VM lifetime,
gated by a private `didFetchSessions` flag, so a type-chip reload (which re-queries `library()`) does
NOT re-fetch sessions. `selectedCaseWithHistory` is a computed property: takes `selectedCase` (the
VM's existing selection-or-first-row fallback), and attaches `historyLine`/`historyScore` via
`LibraryDetailCopy.history(from: recentSessions, caseTitle: selected.title)` — the SAME title-match +
`"MMM dd" · other_user` + `"<grade> avg"` derivation `CaseDetailView` already uses for the phone push
path, so phone and tablet render history identically off one shared function rather than two
DateFormatter implementations drifting apart. `CaseDetailView`'s own phone history loading is
untouched — it still loads its own `caseDetail`+`recentSessions` independently per push.

## Verification
- Rubric grep (`LibraryMasterDetailView.swift`, `CasesListView.swift`): no `Color(red:` / `Color("` /
  hex literals outside one code *comment* documenting the canvas's own `#C9D2DF` (not a Swift value);
  no `systemImage`/`Label(` (no SF Symbols). Square content corners — the master column has none;
  reused `LibraryRowView`/chip components already square/capsule-correct from Tasks 2-3.
- `xcodegen generate` run; `git status` shows `CaseRoom.xcodeproj` NOT tracked (gitignored, as before)
  and `project.yml` unchanged (glob-based `sources: [CaseRoom]` already covers the new file).
- Focused build+test:
  ```
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom \
    -destination 'platform=iOS Simulator,id=49C5BC31-F364-44C0-BFAB-2CAAAD4B23ED' \
    -only-testing:CaseRoomTests/LibraryViewModelTests \
    -only-testing:CaseRoomTests/LibraryDecodingTests \
    -only-testing:CaseRoomTests/CaseDetailContentTests \
    build-for-testing test-without-building > /tmp/f5.log 2>&1
  ```
  Log tail:
  ```
  ** TEST BUILD SUCCEEDED **
  	 Executed 15 tests, with 0 failures (0 unexpected) in 0.015 (0.022) seconds
  	 Executed 5 tests, with 0 failures (0 unexpected) in 0.021 (0.023) seconds
  	 Executed 25 tests, with 0 failures (0 unexpected) in 0.018 (0.024) seconds
  Test Suite 'CaseRoomTests.xctest' passed at 2026-07-17 18:09:53.572.
  	 Executed 45 tests, with 0 failures (0 unexpected) in 0.054 (0.069) seconds
  Test Suite 'Selected tests' passed ... Executed 45 tests, with 0 failures (0 unexpected)
  ** TEST EXECUTE SUCCEEDED **
  ```
  Runner cooperated this run (no thrash wedge, no retries needed). All 5 new
  `selectedCaseWithHistory`/`recentSessions`-once tests passed individually confirmed by name in the
  log (`testSelectedCaseWithHistoryAttachesTitleMatchedSession`,
  `testSelectedCaseWithHistoryNilLineWhenNoTitleMatch`,
  `testSelectedCaseWithHistoryFollowsSelectionAcrossRows`,
  `testSelectedCaseWithHistoryNilWhenLibraryEmpty`, `testRecentSessionsFetchedOnceNotOnEveryTypeReload`
  — the last asserts `stub.recentSessionsCallCount == 1` after three `load()` calls across two
  type-chip changes, proving the "fetch once" gate rather than inferring it).

## Deviations / seams
- None from the task brief. `CaseDetailContent(.tablet)` and `LibraryRowView(isSelected:onTap:)` were
  already parameterized for this by Tasks 2/4 exactly as the pinned interfaces describe — Task 5 wired
  them, it didn't need to extend either.
- iPad screenshot NOT captured here — explicitly the phase lead's responsibility per the task brief.
- `xcodebuild test` (full 313+ suite) not run this task per the CRITICAL instruction (thrash-lock +
  mic-flake hang risk) — only the 3 focused targets above ran, green.
