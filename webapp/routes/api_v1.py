"""
/api/v1 router — the native-app API surface (iOS P1). Task 6-8 add more
routes here; keep this module's `router` a clean import point for them.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import Response
from pydantic import BaseModel, Field

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.repositories import device_tokens as repo

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]


class DeviceTokenBody(BaseModel):
    token: str
    platform: str = Field(default="ios")


@router.post("/devices", status_code=204, dependencies=_MUTATING)
def register_device(body: DeviceTokenBody, user: User = Depends(require_auth_api)):
    repo.upsert_token(user.id, body.token, body.platform)
    return Response(status_code=204)


@router.delete("/devices/{token}", status_code=204, dependencies=_MUTATING)
def unregister_device(token: str, user: User = Depends(require_auth_api)):
    repo.delete_token(token)
    return Response(status_code=204)
