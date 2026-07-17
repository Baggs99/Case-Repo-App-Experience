# F2 — Home + Timeline detail · Ledger

Updated: 2026-07-17 · Branch: fe/f2-home · Worktree: /Users/thomaskgould/dev/fe-f2
Base commit: 72c4351 (cut from feature/backend-gap after F1 merge)

## Bootstrap (DONE)
- DB caserepo_fe_f2 created → schema.sql → migrations 0*.sql (all idempotent) → seed_caseroom_dev.py (users a/b/c@yale.edu, case 1). evidence: all steps exit 0.
- Backend baseline: `DATABASE_URL=…/caserepo_fe_f2 <venv> -m pytest tests/ -q` → **655 passed** (matches target).
- iOS baseline: `xcodegen generate` (idempotent) + `xcodebuild -scheme CaseRoom -destination id=942222D4-…(iPhone 17) test` → **313 tests, 0 failures** (matches target). mic granted on sim.
- Env: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer for all xcode* calls. venv = /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python.

## Now
Plan-review PASS (after fixes). Executing task loop.
Order: T1 DS primitives → T2 API → T4 Timeline detail → T3 Home phone → T5 Tablet → T6 close-out.

## Done
- Bootstrap (above): backend 655, iOS 313.
- Plan written + committed (c019546).
- Plan-review (Opus): REQUEST_CHANGES → 2 IMPORTANT (I-1 add profile() for identity/cohort rank; I-2 T4-before-T3 ordering, no stub) + 6 MINOR all fixed in plan. Re-commit pending.

## Tasks
- Task 1 (DS primitives, opus): COMPLETE — commits 76e26e1..0435129, review PASS (0 crit/imp). SteppedTimeline hierarchy inverted to pixel-truth + TODAY label/dot + flat glass-key variant (glassKey/glassChipFlat). Suite 313→315. Gallery shot task1-gallery-bottom.png verified vs canvas 3a/7b.
  - Banked MINOR (final triage): glass-key reuses panel top-inset highlight (.85/1.5px) vs §1 recipe (.9/1px). Subtle, shared w/ panel.
- Task 2 (API models, sonnet): COMPLETE — commits b6518f4..0157c7b (impl 5f7bfa5 + review-fix 0157c7b). HomeModels.swift (24 types) + DashboardStats additive extension + 8 APIClient methods + 4 protocols. Review: REQUEST_CHANGES → 1 IMPORTANT (Reweight.focusDimension must be optional; backend nulls it on no_offer) FIXED + null fixture. Suite 315→332. Impl-caught deviations validated by reviewer: strengths/weaknesses are [DimensionScore] not [String]; casesDone60D capital-D; nullable GroupRef/GauntletGroup.name.
- Task 4 (Timeline detail, sonnet): COMPLETE — commits 0157c7b..30d87cd (impl f78db05 + review-fix 30d87cd). TimelineDetailView + VM + 13 tests + DEBUG hatches (-F2Timeline/-F2TimelinePromptNoOffer). Review: REQUEST_CHANGES → 3 IMPORTANT copy-fidelity (no_offer "before BCG" via focus-firm derivation; "MMM dd" zero-pad dates; readiness-row "PUSH" short-form) + 1 MINOR (test baked the bug) ALL FIXED + verified vs canvas 7b in reshot shots. Suite 332→345.
  - Plan patched (lines 226/295/315) so T3 inherits "MMM dd" + focus-firm derivation.
  - NOTE (screenshot tooling): stale DerivedData (brssf) caused false "Login" shots; deleted it, fzihnr is the working build. Cold-launch needs ~8s render wait (perl select; `sleep` binary blocked).
  - Deferred/flagged: "Set date" tap is inert (B7 has no set-deadline endpoint) — backend follow-up.
- Task 3 (Home phone, sonnet): COMPLETE — commit 80f3d36 (impl agent stopped pre-finalization; lead finished: fixed testDateKickerFormat which hardcoded the canvas's FICTIONAL weekday "WEDNESDAY, JULY 16" [2026-07-16 is really Thursday] → code correct, test wrong; ran suite, captured shot, committed). HomeView + HomeViewModel + NumberWords + 13 tests; RootShell .home NavigationStack(homePath) + AppRouter .timelineDetail→homePath. Review: PASS (0 crit/imp). Suite 345→358. Shot home-phone.png matches canvas 3a.
  - I-1 identity fix verified (cohort rank by entry.userId==profile.id, hidden if absent; greeting firstName from profile).
  - Banked MINORs (Task 6 triage): (a) dateKicker uses "MMMM dd" → single-digit days show "JULY 06"; plan spec wants "MONTH D" — one-char dd→d fix; (b) cohort found-case test fixture has id-order == rank-order (not ordering-adversarial); code correct, test-robustness nit.
  - Infra note: 3 DerivedData dirs exist (fzihnr active); Task 5 must select app by NEWEST mtime + verify shot >1MB to avoid the stale-install trap. Sim wedge (Live Activity test) cleared by orchestrator reboot+mic-regrant; suite now runs clean foreground (~fast, warm DD).
- Task 5 (tablet Home canvas 2a, sonnet): IN PROGRESS. BASE=80f3d36.
- (T6 pending)

## Blocked / decisions needed
- (none yet)

## Assumptions
- Test/shot sim = iPhone 17 UDID 942222D4-A174-4963-AA23-9853F5ABDFB6 (env block overrides F0's stale A10D5A1D). iPad Pro 11 (M5) UDID 653F37B8-9FA1-48AE-BE7E-47E2F3AD982C for tablet shots (landscape).
