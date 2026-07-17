"""
Purpose: /api/v1 profile, avatar upload, and notification-settings endpoints.
Inputs:  session-cookie auth (require_auth_api); multipart avatar upload; JSON
         bodies for profile + settings; STORAGE_* env for the avatar backend.
Outputs: UPDATEs users profile fields, writes avatars/{user_id}.{ext} to storage,
         UPSERTs notification_settings.
Run:     registered in webapp/main.py; e.g. GET /api/v1/profile.
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

from pipeline.storage import get_storage
from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.repositories import notification_settings as notif_repo
from webapp.repositories import profile as profile_repo

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]

# content-type -> (extension, magic-byte prefix validator)
_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5 MB


class ProfileUpdate(BaseModel):
    display_name: Optional[str] = Field(default=None, max_length=100)
    bio: Optional[str] = Field(default=None, max_length=2000)
    linkedin_url: Optional[str] = Field(default=None, max_length=300)


class NotificationSettingsUpdate(BaseModel):
    proposals: Optional[bool] = None
    session_reminders: Optional[bool] = None
    feedback: Optional[bool] = None
    free_now: Optional[bool] = None
    community: Optional[bool] = None


def _profile_json(user_id: int) -> dict:
    p = profile_repo.get_profile(user_id)
    if p is None:
        raise HTTPException(status_code=404, detail="not_found")
    photo_url = get_storage().url(p["photo_key"]) if p["photo_key"] else None
    return {**{k: p[k] for k in
               ("id", "email", "display_name", "bio", "linkedin_url", "school")},
            "photo_url": photo_url}


def _sniff_ok(content_type: str, data: bytes) -> bool:
    """Reject content-type spoofing: the bytes must match the declared type."""
    if content_type == "image/png":
        return data[:8] == b"\x89PNG\r\n\x1a\n"
    if content_type == "image/jpeg":
        return data[:3] == b"\xff\xd8\xff"
    if content_type == "image/webp":
        return data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    return False


@router.get("/profile")
def get_profile(user: User = Depends(require_auth_api)):
    return _profile_json(user.id)


@router.put("/profile", dependencies=_MUTATING)
def put_profile(body: ProfileUpdate, user: User = Depends(require_auth_api)):
    profile_repo.update_profile(
        user.id,
        display_name=body.display_name,
        bio=body.bio,
        linkedin_url=body.linkedin_url,
    )
    return _profile_json(user.id)


@router.post("/profile/photo", dependencies=_MUTATING)
async def upload_photo(user: User = Depends(require_auth_api),
                       file: UploadFile = File(...)):
    content_type = (file.content_type or "").lower()
    if content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="unsupported_media_type")

    data = await file.read()
    if len(data) > _MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="file_too_large")
    if not _sniff_ok(content_type, data):
        raise HTTPException(status_code=415, detail="content_does_not_match_type")

    ext = _ALLOWED_IMAGE_TYPES[content_type]
    # Key is derived from the AUTHENTICATED user's id — never from client input.
    key = f"avatars/{user.id}.{ext}"
    get_storage().write(key, data, content_type=content_type)
    profile_repo.set_photo_key(user.id, key)
    return {"photo_url": get_storage().url(key)}


@router.get("/settings/notifications")
def get_notifications(user: User = Depends(require_auth_api)):
    return notif_repo.get_settings(user.id)


@router.put("/settings/notifications", dependencies=_MUTATING)
def put_notifications(body: NotificationSettingsUpdate,
                      user: User = Depends(require_auth_api)):
    flags = {k: v for k, v in body.model_dump().items() if v is not None}
    return notif_repo.update_settings(user.id, **flags)
