# B1 accumulated Minor findings (from per-task reviews) — for final triage

- m6a: routes/proposals.py:93 accept-handler comment still says "an 8-day-old proposal must expire" — stale after A3 (should reference 2h now / earliest-start windows). Comment-only.
- m6b: sweep_missed 'live'/protected-state exclusion and the 'lobby' branch are untested (only 'scheduled' seeded). WHERE clause is correct; add a 'live'-stays-live and a past-window 'lobby'→missed test.
- m6c: no sweep idempotency/re-run test (second run should be a no-op / return 0).
- m6d: latent naive-datetime ::timestamptz cast in sweep_expired — a client sending an offset-less ISO time stores an offset-less string; (e)::timestamptz then resolves vs the DB session TimeZone GUC, shifting the expiry boundary. Pre-existing input-validation gap; all current tests tz-aware. Consider normalizing to UTC (or requiring tz-aware) in create_proposal/counter_proposal.
- m7a: webapp/push/starting_soon.py:58-71 starting_soon_loop() now dead code (unreferenced); removing it also frees `import asyncio` (line 14). Optional cleanup.
- m8a: mint route create_pair_token doesn't wrap TransitionError(500) → FastAPI returns generic 500, detail lost. Reachable only on 5 consecutive short_code collisions (~1e9 space) — cosmetic.
- m8b: pairing claim repo else-branch raises 400 "provide a token or short_code" but the route pre-guards with 422 — status disagreement; route always intercepts first (harmless, defensive for direct repo callers).
- m9a: REGRESSION webapp/templates/room.html:48 renders `{{ p.case_title }}` unguarded → literal "None" for case-less proposals now surfaced by inbox() LEFT JOIN. Cosmetic web-only, no crash/security. Guard: `{{ p.case_title or "a case (interviewer's choice)" }}`.
- m9b: iOS-contract note (not a defect): sent-countered /api/v1/proposals items have from_name = caller's own name; the counterparty who countered is only the raw counter_by id. Document for iOS.
