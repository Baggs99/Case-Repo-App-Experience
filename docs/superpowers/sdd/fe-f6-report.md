# F6 — Interviewer consoles (phone 8b + tablet hero 1a) · Phase Report

**Status:** DONE · **Branch:** `fe/f6-console` · **Head:** `f16a8d2` (base `a60ebab`)
**iOS suite:** 668 → **699** green (0 failures) · +31 tests · **Backend suite:** **655** green (0 failures — no backend files changed; iOS-only phase)
**Date:** 2026-07-18 · Plan: `docs/superpowers/plans/2026-07-17-fe-f6-plan.md` · Ledger: `.superpowers/sdd/f6/progress.md`
**Screenshots:** `.superpowers/sdd/f6/shots/` (4 phone-context + 6 tablet — portrait; landscape can't be forced headless)

Built the interviewer's **console** as the live-interviewer seat: the **phone console** (canvas 8b — 6 stage chips, serif read-aloud, exhibit Release/SENT·mm:ss/Recall, per-stage 1–N score strip + evidence, bottom Previous/Display PDF/Next→Finalize, tap-to-run clock) and the **tablet hero** (canvas §7-1a — top bar with mark/wordmark | case | CANDIDATE | tap-run master-clock chip w/ N LEFT + under-5-min green | Finalize & send, 45-min cap bar, grid 1fr/380px: stage script + exhibits + SCORE THIS STAGE | right rail candidate feed w/ LIVE chip + self-view, SEGMENT TIMER w/ laps, RUBRIC — LIVE mini-cells + running avg), plus **case-pack PDF mode** (tablet overlay covers the LEFT pane only — the rail stays live — + phone full-screen pager; 3 authored pages). All scoring/exhibit-release/finalize flow through the existing `RubricViewModel`; **the transport layer (WebRTC/signaling/reveal-crypto) is byte-identical** (grep-verified across the whole branch).

---

## Tasks (each: fresh Opus implementer → fresh Opus reviewer → fix loop)

| Task | Scope | Commit(s) | Suite | Review |
|---|---|---|---|---|
| Plan | Plan + Opus plan-review (REQUEST_CHANGES: 2 blocking + 4 important + 5 nits, all folded) | `f0b5e5e` | — | folded |
| T1 | ConsoleScript (authored 7/6-stage script + dims map + 3 PDF pages) + pure ConsoleViewModel + tests | `fff3396`,`c15308d`,`3dcce80` | 691/0 | APPROVE-WITH-NITS (coverage guarantee adversarially proven) → 3 nits fixed |
| T2 | Phone console 8b + SessionView interviewer-live repoint (liveContent level) + hatches | `d53fe1c`,`a6ecd82`,`3d50f18`,`2511478` | 694/0 | APPROVE-WITH-NITS (shots match 8b; rv#3 confirmed; reveal-once proven) |
| T3 | Tablet hero chrome (top bar + cap bar) + LEFT pane + 12-dim shot fixture | `4ffd565`,`15194bc`,`8a5640a`,`d038adb` | 696/0 | APPROVE-WITH-NITS |
| T4 | Tablet RIGHT rail (candidate feed + SEGMENT TIMER + laps + RUBRIC — LIVE) | `68d5750`,`9be1e6d` | 697/0 | APPROVE-WITH-NITS → 3 nits fixed (incl. a real "0/10"→"— /10" miss) |
| T5 | Case-pack PDF mode (tablet left-overlay + phone pager) + `pdfBackdrop` token | `73e36d0` | 699/0 | APPROVE-WITH-NITS (left-only overlay + live rail + e1 SENT sync + verbatim pages) |
| Close-out | Whole-branch adversarial review → SHIP-WITH-FOLLOWUPS; 1 IMPORTANT fixed (candidate feed wired) | `f16a8d2` | **699/0** | transport CLEAN |

Whole-branch adversarial review: **transport-boundary CLEAN** (0 media/crypto/signaling files touched), no crash/contract/concurrency blockers. Its 1 IMPORTANT finding (interviewer's candidate video was an unwired placeholder — regression vs pre-F6) was FIXED (`f16a8d2`); the 3 minor items are verified-safe/documented below.

---

## Architecture / integration (for the orchestrator + future phases)

- **The console IS the interviewer's live seat.** `SessionView`'s interviewer `live` branch renders `InterviewerConsoleView` (size-class aware: phone 8b `.compact` / tablet 1a `.regular`), repointed at the `liveContent` level so no 300h `VideoCallView` wrapper mounts above it; the console owns its own media surface. The **candidate** live branch (`CandidateLiveView`) + negotiation/lobby/debrief/finalized routing are byte-identical (the old `liveContent` body was extracted verbatim into `candidateLiveContent`). The console overrides `.dsTheme(.light)` at its root (the takeover cover is dark; candidate stays dark) — same override pattern F5's DebriefView uses.
- **All state-changing work reuses existing plumbing.** Scoring/exhibits/reveal/finalize go through the shared `RubricViewModel` (SessionView owns it, shares it with DebriefView). "Finalize & send" (top-bar + last-stage) → `moveToDebrief()` — the single finalize path stays F5's DebriefView; **no `/finalize` added.** Release → the existing `reveal(exhibitId:)`; recall is a local un-mark only (§A5). Exhibit refs e1/e2/e3 → `ExhibitMeta.idx` 0/1/2 → `.exhibitId`.
- **Template-agnostic rubric.** The console renders whatever template `RubricViewModel` loads. RUBRIC — LIVE rail shows all template items (current-stage dims ink / others slate); running avg is a LOCAL mean of scored dims (not `gradePreview`). Cell scale derives from `item.maxPoints` (never a hardcoded 10). Stage→dim resolution: tablet union-keys + catch-all (every dim scoreable, no drop/dup — adversarially tested); phone 1:1 (each real dim on a distinct stage).
- **New DEBUG hatches** (`#if DEBUG`, Release-inert): `-startTakeover console-phone[-scored]`, `console-tablet[-scored]`, `console-pdf[-p2|-p3]`, `console-phone-pdf`. Fixtures: a real-shaped 5-dim/max-5 phone fixture + a canvas-faithful 12-dim/max-10 tablet fixture (shot-only).
- **New shared-component param:** `ScoreCells.showsNumbers: Bool = true` (default preserves every F5 call site byte-for-byte; the rail passes `false` for the canvas's blank heat-strip cells). **New token:** `DSPalette.pdfBackdrop` (light #E7EBF1 + dark analog) for the case-pack paper.
- New files: `ConsoleScript.swift`, `ConsoleViewModel.swift`, `InterviewerConsoleView.swift`, `ConsolePDFView.swift`, `ConsoleViewModelTests.swift`. Edited: `SessionView.swift`, `ScoreCells.swift`, `Tokens.swift`, `SessionFixtures.swift`, `RootShell.swift`. `project.pbxproj` is gitignored/regenerated (glob picks up new files; no `project.yml` change needed).

---

## Deviations & OWNER-VISUAL flags (FW6 demo checkpoint)

1. **Console SUPERSEDES F5's dark `InterviewerLiveView` as the live-interviewer path.** Canvas 4a-interviewer (dark) and 8b/1a (light console) are competing designs for the same moment; the brief ("extend the interviewer seat", "tablet hero = THE flagship") selects the console. `InterviewerLiveView` + its `liveInterviewerStandalone` fixture are RETAINED (F5 artifact; now unreachable via the live path — a documented maintenance residual, kept so the F5 shot/fixture still resolves).
2. **Shipping rubric = 5 dims / max 5** (structure/quant/insight/communication/synthesis) vs the canvas's **12 dims / 1–10** mock. The console binds to the real template (execution §2: "live screens bind to the API; reports override briefs"); the 12-dim look is reproduced only in the tablet shot fixture. Owner call: enrich the backend rubric template to 12 dims later, or accept 5.
3. **Stage script + PDF case-pack are authored client-side** (the canvas Case-07 Nordic content) — no backend stage-script/case-pack endpoint exists. Live-wired: rubric scoring (autosave), exhibit reveals, clock, finalize. Follow-up: a backend case-pack/script source when >1 case ships.
4. **Recall is a local un-mark, not an un-broadcast** (§A5) — no recall endpoint and the transport is frozen; reveal is one-way, so recall clears the interviewer's SENT·mm:ss marker but the candidate's already-revealed exhibit stays.
5. **Phone console has no interviewer mute/self-view** (canvas 8b is console-only; audio flows via the untouched transport) — and **phone PDF has no canvas anchor** (Mobile 1-series tail truncated) → implemented as a full-screen single-column authored pager.
6. **RUBRIC — LIVE rail cells are BLANK** (canvas 1a line 805 — a compact heat-strip) vs the numbered 24pt left-pane cells. Matched the canvas via `ScoreCells.showsNumbers: false`. Visual-owner-gate — confirm the blank live-cell at the demo.
7. **Tablet shots are PORTRAIT** (the headless sim can't force/hold landscape — predecessors F5 hit the same). At the real landscape hero width (1194pt) the top-bar text and all 7 stage chips fit one row; the portrait truncation/chip-scroll are width artifacts, not layout defects.

## Documented residuals (non-blocking; whole-branch review + orchestrator-adjudicated)

- **`RailVideoView` duplication (DECISION, recorded):** the candidate feed / self-view mount the live tracks via a ~12-line render-only `RTCMTLVideoView` attach/detach representable added in the console file, because `VideoCallView`'s equivalent `RTCVideoRepresentable` is `private` and that transport-boundary file is off-limits to edit. Adjudication (lead + orchestrator agree): a duplicate **render-only** wrapper is the correct side of the HARD RULE — the rule protects negotiation/capture/crypto semantics, not a display mount; the wrapper only attaches tracks the untouched media layer produces (never creates/captures/negotiates), the console drives no capture toggles, and the whole-branch boundary grep confirms zero transport files changed. Optional future cleanup: de-privatize `RTCVideoRepresentable` and share it.
- **Phone drops any template dim outside its 6-stage 1:1 map** (no phone catch-all / no phone rail). Safe today — the real template is exactly `{structure,quant,insight,communication,synthesis}`, all 5 mapped (verified vs `webapp/repositories/practice_sessions.py`). A 6th/renamed backend dim would be unscoreable on phone → revisit if the backend rubric grows.
- **Phone `scoreBlock` uses `stageItems(...).first`** — 1:1 by construction today; brittle if a phone stage key ever matched multiple template items.
- **T5 PDF page-title tracking** uses one constant vs the canvas's per-page −0.025/−0.02em (sub-0.1px, imperceptible).

## Follow-ups (deferred; non-blocking)
- Backend case-pack / stage-script source (deviation 3) to drive >1 case.
- Owner decision on the 12-vs-5-dim rubric (deviation 2) and the blank-vs-numbered live cell (deviation 6).
- If the interviewer needs the candidate's video on **phone** (canvas 8b omits it), that's a design change, not a bug.

## Screenshot verdict
`.superpowers/sdd/f6/shots/` — phone (iPhone 17): `phone-console`, `phone-console-scored` (running clock + scored dim + SENT·mm:ss), `phone-pdf`. Tablet (iPad Pro 11", portrait): `tablet-console-left`, `tablet-console-scored` (under-5-min green N LEFT + near-full cap bar + SENT), `tablet-console-full` + `tablet-console-rail` (candidate feed + SEGMENT TIMER + laps + RUBRIC — LIVE avg + ink/slate split), `tablet-pdf-p1/p2/p3` (left-only overlay with the rail live beside it; p2 Exhibit 01 Release synced to the script's e1 SENT; p3 answer-key INTERVIEWER ONLY). Each reviewer canvas-anchored its shots (8b / §7-1a); reject-list clean (StaircaseMark-only, square content corners, underline secondaries, tabular clock/timer/score numerals, no population counts, tokens-only).

## THOMAS MANUAL
Owner-visual sign-off deferred to the FW6 demo (visual-judgment gate): eyeball the **tablet hero** (§7-1a) fidelity on-device (landscape — the sim shots are portrait), and rule on the deviations above — chiefly (2) the **5-vs-12-dim rubric**, (6) the **blank vs numbered** RUBRIC — LIVE cells, and (1) the **console superseding the dark interviewer-live**. The candidate-feed video is wired but renders the striped placeholder in the sim shots (no live media); it will show real video on a signed on-device remote session (needs your signing via the ship tool). No dev server was started (port 8106 unused — the screenshots use DEBUG fixtures + mock services); the iPad Pro 11" sim is left booted (shut it down to reclaim RAM if idle).

## ESCALATIONS
None. No Fable/`deep` consult was made or required.
