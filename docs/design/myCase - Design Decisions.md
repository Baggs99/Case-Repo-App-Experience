# myCase — Design Decisions (handoff)

Canonical record of every decision that survived review. Part I: iPhone (2026-07-16). Part II: tablet (§7, 2026-07-17).
Product spec: `uploads/2026-07-16-mycase-ux-tree-design.md` (IA + flows; two deltas below).
Live design: `myCase Mobile.dc.html` — a canvas of iPhone frames, newest turn at top.
Brand reference: `extracted/myCase Style Guide.template.html` (readable copy of the bundled upload).

## 0. Deltas vs the July 16 UX spec (owner-decided in review)

1. **Admitted forum is nixed.** No forum anywhere. Community = school standing + groups + connections only. The timeline post-deadline flow ends in *plan reweighting*, never a forum handoff.
2. **No population counts, ever.** Leaderboards show percentiles (91ST / 66TH), not raw ranks; never "of N players/members". Only a small joined cohort (~10, people who know each other) may show literal ranks + points. School-vs-school shows avg member percentile + campus city. Future (owner-flagged, not designed): one performance score = f(accuracy, time, complexity) replaces raw points.
3. **iPhone is drill-forward.** The big "Get cased now" action tray is an iPad-console idea; on phone the drill set is Home's hero and Case gets a slim one-row verb bar.
4. **Done cases are retired.** Once done, a case is spent for you as candidate: greyed out, sorted below a "DONE — YOURS TO INTERVIEW WITH" divider, no badges. Its detail page flips the primary CTA to "Case someone with this"; "Get re-cased anyway" is a faint afterthought ("won't count toward diagnostics").
5. **Recap close-out = required 1–5 rating** (not helpful-Yes/No), same scale as the debrief. Optional feedback-quality thumbs ("Worth it / Thin") for authenticated interviewers.

## 1. Visual system (final = turn-3 language: "calm full glass")

Chosen direction: **1c liquid glass, pared back** — one glass hero card per screen, one or two green marks per screen, everything else flat editorial hairlines directly on the page. Glass is for *chrome and overlays*: top pills, tab bar, sheets, keypads, toasts, the recap close-out. Corners: glass = capsule/rounded; page content = square (style-guide rule holds).

### Tokens
- Fonts: `Archivo` 400–800 (all UI/display), `Source Serif 4` 400/600 + italic (voice: ledes, whys, asides, feedback prose). Every phone-screen root div sets `font-family:'Archivo',sans-serif` (the iOS frame injects SF otherwise — regression to watch).
- Light page bg inside phones: `#EFF2F6` (canon; early screens used `#F3F5F8`/`#EDF1F6`). Ink `#0D1C31`, **muted `#515A66`** (owner overrode `#5E6E86` by direct edit — use `#515A66`), faint `#A9B4C4`, hairline `#C9D2DF` (secondary `#DDE3EB`), surface `#FFFFFF`.
- Dark (session takeover only): bg `#081222`, surface `#101E36`, ink `#E9EEF5`, muted `#7C8CA8`, faint `#3D5075`, line `#24365A`, green `#2FC07E`.
- Green `var(--green)` (default `#1B9A5F`) is scarce: live dots, DAY streak tag, FOCUS/FOR YOU/VERIFIED labels, TODAY dot, filled rating cells, active-tab dot. Cobalt `#2E56C0` links only.
- CSS vars on body (host tweaks sync to them): `--green`, `--gblur` (default 20px), `--gbg` = `linear-gradient(135deg,rgba(255,255,255,.66),rgba(255,255,255,.4))`. `body.solid` (reduce-transparency tweak) forces `--gbg:#FFFFFF; --gblur:0px`.

### Glass recipes (copy verbatim)
- **Panel/sheet/tab bar** (light): `background:var(--gbg);backdrop-filter:blur(var(--gblur)) saturate(1.7);-webkit-backdrop-filter:…;border:1px solid rgba(255,255,255,.68–.75);box-shadow:0 18px 44px rgba(13,28,49,.16),inset 0 1.5px 0 rgba(255,255,255,.85),inset 0 -1px 0 rgba(255,255,255,.3)`. Radius: sheets 32–34, cards 26–30, bars/pills 999.
- **Glass key/chip/secondary button**: `background:rgba(255,255,255,.55);backdrop-filter:blur(12px) saturate(1.6);border:1px solid rgba(255,255,255,.75);box-shadow:0 2px 8px rgba(13,28,49,.07),inset 0 1px 0 rgba(255,255,255,.9)`; radius 16 (keys/cells) or 999 (chips/buttons).
- **Dark glass** (takeover): `background:rgba(16,30,54,.6);backdrop-filter:blur(16px) saturate(1.4);border:1px solid rgba(233,238,245,.14);box-shadow:0 14px 34px rgba(0,0,0,.35),inset 0 1px 0 rgba(233,238,245,.12)`.
- **Scrim under sheets**: `rgba(13,28,49,.34)` + `backdrop-filter:blur(5px)`; sheet animates `rise .32s cubic-bezier(0.22,1,0.36,1)`.
- Glass needs something behind it: each screen has 1–2 faint radial tint blobs (green/cobalt ≤ .09–.18 alpha) + one giant faint staircase path (`stroke #C9D2DF/#B7C3D4, sw 0.6, opacity .5`) bleeding off-canvas.

### Recurring chrome
- **Top pills** (floating, y=66): left wordmark chip (mark svg + serif-italic "my" + Archivo-800 "Case"), right avatar pill (40px glass, 28px ink circle "AO"). Sub-pages use `‹ Back` text + small slate context label instead.
- **Tab bar**: floating glass capsule (left/right 12, bottom 12, h 64), five slots: HOME · LIBRARY · [CASE raised 56px ink circle, mark in chalk→green gradient, translateY(-13px)] · COMMUNITY · DRILLS. Labels 9px/600/.12em; active = ink weight-800 (Home adds a 4px green dot; Case-active adds `box-shadow:0 0 0 2px var(--green)` ring on the circle); inactive `#515A66`. Content scrolls behind the bar (bottom padding 120–130).
- **Header scroll fade**: a 34px `linear-gradient(180deg,#EFF2F6 22%, transparent)` strip overlaying the top of every scroll container (zero-height wrapper + absolute inner, pointer-events none) — content fades out under the H1 instead of hard-clipping. Applied on Drills + Community; owner wants it, roll out to all tabs when touched.
- Hidden scrollbars everywhere inside phones: `scrollbar-width:none` on every overflow container and chip row.
- Toast: capsule `rgba(13,28,49,.94)` chalk text, bottom ≈ 92 (above tab bar), auto-dismiss ~2.4s. Dark screens invert (`rgba(233,238,245,.96)` on ink).

### The mark & motion
- Staircase path (only icon in the system): `M4 35 H15 V25 H26 V15 H37 V4 H45`, viewBox `0 0 48 40`, gradient ink→green (`userSpaceOnUse x1=0 y1=15 x2=0 y2=4`), length 74 (draw via dasharray/dashoffset 74, `drawpath .9s`).
- Onboarding progress = the mark drawing itself: dashoffset `74 − 74·(step/5)` next to "STEP N OF 05".
- **Timeline is a literal stepped line** (owner call): svg `viewBox 0 0 320 64–80`, `preserveAspectRatio:none`, path like `M2 58 H96 V42 H192 V24 H276 V8 H318`, ink 2px with `vector-effect:non-scaling-stroke`, green `TODAY` dot at origin, firm labels in a 3-col grid beneath (firm · date / days / one readiness tag, only McKinsey's ON PACE is green).
- Motion: `rise` 420ms `cubic-bezier(0.22,1,0.36,1)` 16px up, staggered ~120–150ms; hovers 160ms 1px lift; keypad/rating presses `scale(.96)`; blinkdot 1.1s for live. Nothing bounces.

### Type on phone (min sizes in use)
H1 tab 28/800/-.03em · takeover display 32–40/800 · card title 20/700 · row title 13–14.5/600–700 · kicker 9.5–10/600/.15–.18em caps · meta 11–12 · serif voice 12.5–16.5 · timers/numbers tabular-nums always. Buttons: primary = ink capsule h 46–52; secondary = underlined text (never outlined boxes); one filled button per screen where possible (recap gate card + verb bar primary are the sanctioned exceptions).

## 2. Screen inventory (canvas anchors → state prefix in the DC logic)

Newest first in `myCase Mobile.dc.html`. Each option id is the wrapper's `id` attr; interactive state lives in one `Component` class, suffix-namespaced. Shared tick: `ensureTick()` — **re-arm interval on every timed entry point** (hot-reload never re-runs componentDidMount; there is a `componentDidHotReload` hook too).

- **8a Guest interviewer path** (`gView/g*`): link-gate (no chrome) → guest console-lite (clock, read-aloud, one release) → post-session "keep it on a record?" → "On the record". Log-in button currently routes like guest (variant not designed).
- **8b Interviewer phone console** (`iv*`): 6-stage chips (data `IVSTAGES`: Opening/Clarify/Framework/Quant+2 exhibits/Brainstorm/Close), serif read-aloud, exhibit Release→`SENT · mm:ss`/Recall, one 1–10 score strip + evidence note per stage, bottom glass bar Previous / Display PDF / Next(Finalize). Clock starts on tap (`ivOn`, starts 11:30).
- **7a Avatar sheet** (`av*`, `notifOn`): glass sheet over dimmed page — profile header+Edit, Linked accounts (LINKED), School (VERIFIED), Notifications toggle (style-guide pill), Sign out; **"Administer a group" buried bottom-right, faint** → create flow (name input → "YOU'RE THE ADMIN").
- **7b Timeline detail** (`tl*`): headline "Fifty-eight days.", big stepped line, per-firm readiness rows, add-a-firm chips (Kearney/OW/LEK/Strategy& — appends "Set date" rows), passed-deadline prompt: Did you interview? → Offer(green record card) / No offer(reweight: "quant drills daily, two extra cases before BCG") / Waiting(ask again in a week) / No(drops off the line).
- **6a Community** (`cm*`): hero = Wharton card (№2 THIS WEEK, 69.8 avg pctl, "your gauntlet counts"); YOUR GROUPS → C-14 group page (weekly points board w/ streak col, TOP FIVE ADVANCE, live nights, serif note: member progress admin-only, leadership transfers); CONNECTIONS rows (S. Park FREE NOW green, T. Becker, M. Lindqvist). *(Forum removed.)*
- **6b Recap gate** (`rc*`): report page (rubric bars 7/5/8/6 + five serif paragraphs from T. Becker + attached PDF row); floating glass close-out sheet over the scroll: locked line "Read to the end — N% of the way there" (unlocks at scrollBottom−16) → RATE THIS CASE 1–5 glass cells (required) + thumbs → Close → "Gate cleared." (candidate seat reopens; recap stays in History).
- **5a Library** (`lib*`): type chips (All/Market entry/Profitability/M&A/Sizing) + Everything/Not done/Done text toggles + live count "N OPEN · N DONE"; open rows first, retired greyed below divider; case detail: rating+runs, your history, case-pack PDF row (striped thumb, "It knows." joke stays), CTA per §0.4.
- **5b Drills** (`d*`): gauntlet hero (six types grid, DAY 12, begin→re-run label), 3-question mental-math run (real clock, progress bar) → percentile result (mark draw, +pts, 3RD IN C-14, weak-section CTA "Practice market sizing"), 16-bar 4-week trend (last bar green), scoped board `boards(s)`: C-14 / WHARTON / GLOBAL / SCHOOLS per §0.2. Header has the scroll fade.
- **4a Session takeover, candidate** (`stepL/nego/live*/fb/rate/swap`): dark throughout until debrief returns to light. Lobby (seats w/ READY/JOINED) → negotiation (their pick; counter once → "THEY KEPT THEIR PICK" — rule demoed) → LIVE: glass clock pill, striped interviewer pane, CASE/EX pills w/ new-dot, exhibits auto-release at 0:08/0:20 (toast), Nordic volumes table + unit-cost bars → End → debrief: 7.2 avg, bars, feedback line, required 1–5 (clears gate), Schedule next (pre-filled) / Swap roles (→ "invite sent") / Close-logged.
- **4b** static live frame (Exhibit 01 open) for commenting.
- **3a Home — drill-forward (CANON)** (`rec3a`): date kicker + "Morning, Amara."; glass hero = today's set (streak squares inside, cohort footer); slim dark tonight strip (blink dot, Details); flat DIAGNOSTIC block (4 bars, FOCUS tag on Market sizing 5.1) merged with "Next case for the gap" + Swap; flat stepped TIMELINE block.
- **3b Case — calm spine (CANON)** (`*3`): slim glass verb bar (filled "Get cased now" + text "Case someone"/"Schedule"); recap-gate card (only card); flat NEXT UP (swap), UPCOMING rows (accepts animate in), PENDING rows w/ text Accept/New time/Decline + dashed-era sent row "awaiting reply", HISTORY rows. Three glass sheets: **Get cased now** (QR square + code K7Q-4TN, live-now board w/ Ping→"expires in 2 h", copy-link), **Case someone** (Scan QR primary, open invites, interviewer log, "never gated" note), **Schedule later composer** (WHO chips / WHEN quick-picks Now·1h·Tonight 8pm·Pick a time / CASE: Interviewer decides ⟂ Request:[rec], serif "The app is the calendar, not the conversation").
- **2a/2b** first Home/Case pass — **superseded by 3a/3b**, kept for comparison only (2b carries owner direct-edit width/height artifacts; don't propagate).
- **1a/1b/1c** glass-extent exploration (welcome + passcode). Owner picked **1c(+1d)**, then calmed it in turn 3.
- **1d Onboarding, interactive** (`stepD/authM/code*/school*/joined*`): welcome → email passcode (working glass keypad, auto-advance at 6) → profile import (LinkedIn/Google skip code) → school verify (send code → keypad → VERIFIED banner) → group join (C-14 etc.) → "You're in." summary. **Still in 1b-era styling — pending retrofit to turn-3 language (bg #EFF2F6, #515A66 muted, calmer greens).**

## 3. Data & persona (keep continuity)

Amara Osei ("AO"), Wharton MBA '27, Cohort C-14 (led by R. Vance), day-12 streak, 6th of 10 in cohort, 8 behind №5 (points 331 base). Diagnostic: Structure 8.2 · Communication 7.4 · Quant 6.8 · Market sizing 5.1 (FOCUS). Tonight 19:00: candidate vs **M. Lindqvist (LBS)** — "Low-cost carrier enters the Nordic market" (Kellogg 2019, D4; exhibits: 14.0M pax/€95 avg table; unit costs Skanwing 4.1/NorAir 5.3/FinnJet 6.0). Recommendation `RECS[0]`: "EV charging — size the German market" (Stern 2024, D3). Unread recap: Ski resort profitability, T. Becker, 4.1/5, "Structure held. The quant went soft in the middle — drill it before Thursday." Pending: T. Becker Thu 18:00 dental roll-up; S. Park tonight 21:30 (asks you to interview; also FREE NOW). Timeline: McKinsey Sep 12 (58d, ON PACE) · BCG Sep 30 (76d, PUSH QUANT) · Bain Oct 08 (84d, EARLY); passed: Roland Berger Jul 02. Firms/deadline copy lives only here — one source.

## 4. Host tweaks (data-props on the DC)

`accent` (color: #1B9A5F | #0F8A72 | #2E56C0 → syncs `--green`), `glassBlur` (6–32px → `--gblur`; owner previewed 25), `reduceTransparency` (bool → `body.solid`). Don't add tweaks for copy/single colors.

## 5. Rules that keep biting (checklist for edits)

1. Owner edits in the file are law (e.g. #515A66 labels, a 40px-radius button, 2b size artifacts) — never revert silently.
2. Every screen root inside `IOSDevice` needs explicit Archivo.
3. Any new timed state must call `ensureTick()` on entry.
4. New scroll containers: `scrollbar-width:none` + consider the header fade + 120px+ bottom padding above the tab bar.
5. One glass hero per screen; greens ≤ 3 per screen; kickers slate by default, green only when it *means* something.
6. No chat, no forum, no head-counts, no icon sets/emoji (staircase only), square content corners, secondary = underline.
7. Timers/scores always `font-variant-numeric:tabular-nums`.
8. Unique svg gradient ids (g1…g25 used so far).
9. Options canvas: new work = new `<section>` on top, ids `{turn}{letter}`, badges + serif captions; never touch earlier sections except demotions of padding.

## 6. Not yet designed (next up)

- **Web**: left sidebar (collapsible) instead of tab bar; console fully in-browser for guests; QR pairing + 6-char code fallback.
- Login variant of the guest gate; notification settings detail; empty/expired/missed states; unified performance score (owner: "later").
- Tablet extras: avatar sheet, negotiation/debrief takeover, portrait orientation.

## 7. Tablet — `myCase Tablet.dc.html` (canvas, newest turn on top)

Same tokens, glass recipes, chrome rules and hard rules as Part I. Everything below is tablet-specific.

### Frame & chrome
- **Bezel is hand-rolled** (no iPad starter): outer div `width:1194;border-radius:44;background:#000;padding:16;box-shadow:0 40px 80px rgba(0,0,0,.18),0 0 0 1px rgba(0,0,0,.12)`; inner screen `height:802;border-radius:28;overflow:hidden`. Status bar = `<x-import component-from-global-scope="IOSStatusBar" from="./ios-frame.jsx">` absolutely positioned at top (pointer-events none); home-indicator pill (139×5, `rgba(0,0,0,.25)`) bottom-center; **no dynamic island**.
- Tab pages: top row at y≈58 = wordmark glass chip (left) · page H1 26/800 (center) · avatar chip (right). Tab bar = the same 5-slot glass capsule, **560px wide, centered**, bottom 14. Content `padding:22px 28px 110px`, two-column `grid 1fr 1fr gap 36`, columns split by hairline or none; Library uses `1fr 470px` master–detail with a divider border.
- Master–detail replaces phone drill-ins wherever a right pane fits (Library detail, Community group page). The drill *run* stays a phone habit — tablet Begin buttons are visual.

### Screens (anchor ids → state prefixes; one logic class, `ensureTick()` + `componentDidHotReload` rule applies)
- **1a Interviewer console — the hero** (`tm* sg* st* sc* rel pdf*`): top bar = mark+wordmark | case kicker+title | CANDIDATE Amara Osei | master-clock glass chip (tap-to-run, starts 12:34, shows `MM:SS + N LEFT`, remain turns green under 5 min) | ink "Finalize & send". 2px cap-progress bar (45-min CAP). Body `grid 1fr 380px`:
  - Left: 7 stage chips (`STAGES`: Behavioral, Opening, Clarify, Framework, Quant [exhibits e1+e2], Brainstorm [e3], Close — reference console text verbatim); READ ALOUD serif 19/1.55 max-620; exhibit rows (Release to candidate → `SENT · mm:ss` from master clock / Recall); GUIDANCE dashes; "SCORE THIS STAGE" 2px-ink block — per-stage dims (12 total in `DIMS`) each with desc, 24px 1–10 square cells (≤score = green), serif-italic evidence input. Footer: Previous · glass "Display PDF — always here" pill · ink Next stage/Finalize.
  - Right rail 380px: candidate feed 224h (ink, stripe pattern, LIVE chip, name tags, self-view 118×66) → SEGMENT TIMER (34px clock, Start/Pause, "Stop · log" appends `Segment 0N` laps list) → RUBRIC — LIVE: all 12 dims, 16px mini-cells (same `scSet` handler both places), current-stage dims ink / others slate, running avg top-right green.
- **1a PDF mode** (`pdfOn/pdfPage`): overlay covers the **left pane only** (rail + clocks stay live) on `#E7EBF1`; toolbar "CASE PACK — INTERVIEWER COPY · 8 PAGES" + serif line "The script keeps scoring; this is the paper." + ink "‹ Back to script"; centered 566px white page (hairline border, `0 18px 40px` shadow, padding 40/46). Three authored pages: 01 brief (2px-ink header rule, background/ask paras, timing plan 0–44 min), 02 Exhibit 01 (volumes/fares table, **Release button synced with the script's e1 state**, source footnote), 03 answer key (green `INTERVIEWER ONLY`, quant chain 14M×8%→€80.75→≈€90M vs €120M, grading notes serif). Pager: `PAGE 0N OF 08` (page 3 appends "— 04–08 IN THE FULL PACK"), prev/next grey out at ends.
- **1b Case** (`recT tProp pingT toastT`): the owner's tray, home at last — glass tray hero: 300px verb column (ink "Get cased now" + two glass verbs) | vertical divider | inline LIVE-NOW board ("PINGS EXPIRE IN 2 H", Ping buttons toast). Below, two-column spine: left = recap card → NEXT UP (Swap) → UPCOMING (tonight + accepted rows rise in); right = PENDING (Accept/New time/Decline text actions; accept crosses columns) → HISTORY. Case tab-circle gets the green ring.
- **2a Home** (`recH/swapH`): left = gauntlet hero card + dark "LAST NIGHT — LOGGED" strip (7.2 avg · recap rated 5/5 · Re-read) + UPCOMING row; right = DIAGNOSTIC flat block (bars 8.2/7.5/6.6/5.3-FOCUS + "Next case for the gap" + Swap) + stepped-line TIMELINE block.
- **2b Drills** (`dScope/pickDScope`): left = gauntlet hero (six types grid) + 4-week trend (72px bars); right = the scoped board — C-14 (ranks+points, TOP FIVE divider) / WHARTON (percentiles) / GLOBAL (percentiles + `···` gap row) / SCHOOLS (campus subs) — same percentile-not-headcount copy as phone.
- **2c Library** (`libType/libDone/libSel`): left = type chips + Everything/Not-done/Done toggles + `N OPEN · N DONE` + rows (retired greyed below "DONE — YOURS TO INTERVIEW WITH"); selected row `rgba(255,255,255,.55)`. Right pane = always-visible detail (tag line incl. `OPEN FOR YOU` fallback, rating·runs, history, case-pack row, CTA per retired rule).
- **2d Community** (static): left = Wharton hero card (№2 · 69.8) + CONNECTIONS (S. Park FREE NOW · T. Becker today 18:00 · M. Lindqvist "swap invite pending") + YOUR GROUPS pointer; right = C-14 group page permanently open (points board w/ streak col, live-week, admin-only serif note).

### Tablet data day-advance (July 17 — one day after Part I; keep both frames' internal consistency)
DAY 13 streak (15th square dark-ink pending); last night's Nordic session done: 7.2 avg, recap rated 5/5; next session T. Becker **today 18:00** (T-9H, green); McKinsey 57d / BCG 75d / Bain 83d; diagnostic 15 cases, Quant 6.6, Sizing 5.3; cohort: you 335 pts, 4 behind №5, +2; school standing 88TH; `CASES.nordic.hist = 'Jul 16 · M. Lindqvist · 7.2 avg'`, `dental.sched = 'Today 18:00 · T. Becker'`. Mobile file stays on July 16 — don't cross-pollinate.
