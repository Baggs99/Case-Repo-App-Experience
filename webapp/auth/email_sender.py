"""
Email sending — abstraction so dev / prod use the same call sites.

Backends:
  - ConsoleEmailSender (default in dev): logs the email to stdout AND
    writes it to output/emails/<timestamp>-<email>.txt so you can grab
    the verification link without setting up SMTP.
  - ResendEmailSender (TODO): production-ready stub. Sign up at
    https://resend.com (free tier: 3,000 emails/month), set RESEND_API_KEY,
    and uncomment the implementation below.

Env-driven selection:
  EMAIL_BACKEND=console (default)
  EMAIL_BACKEND=resend  (when you wire up cloud)
"""

from __future__ import annotations

import logging
import os
import re
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)


class EmailSender(ABC):
    @abstractmethod
    def send(self, *, to: str, subject: str, text_body: str) -> None:
        """Send an email. Synchronous so callers don't have to manage tasks
        for what is rarely a hot path. Switch to async if you start sending
        large volumes."""


# ── Console: dev backend ───────────────────────────────────────────────────────

EMAILS_DIR = Path(__file__).resolve().parents[2] / "output" / "emails"


class ConsoleEmailSender(EmailSender):
    """Prints each email to the server log and saves it to disk.

    The disk copy is the easy way to recover a verification link during
    development: just open the latest file in output/emails/.
    """

    def __init__(self, output_dir: Path = EMAILS_DIR):
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def send(self, *, to: str, subject: str, text_body: str) -> None:
        logger.info(
            "─" * 70 + "\n"
            "📧 EMAIL (console backend — not actually sent)\n"
            "    To:      %s\n"
            "    Subject: %s\n"
            "─" * 70 + "\n%s\n" + "─" * 70,
            to, subject, text_body,
        )

        timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
        safe_to = re.sub(r"[^A-Za-z0-9_.@-]", "_", to)
        path = self.output_dir / f"{timestamp}-{safe_to}.txt"
        path.write_text(
            f"To: {to}\nSubject: {subject}\n\n{text_body}\n",
            encoding="utf-8",
        )
        logger.info("    (saved to %s)", path)


# ── Resend: production backend ─────────────────────────────────────────────────

class ResendEmailSender(EmailSender):
    """Production sender via Resend (https://resend.com).

    Required env vars:
      RESEND_API_KEY  e.g. re_xxxxxxxxxxxxx
      EMAIL_FROM      e.g. 'Case Repo <onboarding@resend.dev>' (sandbox)
                      or  'Case Repo <noreply@yourdomain.com>' (after verifying
                      your domain in Resend)

    Failure modes (raised as RuntimeError so callers can decide whether to
    show the user a soft error vs hard-fail signup):
      - missing API key
      - Resend API rejection (rate limit, bad key, unverified domain, ...)
    """

    def __init__(self):
        api_key = os.environ.get("RESEND_API_KEY", "").strip()
        if not api_key:
            raise RuntimeError(
                "RESEND_API_KEY is empty. Paste your key into .env, or "
                "set EMAIL_BACKEND=console to fall back to dev mode."
            )

        sender = os.environ.get("EMAIL_FROM", "").strip()
        if not sender:
            raise RuntimeError(
                "EMAIL_FROM is not set. e.g. 'Case Repo <onboarding@resend.dev>'."
            )

        # Lazy import so the resend package isn't required when running with
        # the Console backend.
        import resend  # noqa: F401  — module-level side effect: configures key
        resend.api_key = api_key
        self._resend = resend
        self._sender = sender

    def send(self, *, to: str, subject: str, text_body: str) -> None:
        try:
            response = self._resend.Emails.send({
                "from":    self._sender,
                "to":      [to],
                "subject": subject,
                "text":    text_body,
            })
        except Exception as exc:
            logger.exception("Resend API call failed")
            raise RuntimeError(f"Email send failed: {exc}") from exc

        msg_id = response.get("id") if isinstance(response, dict) else None
        logger.info("Resend accepted email to %s (id=%s)", to, msg_id)


# ── Factory ────────────────────────────────────────────────────────────────────

def get_email_sender() -> EmailSender:
    backend = os.environ.get("EMAIL_BACKEND", "console").lower()
    if backend == "console":
        return ConsoleEmailSender()
    if backend == "resend":
        return ResendEmailSender()
    raise ValueError(f"Unknown EMAIL_BACKEND: {backend!r}")


# ── Convenience: build the verification email body ────────────────────────────

def build_verification_email(*, recipient_email: str, verification_url: str) -> tuple[str, str]:
    """Return (subject, text_body) for the verification email."""
    subject = "Verify your Case Repo account"
    body = (
        f"Welcome to Case Repo!\n\n"
        f"Click the link below to verify your email address. The link is\n"
        f"valid for 24 hours and can only be used once.\n\n"
        f"  {verification_url}\n\n"
        f"If you didn't create an account, you can ignore this email.\n"
        f"\n"
        f"— Case Repo\n"
    )
    return subject, body


def build_password_reset_email(*, recipient_email: str, reset_url: str) -> tuple[str, str]:
    """Return (subject, text_body) for the password-reset email."""
    subject = "Reset your Case Repo password"
    body = (
        f"We received a request to reset the password for your Case Repo\n"
        f"account ({recipient_email}).\n\n"
        f"Click the link below to choose a new password. The link is\n"
        f"valid for 1 hour and can only be used once.\n\n"
        f"  {reset_url}\n\n"
        f"If you didn't request this, you can safely ignore this email —\n"
        f"your password won't be changed.\n"
        f"\n"
        f"— Case Repo\n"
    )
    return subject, body
