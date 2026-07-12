"""
RFC 5545 .ics invite builder for practice sessions (spec §4.7, T8.4).

Pure string assembly — no dependencies. Emits METHOD:REQUEST with a stable
UID (caseroom-{session_id}@{host}) so re-sends update rather than duplicate
in calendar clients. Lines are CRLF-terminated and folded at 75 octets per
RFC 5545 §3.1; TEXT values are escaped per §3.3.11.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

DEFAULT_DURATION = timedelta(minutes=45)


def _escape(text: str) -> str:
    return (text.replace("\\", "\\\\").replace(";", "\\;")
                .replace(",", "\\,").replace("\r\n", "\\n").replace("\n", "\\n"))


def _fold(line: str) -> str:
    """Fold to lines of at most 75 octets (UTF-8), continuation indented."""
    raw = line.encode("utf-8")
    if len(raw) <= 75:
        return line
    parts, budget = [], 75
    chunk = b""
    for ch in line:
        b = ch.encode("utf-8")
        if len(chunk) + len(b) > budget:
            parts.append(chunk.decode("utf-8"))
            chunk, budget = b, 74  # continuation lines lose one octet to the space
        else:
            chunk += b
    parts.append(chunk.decode("utf-8"))
    return "\r\n ".join(parts)


def _utc(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def build_session_ics(*, session_id: int, case_title: str,
                      starts_at: datetime | None,
                      organizer_name: str, organizer_email: str,
                      attendee_name: str, attendee_email: str,
                      session_url: str, host: str,
                      now: datetime | None = None) -> str:
    """One VEVENT invite. starts_at=None means 'now' (proposal accepted for
    an immediate session)."""
    now = now or datetime.now(timezone.utc)
    start = starts_at or now
    end = start + DEFAULT_DURATION

    lines = [
        "BEGIN:VCALENDAR",
        "PRODID:-//CaseRoom//Practice Sessions//EN",
        "VERSION:2.0",
        "CALSCALE:GREGORIAN",
        "METHOD:REQUEST",
        "BEGIN:VEVENT",
        f"UID:caseroom-{session_id}@{host}",
        f"DTSTAMP:{_utc(now)}",
        f"DTSTART:{_utc(start)}",
        f"DTEND:{_utc(end)}",
        f"SUMMARY:{_escape(f'Case practice: {case_title}')}",
        f"DESCRIPTION:{_escape(f'Join your CaseRoom practice session: {session_url}')}",
        f"URL:{session_url}",
        f"ORGANIZER;CN={_escape(organizer_name)}:mailto:{organizer_email}",
        (f"ATTENDEE;CN={_escape(attendee_name)};ROLE=REQ-PARTICIPANT;"
         f"PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{attendee_email}"),
        "STATUS:CONFIRMED",
        "SEQUENCE:0",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    return "\r\n".join(_fold(line) for line in lines) + "\r\n"
