# Plan — myCase branding: identity fix + ship the logo (incl. Liquid Glass icon)

Created: 2026-07-16 · Owner: Thomas · Status: DRAFT (awaiting bundle-ID confirm)
Branch: TBD at execution (new `feature/branding` off `feature/caseroom`, or fold
into the pre-merge iOS branch — decide when starting).

## Context / why
- **myCase is the product; CaseRoom is a feature inside it.** Today the iOS app
  has no display name (home screen reads "CaseRoom") and an **empty** app-icon
  slot.
- **`studio.ogee` is the wrong identity.** It was hard-coded as a default in the
  2026-07-12 P1 iOS plan (`bundleIdPrefix: studio.ogee` = reverse-DNS of Thomas's
  unrelated *ogee* domain) and copied verbatim through P1–P4 into the app bundle
  ID, widget bundle ID, App Group, APNs topic, and deep-link scheme. It is **not
  yet registered in Apple's portal**, so this is the last cheap moment to fix it
  (bundle IDs are permanent once shipped to the App Store).
- The brand mark already exists: `webapp/static/favicon.svg` — a theme-aware
  gradient staircase (ink `#0D1C31` → uptick-green `#1B9A5F`; dark-mode variants
  `#E9EEF5` / `#2FC07E`). Single stroked glyph, viewBox 48×48 — ideal for a
  layered Liquid Glass icon.

## Toolchain (grounded, checked 2026-07-16)
- SVG→PNG: **Playwright headless render** (already vendored, zero new deps).
  Fallback: `pip install cairosvg` into `.venv` (dev-only).
- Liquid Glass: **Icon Composer.app is present in Xcode 26** (GUI only — no CLI).
  Plan: hand-author the `.icon` bundle (layer PNGs + `icon.json` manifest) and
  verify by opening in Icon Composer / building on the iPhone 15 Pro; a ~2-min
  GUI assemble+export by Thomas is the fallback if the hand-authored manifest
  doesn't validate.

## Rename surface for `studio.ogee` → `<NEW_PREFIX>` (small)
- `ios/project.yml` — `bundleIdPrefix`, app `PRODUCT_BUNDLE_IDENTIFIER`, widget
  `PRODUCT_BUNDLE_IDENTIFIER`, App Group (×2 entitlements blocks), `CFBundleURLName`.
- `ios/CaseRoom/Support/CaseRoom.entitlements` + `ios/CaseRoomWidgets/
  CaseRoomWidgets.entitlements` — regenerated from project.yml on `xcodegen`.
- `ios/CaseRoom/Support/Info.plist` — regenerated from project.yml.
- `ios/CaseRoom/Shared/AppGroup.swift:16` — `static let id` constant (hand-edit).
- `.env` (when push is set up) — `APNS_BUNDLE_ID` must equal the new app bundle.

---

## Phase 0 — Fix the app identity  ⚠️ ONE-WAY DOOR — confirm string first
Replace `studio.ogee`. Owner prefers the **mycase.app** identity → reverse-DNS
bundle ID **`app.mycase`** (app), `app.mycase.widgets` (widget), `group.app.mycase`
(App Group). NB: bundle ID is independent of the API host — `mycase.study` hosting
is unaffected. Deep-link scheme: default keep `caseroom://` (internal, users never
see it; less Swift churn) — optionally `mycase://`.
- Edit the rename surface above; `cd ios && xcodegen generate`.
- **Done when:** `grep -rn studio.ogee ios/` is empty; `xcodebuild ... test`
  (iPhone 17 sim) = 273/0; App Group container still resolves (or falls back to
  `.shared` in the unprovisioned sim, tests unaffected); deep link still routes.

## Phase 1 — Display name → "myCase"  (cheap)
- Add `CFBundleDisplayName: myCase` to `project.yml` app-target `info.properties`;
  regenerate.
- **Done when:** a sim/device build shows **myCase** under the icon.

## Phase 2 — App icon, flat 1024 (unblocks a branded demo immediately)
- Render the staircase onto an **opaque** branded 1024×1024 tile via Playwright
  (background = brand surface; glyph centered on Apple's icon keyline, ~10%
  margin; gradient stroke). Drop into `AppIcon.appiconset` (1024 slot already
  declared).
- **Done when:** app builds with the myCase staircase icon on every iOS version.

## Phase 3 — App icon, Liquid Glass (iOS 26, the "cool" version)
- Produce layered art: background layer (brand gradient) + foreground layer
  (staircase glyph tuned for glass specular). Hand-author the `.icon` bundle;
  enable light/dark/tinted/clear variants. Keep Phase-2 flat PNG as the
  iOS 17–25 fallback.
- **Done when:** on the iPhone 15 Pro (iOS 26) the icon renders Liquid Glass
  (translucency/specular, adapts light/dark/tint); older iOS shows the flat
  fallback.

## Phase 4 — Launch screen + in-app mark
- Launch screen: staircase centered on brand background (`UILaunchScreen`).
- In-app: place the mark on the login/onboarding header (ship SVG as a vector
  PDF in the asset catalog for crisp scaling; reuse existing Brand color sets).
- **Done when:** launch + login show the myCase mark, correct in light/dark.

## Phase 5 — Verify + record
- Full iOS suite green; build+install to sim; visual pass. Commit on the branding
  branch. Update PROGRESS.md + memory.
- **Done when:** 273 iOS tests pass; branded build boots; committed (not pushed —
  Thomas merges).

## Thomas — manual (can't be automated)
1. In Xcode, select your Apple team on **both** targets (signing).
2. Register the **new** App ID (`study.mycase`) + App Group (`group.study.mycase`)
   in the Apple portal — with the corrected id, not `studio.ogee`.
3. Only if the hand-authored `.icon` fails to validate: a ~2-min assemble+export
   in Icon Composer.

## Demo config (device build)
- API_BASE_URL target = **`http://10.66.142.109:8077`** (Thomas's LAN as of
  2026-07-16; DHCP-transient — re-check `ipconfig getifaddr en0` before a device
  build). Set in BOTH app + widget `info.properties` (currently `127.0.0.1`).

## Open decision (blocks Phase 0 execution)
- Confirm the exact bundle ID: **`app.mycase`** (recommended, = mycase.app in
  reverse-DNS) vs literal `mycase.app`. And scheme `caseroom://` (keep) vs
  `mycase://` (default: keep).
