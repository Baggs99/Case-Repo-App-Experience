# Task 8 — Pairing short-codes + optional case + claim by code

**Status:** DONE. All 6 steps executed under strict TDD. Full suite green.

**Commit:** `f7e9846` — "Add pairing short-codes, optional case at mint, claim by token or code"
Files: `webapp/repositories/pairing_tokens.py`, `webapp/routes/practice.py`, `tests/test_b1_pairing_shortcode.py`

## Step 2 — RED (tests fail before implementation)

`DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/test_b1_pairing_shortcode.py -q`

```
7 failed, 2 passed, 19 warnings in 0.71s
FAILED test_case_less_token_claim_409
FAILED test_claim_by_short_code_creates_session
FAILED test_claim_requires_auth
FAILED test_mint_case_optional
FAILED test_mint_returns_short_code
FAILED test_self_claim_by_code_409
FAILED test_unknown_short_code_404
```

Failure cause: mint response had no `short_code`; claim rejected `short_code`. The
2 pre-passing tests: `test_claim_by_token_still_works` (token flow already existed)
and `test_claim_requires_token_or_code` (old required-`token` body already 422'd on `{}`).

## Step 5 — GREEN (new + existing pairing tests)

`... $PY -m pytest tests/test_b1_pairing_shortcode.py tests/test_pairing.py -q`

```
22 passed, 50 warnings in 0.89s
```

9 new Task-8 tests + 13 existing `tests/test_pairing.py` tests — claim-by-token still
creates sessions, 409 on double/self/expired, status endpoint all green. test_pairing.py
untouched.

## Full suite

`... $PY -m pytest tests/ -q`

```
399 passed, 400 warnings in 5.25s
```

390 previously-green + 9 new = 399. Zero failures, zero previously-green regressions.

## Implementation notes

- `_SHORT_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"` (6 chars, no 0/O/1/I); `_gen_short_code` via `secrets.choice`.
- `mint_token(interviewer_id, case_id=None, ttl_minutes=10)`: retries up to 5x on `pg_errors.UniqueViolation`, regenerating BOTH token and short_code inside the loop (conn.rollback between attempts). Returns `{token, short_code, expires_at}`.
- `claim(*, candidate_id, token=None, short_code=None)`: keyword-only; keys on token OR short_code (404 if the row isn't found); neither provided -> 400. Case-less token (`case_id IS NULL`) -> 409 "Choose a case before pairing" (DD-1, sessions stay case-bound). Self-claim (interviewer==candidate) -> 409 for both token and short_code paths. Locking/session-creation logic unchanged.
- Routes: `PairCreateBody.case_id` optional; `PairClaimBody` has optional `token` + `short_code`; mint 404s only when a non-null case_id is unknown; claim handler has the 422 "provide a token or short_code" guard, then delegates to the repo.
- SQL: all values parameterized. The only interpolation in `claim` is `{where}`, a fixed literal (`"token = %s"` / `"short_code = %s"`) — never user data (matches the Global Constraints allowance for the `_COLS`-style fixed interpolation).

## Concerns

None. No deferred items, no placeholders. Task 8 complete and committed.
