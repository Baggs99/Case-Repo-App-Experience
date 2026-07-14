"""
Task 15 capstone: live in-person-session E2E over real HTTP + WebSocket
(no UI, no TestClient) against a real `main.py serve` process.

Drives: pair/create (A) -> pair/claim (B) -> both WS connect -> consent
(both) -> state live (assert session-update on both sockets) -> reveal
(assert WS reveal frame on B + AES-GCM decrypt) -> rubric PUT -> state
debrief (assert session-update) -> finalize -> confirm the session shows
up in B's /api/v1/sessions?scope=recent history.

Inputs:  DATABASE_URL / .env (dev seed applied: a/b@yale.edu, case id 1
         with exhibits); a `python main.py serve --port 8077` process
         reachable at http://127.0.0.1:8077.
Outputs: prints each step's status code + key assertion to stdout; exits
         non-zero on any assertion failure.
Run:     .venv/bin/python main.py serve --port 8077 &   # in one shell
         .venv/bin/python tests/e2e_inperson_flow.py    # in another
"""

from __future__ import annotations

import base64
import json
import sys

import requests
import websockets
import asyncio

BASE = "http://127.0.0.1:8077"
COOKIE_NAME = "case_repo_session"
PASSWORD = "caseroom-dev-1"
CASE_ID = 1  # Dev Dummy Case — has exhibits + default rubric template


def ok(label: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label} {detail}")
    if not cond:
        sys.exit(1)


def login(email: str) -> requests.Session:
    s = requests.Session()
    r = s.post(f"{BASE}/api/v1/auth/login", json={"email": email, "password": PASSWORD})
    ok(f"login {email}", r.status_code == 200, f"-> {r.status_code}")
    ok(f"login {email} sets cookie", COOKIE_NAME in s.cookies, "")
    return s


async def ws_connect(cookie_value: str, session_id: int):
    url = f"ws://127.0.0.1:8077/ws/practice/{session_id}"
    ws = await websockets.connect(url, additional_headers={"Cookie": f"{COOKIE_NAME}={cookie_value}"})
    first = json.loads(await ws.recv())
    return ws, first


async def recv_until(ws, msg_type: str, timeout: float = 5.0) -> dict:
    """Drain frames until one matches msg_type (heartbeats/pings aside)."""
    loop_end = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = loop_end - asyncio.get_event_loop().time()
        if remaining <= 0:
            raise TimeoutError(f"never saw a {msg_type!r} frame")
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        msg = json.loads(raw)
        if msg.get("type") == msg_type:
            return msg


async def main() -> None:
    a = login("a@yale.edu")
    b = login("b@yale.edu")
    a_cookie = a.cookies.get(COOKIE_NAME)
    b_cookie = b.cookies.get(COOKIE_NAME)

    # --- Pairing: A mints, B claims ---
    r = a.post(f"{BASE}/api/practice/pair/create", json={"case_id": CASE_ID})
    ok("pair/create", r.status_code == 200, f"-> {r.status_code} {r.text}")
    token = r.json()["token"]

    r = b.post(f"{BASE}/api/practice/pair/claim", json={"token": token})
    ok("pair/claim", r.status_code == 200, f"-> {r.status_code} {r.text}")
    session_id = r.json()["session_id"]
    print(f"    session_id = {session_id}")

    r = a.get(f"{BASE}/api/practice/{session_id}")
    ok("A GET session role", r.status_code == 200 and r.json()["your_role"] == "interviewer",
       f"-> {r.status_code} role={r.json().get('your_role')}")
    r = b.get(f"{BASE}/api/practice/{session_id}")
    ok("B GET session role", r.status_code == 200 and r.json()["your_role"] == "candidate",
       f"-> {r.status_code} role={r.json().get('your_role')}")

    # --- Both open WebSockets ---
    ws_a, ok_a = await ws_connect(a_cookie, session_id)
    ok("A WS connect", ok_a.get("role") == "interviewer", f"-> {ok_a}")
    ws_b, ok_b = await ws_connect(b_cookie, session_id)
    ok("B WS connect", ok_b.get("role") == "candidate", f"-> {ok_b}")
    # Drain A's peer-joined notice so it doesn't pollute later recv_until calls.
    peer_joined = await recv_until(ws_a, "peer-joined")
    ok("A sees peer-joined", peer_joined.get("role") == "candidate", f"-> {peer_joined}")

    # --- scheduled -> lobby (consent gate only opens post-lobby), then
    # consent (both), then state -> live; assert session-update on BOTH sockets ---
    r = a.post(f"{BASE}/api/practice/{session_id}/state", json={"target": "lobby"})
    ok("A state->lobby", r.status_code == 200 and r.json()["state"] == "lobby",
       f"-> {r.status_code} {r.text}")
    await recv_until(ws_a, "session-update")
    await recv_until(ws_b, "session-update")

    r = b.post(f"{BASE}/api/practice/{session_id}/consent", json={"consent": True})
    ok("B consent", r.status_code == 200, f"-> {r.status_code}")
    su_a1 = await recv_until(ws_a, "session-update")
    ok("A WS session-update after B consent", su_a1["type"] == "session-update", f"-> {su_a1}")
    su_b1 = await recv_until(ws_b, "session-update")
    ok("B WS session-update after B consent", su_b1["type"] == "session-update", f"-> {su_b1}")

    r = a.post(f"{BASE}/api/practice/{session_id}/consent", json={"consent": True})
    ok("A consent", r.status_code == 200, f"-> {r.status_code}")
    su_a2 = await recv_until(ws_a, "session-update")
    su_b2 = await recv_until(ws_b, "session-update")
    ok("A WS session-update after A consent", su_a2["type"] == "session-update", f"-> {su_a2}")
    ok("B WS session-update after A consent", su_b2["type"] == "session-update", f"-> {su_b2}")

    r = a.post(f"{BASE}/api/practice/{session_id}/state", json={"target": "live"})
    ok("A state->live", r.status_code == 200 and r.json()["state"] == "live",
       f"-> {r.status_code} {r.text}")
    su_a3 = await recv_until(ws_a, "session-update")
    su_b3 = await recv_until(ws_b, "session-update")
    ok("A WS session-update after state->live (candidate advances live)", su_a3["type"] == "session-update", f"-> {su_a3}")
    ok("B WS session-update after state->live (candidate advances live)", su_b3["type"] == "session-update", f"-> {su_b3}")

    # --- Reveal: A picks an exhibit of case 1, assert B's WS gets the key + it decrypts ---
    r = a.get(f"{BASE}/api/practice/{session_id}/exhibits")
    ok("exhibit manifest fetch", r.status_code == 200, f"-> {r.status_code} {r.text}")
    manifest = r.json()["exhibits"]
    ok("case has >=1 exhibit", len(manifest) >= 1, f"-> {len(manifest)} exhibits")
    exhibit_id = manifest[0]["exhibit_id"]
    iv_b64 = manifest[0]["iv_b64"]
    print(f"    exhibit_id = {exhibit_id}")

    r = a.post(f"{BASE}/api/practice/{session_id}/reveals", json={"exhibit_id": exhibit_id})
    ok("A POST reveals", r.status_code == 200, f"-> {r.status_code} {r.text}")

    reveal_msg = await recv_until(ws_b, "reveal")
    ok("B WS reveal frame", reveal_msg.get("exhibit_id") == exhibit_id and bool(reveal_msg.get("key_b64")),
       f"-> {reveal_msg}")

    key = base64.b64decode(reveal_msg["key_b64"])
    blob_resp = b.get(f"{BASE}/api/practice/{session_id}/exhibit-blob/{exhibit_id}")
    ok("B exhibit-blob fetch", blob_resp.status_code == 200, f"-> {blob_resp.status_code}")

    sys.path.insert(0, ".")
    from webapp.exhibit_crypto import decrypt_exhibit
    plaintext = decrypt_exhibit(blob_resp.content, key, base64.b64decode(iv_b64))
    ok("reveal key decrypts exhibit blob", plaintext[:4] in (b"RIFF", b"%PDF") or len(plaintext) > 0,
       f"-> decrypted {len(plaintext)} bytes, magic={plaintext[:8]!r}")

    r = b.get(f"{BASE}/api/practice/{session_id}/reveals")
    ok("reveals row logged", r.status_code == 200 and len(r.json()["reveals"]) == 1, f"-> {r.text}")

    # --- Rubric + debrief + finalize ---
    r = a.get(f"{BASE}/api/practice/{session_id}/rubric")
    ok("A GET rubric (template)", r.status_code == 200, f"-> {r.status_code} {r.text}")
    template_items = r.json()["template_items"]
    ok("rubric template has items", len(template_items) >= 1, f"-> {len(template_items)} items")

    scored_items = {
        item["id"]: {"points": item["max_points"], "note": "e2e score"}
        for item in template_items
    }
    r = a.put(f"{BASE}/api/practice/{session_id}/rubric",
              json={"items": scored_items, "notes_md": "E2E overall notes"})
    ok("A PUT rubric", r.status_code == 200 and r.json()["saved"] is True, f"-> {r.status_code} {r.text}")

    r = a.post(f"{BASE}/api/practice/{session_id}/state", json={"target": "debrief"})
    ok("A state->debrief", r.status_code == 200 and r.json()["state"] == "debrief",
       f"-> {r.status_code} {r.text}")
    su_a4 = await recv_until(ws_a, "session-update")
    su_b4 = await recv_until(ws_b, "session-update")
    ok("A WS session-update after state->debrief", su_a4["type"] == "session-update", f"-> {su_a4}")
    ok("B WS session-update after state->debrief", su_b4["type"] == "session-update", f"-> {su_b4}")

    r = a.post(f"{BASE}/api/practice/{session_id}/finalize", json={"grade": None})
    ok("A finalize", r.status_code == 200 and r.json()["finalized"] is True, f"-> {r.status_code} {r.text}")
    grade = r.json()["grade"]
    ok("finalize computed a grade", grade is not None, f"-> grade={grade}")

    # --- Confirm it appears in B's history ---
    r = b.get(f"{BASE}/api/v1/sessions", params={"scope": "recent"})
    ok("B GET /api/v1/sessions?scope=recent", r.status_code == 200, f"-> {r.status_code} {r.text}")
    recent_ids = [row["id"] for row in r.json()["sessions"]]
    ok("finalized session appears in B's recent history", session_id in recent_ids,
       f"-> recent ids={recent_ids}")

    await ws_a.close()
    await ws_b.close()

    print("\nALL STEPS PASSED")


if __name__ == "__main__":
    asyncio.run(main())
