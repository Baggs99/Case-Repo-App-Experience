"""
Purpose: Guest account upgrade — POST /api/v1/auth/upgrade converts the current
         guest row into a real account in place (spec §6.2, "keep it on a
         record?"), preserving every FK to session history.
Inputs:  JSON body {email, password}; the guest session cookie (require_guest).
Outputs: Mutates the guest's users row (is_guest→FALSE, real email/password).
Run:     included from webapp.main via app.include_router(guest_routes.router)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from webapp.auth.guest import GuestUpgradeConflict, require_guest, upgrade_guest
from webapp.auth.passwords import WeakPasswordError
from webapp.auth.users import InvalidEmailDomain, EmailAlreadyRegistered, User
from webapp.csrf import require_same_origin

router = APIRouter(tags=["guest"])

_MUTATING = [Depends(require_same_origin)]


class UpgradeBody(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=1024)


@router.post("/api/v1/auth/upgrade", dependencies=_MUTATING)
def upgrade(body: UpgradeBody, user: User = Depends(require_guest)):
    """Convert the current guest to a real account in place (history FKs stay
    attached). require_guest guarantees the caller is a guest (403 otherwise)."""
    try:
        upgraded = upgrade_guest(user.id, body.email, body.password)
    except InvalidEmailDomain as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except WeakPasswordError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except EmailAlreadyRegistered as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except GuestUpgradeConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return {"upgraded": True, "user_id": upgraded.id, "email": upgraded.email}
