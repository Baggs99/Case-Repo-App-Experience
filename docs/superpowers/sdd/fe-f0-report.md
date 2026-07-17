# F0 — Design Foundation · Phase Report

**Status:** DONE · **Branch:** `fe/f0-foundation` · **Head:** `5fde1ac` (base `d106111`)
**iOS suite:** 273 → **289** green (0 failures) · +16 DesignSystem tests
**Date:** 2026-07-17

The token + component layer every later front-end phase (F1–F10) imports. New group
`ios/CaseRoom/DesignSystem/`. All hex literals confined to `Tokens.swift` (reviewers
grep-enforce this in screen code). Full plan:
`docs/superpowers/plans/2026-07-17-fe-f0-plan.md`.

---

## JUDGMENT decisions (locked)

1. **Glass hand-built over `.ultraThinMaterial`**, not iOS 26 `.glassEffect()`.
   Deployment target is iOS 17 and the §1 recipe (135° white gradient .66→.4 +
   blur+saturate + specific white hairline + top inset highlight) is owner-locked
   "copy verbatim". Material supplies the backdrop blur; the gradient/border/
   highlight are layered on. Native glass is system-controlled (can't hit the
   recipe) and would force `#available(iOS 26)`. Same call for every glass surface.
2. **Fonts = bundled variable TTFs; weight via `Font.custom(family:).weight(_:)`.**
   Google publishes only variable Archivo / Source Serif 4 (no static weights);
   `fonttools` unavailable. A CoreText probe confirmed family + weight-trait
   resolves to the correct named instance (400→Regular, 600→SemiBold, 800→
   ExtraBold) and family + slant → the true italic face, handling the fonts'
   inconsistent PostScript naming automatically. Registered via `UIAppFonts` in
   `info.properties` (per brief — never `INFOPLIST_KEY_*`) + a defensive idempotent
   `DSFonts.register()`.
3. **Dark palette = per-screen takeover theme via `\.dsPalette`**, NOT iOS dark
   mode. App stays light; session screens (F5/F6) opt in with `.dsTheme(.dark)`.

## Environment note (bootstrap blocker → resolved, no code change)

The existing suite HANGS on a fresh simulator at
`SessionViewModelTests.testEnteringLiveStartsLiveActivityForInterviewer` — that
test uses the real `RoomRecorder()`, whose
`AVAudioApplication.requestRecordPermission()` blocks in a host-less test with no
prompt UI. **Fix:** grant mic on the sim before testing —
`xcrun simctl privacy <sim> grant microphone study.mycase` (+ `…CaseRoomTests`
+ `com.apple.dt.xctest.tool`). Then it passes in ~5.6s. **All test runs pin
`-destination id=A10D5A1D…` (iPhone 17, iOS 27 runtime) with mic granted.** Later
phase leads must do the same grant, or the baseline appears to hang.

---

## Interfaces — PINNED for F1–F10 (names + signatures are stable)

### Tokens — `DesignSystem/Tokens.swift`
- `struct DSPalette: Equatable` fields: `page, ink, onInk, muted, faint, hairline,
  hairlineSoft, surface, green, link: Color`, `isDark: Bool`.
- `static let DSPalette.light` / `static let DSPalette.dark` (§1 hex, dark-takeover).
- `Color(hex: UInt32, alpha: Double = 1)` — token-layer only.
- `static let Color.dsShadowInk` — theme-independent navy for shadows/scrims.
- `EnvironmentValues.dsPalette` (default `.light`); `View.dsTheme(_ palette: DSPalette)`.
  Screens read `@Environment(\.dsPalette) var palette` and use `palette.ink` etc.
  **NO hex literals allowed outside `Tokens.swift`.**

### Typography — `DesignSystem/Typography.swift`
- `DSFonts.register()` (idempotent); `DSFonts.weight(_ w: CGFloat) -> Font.Weight`.
- `Font.archivo(_ size: CGFloat, weight: CGFloat = 400) -> Font`
- `Font.serifVoice(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font`
- `struct DSTextStyle { font: Font; tracking: CGFloat; lineSpacing: CGFloat }` statics:
  `.h1Tab` (28/800/-0.84), `.takeoverDisplay` (32/800/-1.12), `.cardTitle` (20/700),
  `.rowTitle` (14/600), `.rowTitleStrong` (14.5/700), `.kicker` (10/600/+1.6 caps),
  `.meta` (11.5/400), `.timerLarge` (34/700); `DSTextStyle.serif(_ size:, italic:, weight:)`.
- `View.dsText(_ style: DSTextStyle)` (font+tracking+lineSpacing); `View.tabularNumbers()`.

### Glass — `DesignSystem/Glass.swift`
- `View.glassPanel(cornerRadius: CGFloat = 28)`, `View.glassChip()` (capsule),
  `View.glassSheet(cornerRadius: CGFloat = 32)`.
- `struct GlassSurface<S: InsettableShape>: View` (`shape`, `kind: GlassKind`) — engine.
- `enum GlassKind { case panel, chip, sheet }`.
- `struct DSScrim: View` (rgba ink .34 + blur; solid-ish under Reduce Transparency).
- `AnyTransition.dsRise` (pair with `DSMotion.sheetCurve`).
- Honors `\.accessibilityReduceTransparency` → solid `palette.surface` (body.solid analog).
  Dark recipe auto-selected when `palette.isDark`.

### Motion — `DesignSystem/Motion.swift`
- `enum DSMotion`: `riseCurve` (.42s cubic 0.22,1,0.36,1), `sheetCurve` (.32s),
  `hoverCurve` (.16s), `drawCurve` (.9s), `stagger` (0.13), `pressScale` (0.96),
  `blink` (1.1s repeat).
- `struct DSPressStyle: ButtonStyle` (scale .96, no bounce).
- `struct BlinkDot: View` (`diameter: CGFloat = 6`, green pulse 1→.2).

### Marks — `DesignSystem/StaircaseMark.swift`, `SteppedTimeline.swift`
- `struct StaircaseMark: Shape` (path M4 35 H15 V25 H26 V15 H37 V4 H45, viewBox 48×40).
- `struct StaircaseMarkView: View` (`lineWidth: CGFloat = 5`, `animated: Bool = false`,
  `lowColor: Color? = nil`, `highColor: Color? = nil`; ink→green gradient, trim draw).
- `struct StepPath: Shape` (M2 58 H96 V42 H192 V24 H276 V8 H318, viewBox 320×64, non-scaling).
- `struct SteppedTimeline: View` (`firms: [TimelineFirm]`; ink 2px line + green TODAY dot
  + 3-col firm labels, green readiness only when `onPace`).
- `struct TimelineFirm: Identifiable` (`name, date, days, readiness: String`, `onPace: Bool`).

### Score cell — `DesignSystem/ScoreCells.swift` (§6 shared component)
- `struct ScoreCells: View` (`count: Int`, `value: Int`, `size: ScoreCellSize = .medium`,
  `interactive: Bool = false`, `onSelect: ((Int) -> Void)? = nil`) — cells 1…N filled
  green up to `value`, tabular.
- `enum ScoreCellSize { case large, medium, small }` — 46 / 24 / 16 pt (recap 1–5 pills /
  rubric 24pt / live 16pt). Used by F5 debrief, F6 rubric, F5 recap 1–5.

### Chrome — `DesignSystem/Chrome/`
- `struct WordmarkChip: View` (mark + serif-italic "my" + Archivo-800 "Case", glass chip).
- `struct AvatarPill: View` (`initials: String`; 40pt glass over 28pt ink circle).
- `struct BackPill: View` (`label: String`, `context: String? = nil`).
- `enum DSTab: Hashable, CaseIterable { case home, library, caseTab, community, drills }`
  with `.label` → HOME/LIBRARY/CASE/COMMUNITY/DRILLS. (F1's tab identity; distinct from
  F1's `AppRoute`.)
- `struct DSTabBar: View` (`selection: Binding<DSTab>`, `onSelect: (DSTab) -> Void = {_ in}`)
  — 5-slot floating glass capsule; raised 56pt ink CASE circle (mark chalk→green, offset
  -13); active = ink weight-800, HOME-active +4px green dot, CASE-active +2px green ring;
  inactive muted.
- `struct DSToast: View` (`text: String`); `View.dsToast(item: Binding<String?>)`
  (rises above tab bar, auto-dismiss ~2.4s).
- `View.dsHeaderFade()` (34px page→clear top fade for scroll containers).
- `struct DSBackground: View` (page + green/cobalt tint blobs + giant faint staircase,
  layout stays screen-bound).

### Fixtures — `DesignSystem/PreviewFixtures.swift` (Previews/UI-tests ONLY)
- `enum PreviewFixtures { static let phone: PreviewDay; static let tablet: PreviewDay }`
  — Decisions §3 (phone, Jul 16) / §7 (tablet, Jul 17) verbatim.
- `struct PreviewDay` → `profile, diagnostic, tonight, recommendation, recap, pending,
  timeline: [TimelineFirm], standing`. Sub-structs: `PreviewProfile, PreviewDiagnostic,
  PreviewSession, PreviewRecommendation, PreviewRecap, PreviewPending, PreviewCohortStanding`.

### Debug — `DesignSystem/DesignSystemGallery.swift` (`#if DEBUG`)
- `struct DesignSystemGallery: View` — every component, both themes. Launch args:
  `-DSGallery` (via CaseRoomApp DEBUG hatch), `-DSGalleryDark`, `-DSGalleryMid`,
  `-DSGalleryBottom` (scroll anchor for screenshots). Does NOT alter normal launch/nav.

### Project wiring
- `ios/project.yml`: `UIAppFonts` (3 TTFs) in `CaseRoom.info.properties`; Fonts folder
  added as resources to `CaseRoomTests` (host-less test font loading). Regenerate with
  `xcodegen generate` (idempotent, verified); `.xcodeproj` stays gitignored (repo
  convention — `project.yml` committed instead).
- `CaseRoomApp.swift`: `DSFonts.register()` in init + DEBUG `-DSGallery` hatch. Existing
  deep links / widgets / App Intents / APNs / App Group untouched.

---

## Screenshot verdict
`.superpowers/sdd/f0/shots/` — iPhone 17 (light/dark × top/mid/bottom) + iPad Pro 11
(light × top/mid/bottom + dark). Verified against canvas: Archivo + Source Serif 4 render
(not SF fallback); palette exact; glass frosted panels/chips with hairline; wordmark chip;
40pt AO avatar pill; 5-slot tab bar w/ raised ink CASE circle + green→chalk staircase mark,
HOME active + green dot; ink→green mark gradient + blink dot; stepped timeline w/ firm labels
(McKinsey ON PACE green only); score cells at all 3 sizes filled-to-N green; dark takeover
(#081222) inverts correctly.

## Assumptions / deviations
- `.xcodeproj` gitignored (repo convention); `project.yml` + generated `Info.plist` committed.
- Tablet screenshots are **portrait** — landscape rotate is blocked by macOS accessibility
  TCC (osascript keystroke denied) on this box. F0's gallery is an orientation-agnostic
  vertical component showcase; true tablet landscape two-column layouts begin in F2. Portrait
  iPad shots prove iPad-scale rendering. Non-material for F0.
- Dark palette `link` = same cobalt `#2E56C0` as light (Decisions dark list omits a link
  color; sessions rarely link).
- Giant-faint-staircase ghost uses `hairline` (#C9D2DF); canvas allows #C9D2DF/#B7C3D4.

## Whole-branch Opus review — VERDICT: APPROVE (0 blocking)

Reviewer confirmed: tokens exact + test-locked; mark/timeline geometry provably
correct; fonts genuinely render as Archivo + Source Serif 4 (not SF); dark takeover
token-driven; every §5 hard rule passes; no-hex enforceable; iOS mechanics clean
(UIAppFonts via info.properties, deep links/widgets/APNs untouched, DEBUG hatch inert
on normal launch). No blocking defects.

**Non-blocking findings — FIXED this phase (shared primitives 10 phases import):**
- Tab bar: added `maxWidth: CGFloat? = nil` (pass 560 for §7 tablet-centered — F2 no
  longer edits F0; gallery passes 560 on iPad, verified in tablet shots) + the canon
  floating-bar shadow (0 10px 26px .14).
- CASE circle: now fixed navy in both themes with the canvas g22 chalk→bright-green
  (#2FC07E) mark (was `palette.green` #1B9A5F).
- Header fade: solid-to-22%-then-transparent (matches the canvas gradient stops).
- Glass: added the bottom inset highlight (`inset 0 -1px 0 rgba(255,255,255,.3)`).
- Full suite re-verified green (289/0) after fixes; affected shots re-captured.

**Non-blocking findings — DEFERRED (per reviewer's own scoping) + documented:**
- **Timeline label hierarchy** — DC pixel truth makes "58d" the 14/700 hero and firm·date
  a 9px kicker; F0 followed the §1 *prose* (firm·date hero / days / readiness). Reviewer
  scoped to "when the timeline lands on real Home/Timeline screens in F2."
  **F2 action:** invert `SteppedTimeline` label hierarchy to pixel truth + change fixture
  day format "58 days" → "58d".
- **Chip glass recipe** — F0 uses the panel gradient for all light glass; canon's flat
  `rgba(255,255,255,.55)` blur-12 key/chip variant is a deliberate F0 simplification
  (reviewer "fine for F0"). Revisit if a screen needs the flatter key look.
- **Gallery uses phone fixtures on iPad** — the §7 tablet fixture is correct + tested but
  not screenshot-rendered (device-agnostic showcase). Non-material.
- Sub-pixel: timeline TODAY-dot radius/x + the "TODAY" text label — F2 timeline polish.

## Concerns / escalations
None. F0 is a solid foundation; all downstream-relevant fidelity gaps are either fixed
or captured above as explicit F2 actions.
