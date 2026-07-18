# Phase F8 Report — Community (school standing · groups · connections · group create)

Branch `fe/f8-community` (cut d471fa7, post-FW3). Canvas anchors: **Mobile 6a**, **Tablet 2d**.
Brief: frontend-execution §5-F8. Deltas honored: **§0.1 NO forum**; **§0.2 percentiles-never-headcounts**
(the ONE sanctioned literal population display is the joined-cohort group board — rank + points + streak).

## Bootstrap (baselines matched)
- DB `caserepo_fe_f8`: createdb → schema.sql → migrations 002…035 (ON_ERROR_STOP, clean) →
  `scripts/seed_caseroom_dev.py` (users a/b/c@yale.edu, 3 schools). 35 tables.
- Baselines GREEN, exact match: **backend 655 passed**; **iOS 413 tests / 0 failures** (iPhone 17 (F4));
  `xcodegen generate` idempotent.
- No live dev server needed: populated screenshots use DEBUG fixture-hatch VMs (persona §3 is for
  Previews/UI-test fixtures ONLY; live screens bind the API) — the F1/F4 established pattern.

## Process
Plan → Opus plan-review (APPROVE after 4 required revisions, all folded) → 4 tasks, each a fresh
sonnet implementer → Opus task-reviewer (all PASS, no fix loops needed) → full suites → Opus
whole-branch adversarial review (APPROVE, merge-ready). Every subagent run synchronous.

## Tasks
| # | Task | Commit | Reviewer verdict |
|---|------|--------|------------------|
| 1 | Community API layer + Community tab (phone, 6a) | `d6d7a05` | PASS (0 findings) |
| 2 | Group page (phone, 6a) — board + TOP FIVE ADVANCE + admin note/transfer/progress | `08fb4dc` | PASS (1 non-blocking minor) |
| 3 | Group create flow + avatar-sheet wiring (7a "YOU'RE THE ADMIN") | `d83dc13` | PASS (0 findings) |
| 4 | Tablet Community master-detail (2d) | `d0d137c` | PASS (0 findings) |

## What shipped
- **Networking/CommunityModels.swift** + **APIClient `CommunityService`** (7 methods): `connections()`,
  `groups()`, `createGroup(name:)`, `group(id:)`, `transferGroupAdmin(id:userId:)`, `groupProgress(id:)`,
  `schoolStanding()`. Codable shapes match live `connections.py`/`groups.py`/`leaderboards.py` verbatim
  (incl. `drill_attempts_30d`→`drillAttempts30D` digit-boundary key; nullable school/photo/bio/mean_grade).
- **CommunityView** (phone 6a): one glass school hero (№rank THIS WEEK / avg member pctl / campus city /
  serif "your gauntlet counts"; null-school → muted "no standing" line, no fabricated count), YOUR GROUPS
  (→ `.groupPage(id)`), CONNECTIONS (FREE NOW green; swap-invite-pending decoration from `/connections`).
- **GroupPageView / GroupPageContent** (phone 6a): weekly points board (rank·name·streak·points, all
  tabular; **streak column ink/muted, never green**), **TOP FIVE ADVANCE** divider (1–5 above, 6+ demoted),
  serif admin note, **admin-only** Transfer leadership (underline → member picker → POST transfer) + member
  progress. `isAdmin` derived deterministically from the caller's `members[]` role — defense-in-depth over
  the backend 403. Sub-page chrome (`‹ Back` + slate context label) via generalized `detailOpen`.
- **GroupCreateView** (7a): glass sheet, name input → POST → "YOU'RE THE ADMIN" + invite code. Driven by
  `AppRouter.groupCreate` bool (NO new AppRoute case — §6 enum stays pinned; mirrors `avatarSheet`).
  AvatarSheetView's buried "Administer a group" seam rewired from the F1 interim `go(to:.community)`.
- **CommunityMasterDetailView** (tablet 2d): 1fr | 470pt master-detail (hairline divider) — left
  hero+connections+groups selector (select-on-tap, no push), right permanently-open group page.
  `GroupPageContent(layout:)` shared phone/tablet; phone path unregressed.

## Suites (final, on committed HEAD)
- **iOS: 455 tests / 0 failures** (413 baseline + 42 new F8 VM/model/router tests). TEST SUCCEEDED.
- **Backend: 655 passed** (no backend code touched).

## Evidence (shots under .superpowers/sdd/f8/shots/)
- `task1-community.png` (iPhone 17 F4) — 6a: 1 glass hero, 1 green (FREE NOW).
- `task2-grouppage.png` (iPhone 17 F4) — 6a group page: board + TOP FIVE ADVANCE + admin surfaces, 0 greens.
- `task3-groupcreate.png` (iPhone 17 F4) — 7a create: "YOU'RE THE ADMIN" + invite code C14E-9XJT.
- `task4-ipad-community.png` (iPad Pro 11" F4) — 2d master-detail. **Portrait** (macOS TCC blocked the
  `osascript` landscape rotate — F1-documented; the two-column split + 560pt bar are orientation-agnostic).

## Reject-list audit (whole branch, Opus-confirmed)
No forum; no headcounts outside the sanctioned group board; ≤1 glass hero/screen; ≤3 greens/screen (FREE
NOW is the only chromatic green; streak columns muted); tabular numerals on all scores/points/ranks/codes;
secondaries = underline; square content corners; staircase mark only (no icons/emoji); tokens only (grep
for `#`hex / `Color(red:` clean across the phase diff); copy verbatim from canvas. AppRoute §6 unchanged.

## Deviations (deliberate, sanctioned)
1. Phone CONNECTIONS renders the "swap invite pending" decoration though canvas 6a places it on tablet 2d —
   the field is live on `/connections` (B3 merged); plan-sanctioned with this note.
2. `-GroupPageFixtures`/tablet fixture make Amara admin for the admin-variant screenshot while §3 canon names
   R. Vance cohort lead — admin role and board rank are distinct schema concepts (R. Vance stays №1 ranked);
   no canon conflict.

## Known MINOR (non-blocking — deferred)
- **Admin member-progress recovery**: if `GET /groups/{id}` succeeds but `GET /groups/{id}/progress` fails,
  the MEMBER PROGRESS section shows "Loading…" and the error-banner Retry re-runs `load()` (board) but not
  `loadProgress`, so that section only recovers on re-navigation. Admin-only, transient-failure-only,
  non-crashing. Fix if revisited: have Retry (when admin) also re-invoke `loadProgress`, or render a
  section-local "Couldn't load member progress — Retry".

## Contract note for the orchestrator
- `swap_invite_pending` + `free_now` are sourced from `GET /api/v1/connections` (not `/availability`) —
  both live on this branch (B3 merged: `EXISTS` in `connections.list_accepted`). The B6 report's
  "swap_invite_pending always false" line is stale (pre-B3-merge) and does not affect decode safety.
- The create flow adds `AppRouter.groupCreate: Bool` only; the pinned `AppRoute` enum is untouched.
- `detailOpen` generalized in RootShell (`libraryDetailOpen || communityDetailOpen`) — Library detail
  chrome verified unregressed.

## Scope discipline
No changes to transport/WebRTC/signaling, widgets, App Intents (beyond the one `AppRouter` field),
deep-link registration, e2e scripts, backend, or migrations. `info.properties` untouched. xcodegen re-run
where the target picked up new files; `project.yml` unchanged (folder-referenced sources). NEVER pushed/merged.
