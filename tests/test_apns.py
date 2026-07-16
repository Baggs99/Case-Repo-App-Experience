"""JWT structure + send path for webapp/push/apns.py (no network)."""
import base64
import json
import tempfile
import unittest
from dataclasses import dataclass

import httpx
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives import hashes, serialization

from webapp.push.apns import make_provider_jwt, send_push


def _test_key():
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    return key, pem


@dataclass
class _FakeSettings:
    pem_bytes: bytes
    apns_key_id: str = "K"
    apns_team_id: str = "T"
    apns_bundle_id: str = "study.mycase"
    apns_use_sandbox: bool = True

    def __post_init__(self):
        f = tempfile.NamedTemporaryFile(suffix=".pem", delete=False)
        f.write(self.pem_bytes)
        f.close()
        self.apns_key_path = f.name


class TestJwt(unittest.TestCase):
    def test_jwt_header_and_claims(self):
        key, pem = _test_key()
        tok = make_provider_jwt(pem, "KEYID12345", "TEAMID1234", now=1700000000.0)
        h, c, _sig = tok.split(".")
        header = json.loads(base64.urlsafe_b64decode(h + "=="))
        claims = json.loads(base64.urlsafe_b64decode(c + "=="))
        self.assertEqual(header, {"alg": "ES256", "kid": "KEYID12345"})
        self.assertEqual(claims, {"iss": "TEAMID1234", "iat": 1700000000})

    def test_jwt_signature_verifies(self):
        key, pem = _test_key()
        tok = make_provider_jwt(pem, "KEYID12345", "TEAMID1234", now=1700000000.0)
        header, claims, sig = tok.split(".")
        raw = base64.urlsafe_b64decode(sig + "==")
        r = int.from_bytes(raw[:32], "big")
        s = int.from_bytes(raw[32:], "big")
        der = utils.encode_dss_signature(r, s)
        public_key = key.public_key()
        try:
            public_key.verify(der, f"{header}.{claims}".encode(), ec.ECDSA(hashes.SHA256()))
        except InvalidSignature:
            self.fail("JWT signature did not verify against the signing input")


class TestSend(unittest.IsolatedAsyncioTestCase):
    async def test_send_push_posts_correct_shape(self):
        _, pem = _test_key()
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["path"] = request.url.path
            seen["topic"] = request.headers["apns-topic"]
            seen["payload"] = json.loads(request.content)
            return httpx.Response(200)

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            status = await send_push(
                "ff00" * 16, title="Knock", body="Dan is knocking",
                data={"kind": "knock", "session_id": 7},
                settings=_FakeSettings(pem), client=client)
        finally:
            await client.aclose()
        self.assertEqual(status, 200)
        self.assertEqual(seen["path"], "/3/device/" + "ff00" * 16)
        self.assertEqual(seen["topic"], "study.mycase")
        self.assertEqual(seen["payload"]["aps"]["alert"]["title"], "Knock")
        self.assertEqual(seen["payload"]["kind"], "knock")

    async def test_send_push_sets_interruption_level(self):
        _, pem = _test_key()
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return httpx.Response(200)

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            await send_push(
                "ff00" * 16, title="Knock", body="Dan is knocking",
                data={"kind": "knock", "session_id": 7},
                interruption_level="time-sensitive",
                settings=_FakeSettings(pem), client=client)
        finally:
            await client.aclose()
        self.assertEqual(seen["payload"]["aps"]["interruption-level"], "time-sensitive")
