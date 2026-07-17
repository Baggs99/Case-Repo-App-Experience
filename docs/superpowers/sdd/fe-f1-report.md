# F1 — Shell & Navigation · Phase Report

**Status:** DONE · **Branch:** `fe/f1-shell` · **Head:** `f65fb94` (base `000f0c8`)
**iOS suite:** 289 → **313** green (0 failures) · +24 tests (AppRouterTests 15, profile/settings 5, AvatarSheetViewModelTests 4)
**Backend suite:** **655** green (0 failures) — no backend files changed this phase (iOS-only)
**Entry points remapped:** 8 distinct steering sources (2 widget `caseroom://` URLs, 5 push kinds, 3 App Intents) + APNs registration — all kept working
**Date:** 2026-07-17 · Plan: `docs/superpowers/plans/2026-07-17-fe-f1-plan.md` · Ledger: `.superpowers/sdd/f1/progress.md`

Replaced the legacy 4-tab `RootTabView` with the canonical 5-slot floating-glass shell (HOME · LIBRARY · ⬤CASE · COMMUNITY · DRILLS + avatar sheet, no You tab), installed F0's chrome as the app shell, routed every audited deep-link/push/App-Intent onto a pinned `AppRoute` registry, and shipped the avatar sheet (canvas 7a) on B5's endpoints — with existing content re-homed so the app stays fully functional mid-transition.

---

## Tasks (each: fresh implementer → fresh Opus reviewer, all APPROVE)

| Task | Model | Scope | Commit | Review |
|---|---|---|---|---|
| Plan | opus | Plan + 2 review rounds (fixed 2 CRIT/1 IMP/7 MIN) | `be346f2` | APPROVE (rd 2) |
| 1 | opus | AppRoute registry + AppRouter + entry-point remap | `78e7e4e` | APPROVE |
| 2 | sonnet | Profile/notification-settings models + APIClient (B5) | `773c7df` | APPROVE |
| 3 | opus | Avatar sheet (canvas 7a) + view-model | `f7bf899` | APPROVE |
| 4 | opus | RootShell — chrome + re-home + router wiring (phone) | `176fa70` | APPROVE |
| 5 | opus | iPad variant — 560pt bar + wordmark\|H1\|avatar | `be2894c` | APPROVE |
| Close-out | opus | Doc sweep + whole-branch review | `891583f`/`f65fb94` | APPROVE (0 CRIT/0 IMP/6 MIN) |

Plan review round 1: REQUEST_CHANGES — 2 CRITICAL (the `AppRoute`→`DeepLink` rename left `RootTabView` referencing the renamed symbol → module wouldn't compile; the switch-based shell re-created `TodayView` so the drill widget/intent stopped opening the drill sheet) + 1 IMPORTANT (Task 2 tests referenced invented stub helpers) + minors; all fixed. A synchronous round-2 re-check caught a 4th token-less compile site (`RootTabView`'s `pending`-onChange) and a cold-launch gap (drill `onChange` needed `initial: true`) — both folded before dispatch.

---

## Interfaces — PINNED for F2–F10 (names + signatures stable)

### Route registry — `App/AppRoute.swift`
```swift
enum AppRoute: Hashable {
    case home, library, caseTab, community, drills   // tabs
    case avatarSheet                                  // modal sheet
    case timelineDetail                               // F2 push (homePath)
    case caseDetail(Int)                              // F4 push (libraryPath)
    case recap(Int)                                   // sessionID — F5 presentation
    case sessionTakeover(Int)                         // sessionID — fullScreenCover (F5/F6)
    case groupPage(Int)                               // group id — F8 push (communityPath)
    case drillRun                                     // F7 drill run
}
var AppRoute.owningTab: DSTab?   // nil for avatarSheet + sessionTakeover
```
Cases are contract §6 verbatim. **Later phases add cases ONLY via their brief.** Distinct from F0's `DSTab` (tab identity) and from `DeepLink` (steering-source parsing).

### Central router — `AppRouter` (singleton, `@Observable @MainActor`), in `Intents/CaseRoomIntents.swift`
```swift
static let shared: AppRouter
var selection: DSTab               // bound to the shell's tab switch
var avatarSheet: Bool              // → AvatarSheetView sheet
var proposeToUserID: Int?          // → ProposeNowView sheet (free_now push)
var sessionTakeoverID: Int?        // → SessionView fullScreenCover (F5/F6 refit)
var drillRun: Bool                 // → shell-owned DrillView sheet (initial:true, cold-launch safe)
var homePath, libraryPath, casePath, communityPath: [AppRoute]  // per-tab nav stacks (F2/F4/F5/F8 mount)
var pending: AppRoute?             // App-Intent inbox; shell drains via go(to:)
func go(to: AppRoute)
func handleDeepLink(_ link: DeepLink)   // caseroom:// + push fold
func handlePush(_ route: PushRoute)     // notification tap
```

### Steering-source parser — `DeepLink` (was the legacy 4-case `AppRoute`), in `Intents/CaseRoomIntents.swift`
```swift
enum DeepLink: Equatable { case drill, sessions, proposeTo(Int), freeNow }
init(_ pushRoute: PushRoute)                 // .proposals/.session → .sessions; .proposeTo → .proposeTo
static func route(from url: URL) -> DeepLink?  // caseroom://drill|sessions|freenow
```
Parse behavior is byte-identical to the pre-F1 enum (IntentsTests + PushRouteTests unchanged in semantics; the 8 assertions were mechanically repointed `AppRoute`→`DeepLink`).

### Shell — `App/RootShell.swift` (replaces `RootTabView`)
ZStack shell: `DSBackground` + selected-tab content (switch on `router.selection`) + floating F0 chrome (`WordmarkChip` top-leading, tappable `AvatarPill` top-trailing → `router.avatarSheet`, `DSTabBar` bottom). Size-class-adaptive: `.regular` (iPad) uses `DSTabBar(maxWidth: 560)` + a `wordmark | H1 | avatar` top row; `.compact` keeps the phone corners. Owns the drill sheet, the propose sheet, the session-takeover `fullScreenCover`, and the avatar sheet. Steering sources wired: `.onOpenURL`→`handleDeepLink`, `pushCoordinator.pendingRoute`→`handlePush`, `router.pending`→`go(to:)`.

### Profile/settings API — `Networking/{Models,APIClient}.swift` (B5)
```swift
struct ProfileDetail: Codable, Equatable { id:Int; email:String; displayName,bio,linkedinUrl,school,photoUrl: String? }
struct NotificationSettings: Codable, Equatable { proposals,sessionReminders,feedback,freeNow,community: Bool; var allEnabled }
protocol ProfileService { profile(); updateProfile(displayName:bio:linkedinUrl:); uploadProfilePhoto(data:mime:)->String; notificationSettings(); updateNotificationSettings(_:) }  // APIClient conforms
```
Shapes match B5 exactly (snake_case via `.convertFromSnakeCase`); photo upload is multipart field name `file` → `{photo_url}`.

### Avatar sheet — `Views/AvatarSheetView.swift` + `State/AvatarSheetViewModel.swift`
Canvas 7a on the B5 endpoints. `AvatarSheetView(viewModel:)` is injectable (default = live). `AvatarSheetViewModel.setNotifications(_:)` = the master toggle (writes all 5 categories, optimistic w/ revert).

---

## Entry-point remap (every audited source kept working)

| Source | Steering (`DeepLink`/`PushRoute`) | Router destination |
|---|---|---|
| `caseroom://drill` (Streak widget) + `StartDrillIntent` | `.drill` / `pending=.drillRun` | `.drillRun` → Home + shell drill sheet |
| `caseroom://sessions` (NextSession widget) | `.sessions` | `.caseTab` |
| `caseroom://freenow` | `.freeNow` | `.caseTab` |
| push `proposal` | `PushRoute.proposals`→`.sessions` | `.caseTab` |
| push `accepted`/`knock`/`feedback`/`starting_soon` | `PushRoute.session(id)`→`.sessions` | `.caseTab` |
| push `free_now` (user_id) | `PushRoute.proposeTo(id)` | `.caseTab` + ProposeNow(id) |
| `NextSessionIntent` | — (spoken dialog) | no nav (unchanged) |
| `ToggleFreeNowIntent` (Siri / Action button / widget button) | — (toggles free-now in-process) | no nav (unchanged) |
| APNs device registration (AppDelegate) | — | `registerDevice(token:)` unchanged |

---

## Design decisions (locked; reviewer-confirmed)

1. **Drill run is Home-hosted transitionally + owned by the shell.** `caseroom://drill` / StartDrillIntent → `.drillRun` presents `DrillView` from `RootShell` (`@State presentedDrill`, `.onChange(of: router.drillRun, initial: true)` — cold-launch safe), so it opens from any tab/cold launch. F7 moves it to the DRILLS tab. TodayView's drill card routes through `AppRouter.shared.go(to: .drillRun)`.
2. **Avatar notifications = single master pill** (writes all 5 B5 categories; display = `allEnabled`). The granular per-category screen is undesigned (Decisions §6). Optimistic flip w/ revert.
3. **School VERIFIED ⇐ non-empty `profile.school`** (B5 school is registry-verified, read-only). **Linked accounts LINKED ⇐ `linkedin_url` present** — see backend gap below.
4. **"Administer a group" → `AppRouter.shared.go(to: .community)`** as the interim (F8 swaps in its create-group route; the route enum ships now, marked with an F8 seam comment).
5. **Detail routes are honest seams:** `.caseDetail(id)` pushes onto `libraryPath` (real `CaseDetailView` when F4 mounts the stack); `.timelineDetail`/`.recap`/`.groupPage` select the owning tab for F2/F5/F8; `.sessionTakeover(id)` presents the real `SessionView` in a `fullScreenCover` (F5/F6 refit to the dark takeover). No fake placeholder screens — Community/Drills tabs are labeled text stubs (F7/F8 fill).

---

## Screenshot verdict
`.superpowers/sdd/f1/shots/` — phone (iPhone 17): `task4-{home,library,case,community,drills,avatar}.png` (real logged-in content) + `task3-avatar-sheet.png` (populated 7a persona); iPad (iPad Pro 11"): `task5-ipad-{home,avatar}.png` (portrait — macOS TCC blocks osascript rotate, F0-documented fallback; the 560 bar + top row are orientation-agnostic). Reviewer-verified vs canvas: floating 5-slot glass bar w/ raised navy CASE circle + chalk→green staircase mark + active states (HOME green dot, CASE green ring, active label ink-800); WordmarkChip + AvatarPill top pills; iPad 560pt centered bar + `wordmark | H1 | avatar` top row (§7); avatar sheet matches 7a (header+Edit, LINKED, VERIFIED, green notifications pill, Sign out, faint "Administer a group"; greens = 3 at the ≤3 ceiling).

## Deviations (all documented, reviewer-approved)
- **DEBUG launch hatches** (`#if DEBUG`, Release-inert — the push-auth/APNs path is unchanged in Release): `-AvatarSheet` (T3 populated shot), `-DevLogin` (auto-login the seeded dev user for screenshots), `-startTab <tab>`, `-avatarOpen`, and a DEBUG-only skip of `requestAuthorizationAndRegister()` under `-DevLogin` (the sim's un-dismissable permission alert obscured shots). Plus a `#if DEBUG PreviewProfileService` for the T3 persona.
- **`AvatarSheetView.init(viewModel:)`** made injectable (`@MainActor`, nil-default with the live VM built in-body — a plain default-arg fails Swift concurrency isolation).
- iPad screenshots are **portrait** (F0-documented macOS TCC rotate block).

## Follow-ups / concerns (non-blocking — recorded for later phases)
- **Backend gap (recommend a follow-up):** GET `/api/v1/profile` exposes no per-provider OAuth link flags (`google_sub`/`linkedin_sub`), so avatar "LINKED" is derived from the free-text `linkedin_url` — not a true OAuth-link signal. A later phase should surface real link/verify booleans (would also firm up F9's account-completion UI).
- **Notifications toggle** uses a green-tinted system `UISwitch`, not a hand-built "style-guide pill"; **Edit-profile** uses a system `Form` — both are undesigned surfaces (Decisions §6); restyle when designed.
- **Contract-doc prose nit:** §5 F1 brief writes `sessionTakeover(sessionID:)` (labeled) while §6 + the shipped enum use unlabeled `(Int)` — downstream phases call it unlabeled.
- **Per-tab path arrays** (`homePath`/`libraryPath`/`casePath`/`communityPath`) are populated by `go(to:)` but not yet bound to `NavigationStack(path:)` — F2/F4/F5/F8 mount their tab's stack. No F1 entry point reaches a detail route, so no live gap.
- **Cosmetic:** two hex-in-comment lines in F0 files (`Glass.swift:29`, `Chrome/TabBar.swift:84`) are CSS-var/canvas documentation, not color literals — reword so the rubric grep returns truly empty for future reviewers.

## THOMAS MANUAL
None required. On-device run needs your signing (ship tool); the FW2 shell demo checkpoint (ORCHESTRATION.md §7) is ready to ship to your 15 Pro on request. The dev server used for screenshots (port 8077, DB `caserepo_fe_f1`) was shut down at close-out.

## ESCALATIONS
None. No Fable/`deep` consult was used or required.
