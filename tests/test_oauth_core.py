"""
Purpose: OAuth OIDC core — PKCE, authorize URL, and RS256 id_token verification
         with a locally-generated key (no network, no live creds). Also the
         users OAuth-sub link/lookup helpers.
Inputs:  cryptography for a throwaway RSA key; seeded dev Postgres for the users
         helpers (user c@yale.edu).
Outputs: links/clears c@yale.edu's google_sub; cleans up.
Run:     .venv/bin/python -m pytest tests/test_oauth_core.py -q
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
import unittest

import psycopg
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from tests.test_ws_integration import _DB_URL, _READY


_MISSING = object()  # sentinel: omit the email_verified claim entirely


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _make_signed_id_token(*, kid, priv, iss, aud, sub, email, nonce, name="Cara Test"):
    header = {"alg": "RS256", "typ": "JWT", "kid": kid}
    payload = {"iss": iss, "aud": aud, "sub": sub, "email": email,
               "email_verified": True, "name": name, "nonce": nonce,
               "exp": int(time.time()) + 600, "iat": int(time.time())}
    signing_input = (_b64u(json.dumps(header).encode()) + "."
                     + _b64u(json.dumps(payload).encode())).encode()
    sig = priv.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    return signing_input.decode() + "." + _b64u(sig)


def _jwk_from_pub(pub, kid):
    nums = pub.public_numbers()
    def enc_int(i):
        b = i.to_bytes((i.bit_length() + 7) // 8, "big")
        return _b64u(b)
    return {"keys": [{"kty": "RSA", "kid": kid, "alg": "RS256", "use": "sig",
                      "n": enc_int(nums.n), "e": enc_int(nums.e)}]}


class TestPkceAndAuthorize(unittest.TestCase):
    def test_pkce_challenge_is_s256_of_verifier(self):
        from webapp.auth.oauth import make_pkce
        verifier, challenge = make_pkce()
        expected = _b64u(hashlib.sha256(verifier.encode()).digest())
        self.assertEqual(challenge, expected)

    def test_authorize_url_contains_params(self):
        from webapp.auth.oauth import authorize_url
        url = authorize_url("google", state="st", code_challenge="cc",
                            redirect_uri="https://app/cb", nonce="nn")
        self.assertIn("state=st", url)
        self.assertIn("code_challenge=cc", url)
        self.assertIn("code_challenge_method=S256", url)
        self.assertIn("nonce=nn", url)
        self.assertIn("scope=", url)


class TestVerifyIdToken(unittest.TestCase):
    def setUp(self):
        self.priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.kid = "test-kid-1"
        self.jwks = _jwk_from_pub(self.priv.public_key(), self.kid)

    def test_valid_token_verifies(self):
        from webapp.auth import oauth
        cfg = oauth.PROVIDERS["google"]
        tok = _make_signed_id_token(kid=self.kid, priv=self.priv, iss=cfg.issuer,
                                    aud="client-abc", sub="G-1",
                                    email="c@yale.edu", nonce="nn")
        claims = oauth.verify_id_token("google", tok, self.jwks,
                                       client_id="client-abc", nonce="nn")
        self.assertEqual(claims["sub"], "G-1")
        self.assertEqual(claims["email"], "c@yale.edu")

    def test_wrong_audience_rejected(self):
        from webapp.auth import oauth
        cfg = oauth.PROVIDERS["google"]
        tok = _make_signed_id_token(kid=self.kid, priv=self.priv, iss=cfg.issuer,
                                    aud="someone-else", sub="G-1",
                                    email="c@yale.edu", nonce="nn")
        with self.assertRaises(oauth.OAuthError):
            oauth.verify_id_token("google", tok, self.jwks,
                                  client_id="client-abc", nonce="nn")

    def test_wrong_nonce_rejected(self):
        from webapp.auth import oauth
        cfg = oauth.PROVIDERS["google"]
        tok = _make_signed_id_token(kid=self.kid, priv=self.priv, iss=cfg.issuer,
                                    aud="client-abc", sub="G-1",
                                    email="c@yale.edu", nonce="nn")
        with self.assertRaises(oauth.OAuthError):
            oauth.verify_id_token("google", tok, self.jwks,
                                  client_id="client-abc", nonce="DIFFERENT")

    def test_tampered_signature_rejected(self):
        from webapp.auth import oauth
        cfg = oauth.PROVIDERS["google"]
        tok = _make_signed_id_token(kid=self.kid, priv=self.priv, iss=cfg.issuer,
                                    aud="client-abc", sub="G-1",
                                    email="c@yale.edu", nonce="nn")
        tampered = tok[:-4] + ("AAAA" if not tok.endswith("AAAA") else "BBBB")
        with self.assertRaises(oauth.OAuthError):
            oauth.verify_id_token("google", tampered, self.jwks,
                                  client_id="client-abc", nonce="nn")

    def test_garbage_token_raises_oautherror(self):
        # Malformed base64/JSON must surface as OAuthError, not a stdlib error.
        from webapp.auth import oauth
        with self.assertRaises(oauth.OAuthError):
            oauth.verify_id_token("google", "not.a.jwt", self.jwks,
                                  client_id="client-abc", nonce="nn")

    def test_non_int_exp_raises_oautherror(self):
        # A signed token that reaches the exp check with a non-int exp must
        # raise OAuthError (not a bare ValueError from the int() cast).
        from webapp.auth import oauth
        cfg = oauth.PROVIDERS["google"]
        header = {"alg": "RS256", "typ": "JWT", "kid": self.kid}
        payload = {"iss": cfg.issuer, "aud": "client-abc", "sub": "G-1",
                   "email": "c@yale.edu", "email_verified": True, "nonce": "nn",
                   "exp": "not-a-number", "iat": int(time.time())}
        signing_input = (_b64u(json.dumps(header).encode()) + "."
                         + _b64u(json.dumps(payload).encode())).encode()
        sig = self.priv.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
        tok = signing_input.decode() + "." + _b64u(sig)
        with self.assertRaises(oauth.OAuthError):
            oauth.verify_id_token("google", tok, self.jwks,
                                  client_id="client-abc", nonce="nn")


class TestEmailVerifiedCoercion(unittest.TestCase):
    """email_verified must be a strict bool: providers (LinkedIn) may emit the
    claim as a JSON string, and bool('false') is True in Python."""

    def _verified(self, value):
        from webapp.auth.oauth import identity_from_claims
        claims = {"sub": "S-1", "email": "c@yale.edu"}
        if value is not _MISSING:
            claims["email_verified"] = value
        return identity_from_claims(claims).email_verified

    def test_string_false_is_unverified(self):
        self.assertIs(self._verified("false"), False)

    def test_missing_is_unverified(self):
        self.assertIs(self._verified(_MISSING), False)

    def test_bool_true_is_verified(self):
        self.assertIs(self._verified(True), True)

    def test_string_true_is_verified(self):
        self.assertIs(self._verified("true"), True)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestOAuthUserHelpers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'c@yale.edu';")
                cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE users SET google_sub = NULL WHERE id = %s;",
                            (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def test_link_and_lookup_by_sub(self):
        from webapp.auth.users import get_user_by_oauth_sub, link_oauth_sub
        link_oauth_sub(self.uid, "google", "GSUB-XYZ")
        found = get_user_by_oauth_sub("google", "GSUB-XYZ")
        self.assertIsNotNone(found)
        self.assertEqual(found.id, self.uid)
        self.assertIsNone(get_user_by_oauth_sub("google", "no-such-sub"))


if __name__ == "__main__":
    unittest.main()
