# B5 Identity/Profile/Onboarding — Execution Ledger

Branch: bgap/b5-identity · Worktree: /Users/thomaskgould/dev/bgap-b5
DB: caserepo_bgap_b5 · PY: /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python

## Baseline
- Env bootstrapped: DB caserepo_bgap_b5 created, schema + migrations 002-018 loaded, .env copied + DATABASE_URL repointed, dev users a/b/c@yale.edu + dummy case seeded.
- Baseline suite (seeded): 360 passed, 0 skipped, 0 failed. Finish line = 360 + new tests.
  (Before seed: 241 passed / 119 skipped — all skips gated on the dev seed, now applied.)

## Tasks
(pending plan)

## Plan
- Plan written + committed (5040c4e), reviewed by fresh Opus reviewer (round 1: REQUEST_CHANGES — 1 CRITICAL email_verified gate, 2 IMPORTANT), fixed (1e94ae9), re-reviewed round 2: APPROVE.

## Execution ledger
- BASE for Task 1 = 1e94ae9
- Task 1: complete (commits 451913d..83f7da6, review APPROVE). MINORs (ledger): FK guard matches conname globally not scoped to users.conrelid (implausible collision); test doesn't assert the sub unique indexes / FK exist.
- BASE for Task 2 = 83f7da6
- Task 2: complete (commits c322094..f5c0e15, review APPROVE, no findings).
- BASE for Task 3 = f5c0e15
- Task 3: complete (commits a0f25f9..fe1f03c, review APPROVE). MINORs (ledger): stale "Booth guest" docstrings in users.py (InvalidEmailDomain, create_user); signup.html/base.html Booth invite-only copy stale under registry model (template copy, out of B5 code scope).
- BASE for Task 4 = fe1f03c
- Task 4: complete (commits 7b815bc..b5d8bfa, review APPROVE, informational MINORs only).
- BASE for Task 5 = b5d8bfa
- Task 5: complete (commits 23b1b0e..5df69bb, review APPROVE). MINORs (ledger): update_settings read-merge-write TOCTOU (per-user toggle, negligible); events.py choke fails-closed on DB error (best-effort push, infra-failure only); dead UPDATE-0-rows setup line in test_no_category_always_sent; "import cycle" comment overstated.
- BASE for Task 6 = 5df69bb
- Task 6: complete (commits b9686ad..50e8be3, review APPROVE). IMPORTANT (unbounded file.read before size check → authed OOM) FIXED in 0a21dbe (file.size early-reject + read(cap+1) bounded read; 9/9 tests). MINORs (ledger): jpeg/webp sniff branches + CSRF-reject + filename-traversal IDOR not separately tested (structurally safe).
- BASE for Task 7 = 0a21dbe
- Task 7: complete (commits 58bd77f..1dfe849, review APPROVE). MINORs (ledger): onboarding.py unused `Response` import; NO rate-limit on otp/request (email-bombing/unbounded codes — recommend follow-up; brute force already mitigated by newest-code-only + 3-attempt cap); two test-strength nits (cap test uses wrong code on 4th; no verify test for unregistered email).
- BASE for Task 8 = 1dfe849
- Task 8: complete (commits eea26d4..7031f58, review APPROVE). MINORs (ledger): timing side-channel on signup/request (same as otp pattern; spec only mandates status+body parity); cosmetic test docstring says "yale" but constant is umich.
- BASE for Task 9 = 7031f58
- Task 9: complete (commits a588ba2..203bc01, review APPROVE, crypto sound: alg pinned RS256/no HMAC path/kid-must-match/claims-post-signature). MINORs (ledger, for final-review fix pass): verify_id_token could wrap base64/JSON/int-parse errors in OAuthError (currently a malformed id_token raises stdlib exc → 500 in callback rather than clean auth-fail); optional kty=="RSA" + kid-present asserts. All fail-closed, no bypass.
- BASE for Task 10 = 203bc01
- Task 10: complete (commits 643805f..8657cf3, review APPROVE). IMPORTANT (LinkedIn-style string email_verified defeats the gate: bool("false")==True) FIXED in 0a19216 (_coerce_bool + 4 coercion tests). MINOR (state cookie missing secure) FIXED same commit (secure=_cookie_secure()). Remaining MINOR (ledger): no test for unverified+new-registered create path (structurally blocked); avatar fetch follow_redirects SSRF-shape mitigated by provider-signed picture URL.
- All 10 implementation tasks complete. Proceeding to full-suite + final whole-branch review.

## Final
- Full suite: 420 passed / 0 failed (baseline 360). Migrations 022/023/024 idempotent (re-applied clean). .env untracked.
- Final whole-branch review (b0552de..HEAD): APPROVE, 0 CRITICAL/0 IMPORTANT, 11 MINOR. 6 in-scope minors hardened in 4be7f9f (threadpool blocking I/O, linkedin_url scheme, fail-open push, clean OAuth errors, docstrings, unused import), re-reviewed clean.
- Report: docs/superpowers/sdd/bgap-b5-report.md (incl. THOMAS MANUAL for live OAuth + DEFERRED follow-ups).
- STATUS: DONE.
