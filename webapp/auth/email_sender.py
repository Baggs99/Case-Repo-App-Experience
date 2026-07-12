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
    def send(
        self,
        *,
        to: str,
        subject: str,
        text_body: str,
        html_body: str | None = None,
        attachments: list[tuple[str, str, bytes]] | None = None,
    ) -> None:
        """Send an email. Synchronous so callers don't have to manage tasks
        for what is rarely a hot path. Switch to async if you start sending
        large volumes.

        `attachments` is a list of (filename, mimetype, content) tuples —
        added for CaseRoom .ics invites (spec T8.4).

        Always provide both `text_body` (fallback for plain-text clients
        and accessibility) and `html_body` (what most clients render).
        Sending text-only is a strong spam signal in 2026 and should be
        avoided for transactional mail.
        """


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

    def send(
        self,
        *,
        to: str,
        subject: str,
        text_body: str,
        html_body: str | None = None,
        attachments: list[tuple[str, str, bytes]] | None = None,
    ) -> None:
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
        text_path = self.output_dir / f"{timestamp}-{safe_to}.txt"
        text_path.write_text(
            f"To: {to}\nSubject: {subject}\n\n{text_body}\n",
            encoding="utf-8",
        )
        logger.info("    (text saved to %s)", text_path)

        if html_body:
            html_path = self.output_dir / f"{timestamp}-{safe_to}.html"
            html_path.write_text(html_body, encoding="utf-8")
            logger.info("    (html saved to %s)", html_path)

        for filename, _mimetype, content in attachments or []:
            safe_name = re.sub(r"[^A-Za-z0-9_.-]", "_", filename)
            att_path = self.output_dir / f"{timestamp}-{safe_to}-{safe_name}"
            att_path.write_bytes(content)
            logger.info("    (attachment saved to %s)", att_path)


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

    def send(
        self,
        *,
        to: str,
        subject: str,
        text_body: str,
        html_body: str | None = None,
        attachments: list[tuple[str, str, bytes]] | None = None,
    ) -> None:
        payload: dict = {
            "from":    self._sender,
            "to":      [to],
            "subject": subject,
            "text":    text_body,
        }
        if html_body:
            payload["html"] = html_body
        if attachments:
            import base64
            payload["attachments"] = [
                {"filename": name, "content": base64.b64encode(content).decode(),
                 "content_type": mimetype}
                for name, mimetype, content in attachments
            ]

        try:
            response = self._resend.Emails.send(payload)
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


# ── HTML email skeleton ────────────────────────────────────────────────────────
#
# Email HTML is its own dialect. Constraints:
#   - <style> blocks get stripped by Outlook 2016+, Yahoo Mail, and others.
#     All styling MUST be inline.
#   - Float / flexbox / grid are unreliable. Use <table> for layout.
#   - No remote images (cheap heuristic for spam classifiers + Outlook
#     blocks them by default until the user clicks "Show images").
#   - No JavaScript. Anywhere.
#   - Subject + plain-text fallback should match the HTML's intent so
#     classifiers don't flag mismatch. We always send both.

def _render_email_html(*, headline: str, intro: str, button_label: str,
                       url: str, fine_print: str) -> str:
    """Wrap a transactional email body in a consistent branded shell.

    Generates the same chrome (Case Repo header, slate palette, CTA button,
    plain-URL fallback below the button, footer disclaimer) for every
    transactional email, with the per-email copy passed in as args.
    """
    return f"""\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{headline}</title>
</head>
<body style="margin:0; padding:0; background-color:#f5f5f5; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; color:#0f172a;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f5f5f5; padding:40px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px; background-color:#ffffff; border-radius:8px; border:1px solid #e2e8f0;">
          <tr>
            <td style="padding:32px 40px 8px 40px;">
              <div style="font-size:20px; font-weight:600; color:#0f172a; line-height:1.2;">Case Repo</div>
              <div style="margin-top:2px; font-size:13px; color:#64748b;">Consulting cases for Yale SOM</div>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 40px 8px 40px;">
              <div style="font-size:18px; font-weight:600; color:#0f172a; margin-bottom:12px;">{headline}</div>
              <div style="font-size:15px; line-height:1.55; color:#334155;">{intro}</div>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 40px 8px 40px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="background-color:#0f172a; border-radius:6px;">
                    <a href="{url}" style="display:inline-block; padding:12px 24px; color:#ffffff; text-decoration:none; font-size:15px; font-weight:500;">{button_label}</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 40px 8px 40px;">
              <div style="font-size:13px; color:#64748b; line-height:1.55;">
                If the button above doesn&rsquo;t work, paste this link into your browser:<br>
                <a href="{url}" style="color:#0f172a; word-break:break-all;">{url}</a>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 40px 32px 40px; border-top:1px solid #e2e8f0; margin-top:16px;">
              <div style="font-size:12px; color:#94a3b8; line-height:1.55;">{fine_print}</div>
            </td>
          </tr>
        </table>
        <div style="margin-top:16px; font-size:11px; color:#94a3b8;">Case Repo &middot; <a href="https://cases.baglini.co" style="color:#94a3b8; text-decoration:none;">cases.baglini.co</a></div>
      </td>
    </tr>
  </table>
</body>
</html>
"""


# ── Convenience: build the verification email body ────────────────────────────

def build_verification_email(*, recipient_email: str, verification_url: str) -> tuple[str, str, str]:
    """Return (subject, text_body, html_body) for the verification email."""
    subject = "Verify your Case Repo account"
    text_body = (
        f"Welcome to Case Repo.\n\n"
        f"Click the link below to verify your email address. The link is\n"
        f"valid for 24 hours and can only be used once.\n\n"
        f"  {verification_url}\n\n"
        f"If you didn't create an account, you can ignore this email.\n\n"
        f"— Case Repo\n"
        f"https://cases.baglini.co\n"
    )
    html_body = _render_email_html(
        headline="Welcome to Case Repo",
        intro=(
            "Click the button below to verify your email address. "
            "This link is valid for 24 hours and can only be used once."
        ),
        button_label="Verify my email",
        url=verification_url,
        fine_print=(
            "If you didn&rsquo;t create a Case Repo account, you can safely "
            "ignore this email."
        ),
    )
    return subject, text_body, html_body


def build_password_reset_email(*, recipient_email: str, reset_url: str) -> tuple[str, str, str]:
    """Return (subject, text_body, html_body) for the password-reset email."""
    subject = "Reset your Case Repo password"
    text_body = (
        f"We received a request to reset the password for your Case Repo\n"
        f"account ({recipient_email}).\n\n"
        f"Click the link below to choose a new password. The link is\n"
        f"valid for 1 hour and can only be used once.\n\n"
        f"  {reset_url}\n\n"
        f"If you didn't request this, you can safely ignore this email —\n"
        f"your password won't be changed.\n\n"
        f"— Case Repo\n"
        f"https://cases.baglini.co\n"
    )
    html_body = _render_email_html(
        headline="Reset your password",
        intro=(
            f"We received a request to reset the password for your Case Repo "
            f"account (<strong>{recipient_email}</strong>). Click the button "
            f"below to choose a new password. This link is valid for 1 hour."
        ),
        button_label="Set a new password",
        url=reset_url,
        fine_print=(
            "If you didn&rsquo;t request a password reset, you can safely "
            "ignore this email&mdash;your password will not be changed."
        ),
    )
    return subject, text_body, html_body
