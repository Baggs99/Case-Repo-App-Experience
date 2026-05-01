"""
Tiny probe: try a ladder of OpenAI models via the Responses API and report
which ones this API key can actually call. Uses a trivial 1-token prompt so
each attempt costs a fraction of a cent.

Run:  python _probe_models.py
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

# Reuse the same .env loader main.py uses so the key is available.
sys.path.insert(0, str(Path(__file__).parent))
from main import _load_dotenv  # noqa: E402
_load_dotenv(Path(__file__).parent / ".env")

# Windows console is cp1252 by default; force UTF-8 so model responses
# containing emoji / non-Latin chars don't crash the print.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
except Exception:
    pass

from openai import OpenAI  # noqa: E402

# Ordered highest-capability -> lowest, restricted to models this account
# actually has access to (from platform.openai.com/settings/organization/limits).
MODEL_LADDER = [
    "gpt-5.4",        # current default for classify-difficulty
    "gpt-5.1",        # previous default — fallback if 5.4 isn't available
    "o3",             # frontier reasoning
    "gpt-5-mini",
    "gpt-4.1",
    "o4-mini",
    "gpt-5-nano",
    "gpt-4.1-mini",
    "gpt-4.1-nano",
]


def probe(client: OpenAI, model: str) -> tuple[str, str]:
    """Return (status, detail). status in {'OK','MODEL','QUOTA','AUTH','OTHER'}."""
    try:
        # Reasoning models (o-series, gpt-5*) consume tokens on internal
        # reasoning before emitting output, so a tiny cap returns "". Use
        # a larger budget so we actually see a response.
        resp = client.responses.create(
            model=model,
            input="Reply with the single word 'pong' and nothing else.",
            max_output_tokens=256,
        )
        text = getattr(resp, "output_text", "") or "(no text — reasoning-only)"
        return "OK", text.strip()[:80]
    except Exception as exc:  # noqa: BLE001
        msg = str(exc)
        low = msg.lower()
        if "model_not_found" in low or "does not exist" in low or "no access" in low:
            return "MODEL", _short(msg)
        if "insufficient_quota" in low or "exceeded your current quota" in low:
            return "QUOTA", _short(msg)
        if "invalid_api_key" in low or "incorrect api key" in low or "unauthorized" in low:
            return "AUTH", _short(msg)
        if "rate limit" in low or "429" in low:
            return "RATE", _short(msg)
        return "OTHER", _short(msg)


def _short(msg: str) -> str:
    msg = msg.replace("\n", " ").strip()
    return msg[:160] + ("…" if len(msg) > 160 else "")


def main() -> None:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("NO KEY — OPENAI_API_KEY not set.")
        sys.exit(1)
    print(f"Using key prefix: {api_key[:12]}…")
    print(f"Probing {len(MODEL_LADDER)} models…\n")

    client = OpenAI(api_key=api_key)
    first_ok: str | None = None

    for model in MODEL_LADDER:
        t0 = time.monotonic()
        status, detail = probe(client, model)
        dt = time.monotonic() - t0
        tag = {
            "OK": "[OK]   ",
            "MODEL": "[NONE] ",
            "QUOTA": "[QUOTA]",
            "AUTH":  "[AUTH] ",
            "RATE":  "[RATE] ",
            "OTHER": "[ERR]  ",
        }[status]
        print(f"  {tag} {model:<20}  ({dt:5.2f}s)  {detail}")
        if status == "OK" and first_ok is None:
            first_ok = model
        # An auth failure applies everywhere — stop the ladder.
        # A quota failure may be per-model (confusingly), so keep going.
        if status == "AUTH":
            print(f"\n  --> Key auth error; all later models will fail. Stopping.")
            break

    print()
    if first_ok:
        print(f"FIRST WORKING MODEL: {first_ok}")
    else:
        print("NO MODEL WORKED — fix billing / model access first.")


if __name__ == "__main__":
    main()
