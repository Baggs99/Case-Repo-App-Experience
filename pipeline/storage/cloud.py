"""
Cloud storage backend — Cloudflare R2 (S3-compatible).

Speaks the same `Storage` interface as `LocalStorage` so the web app and
publisher don't care which backend is configured.

Used in production. Construct via `R2Storage.from_env()`, which reads:
  - R2_BUCKET_NAME
  - R2_ENDPOINT             (https://<account-id>.r2.cloudflarestorage.com)
  - R2_ACCESS_KEY_ID
  - R2_SECRET_ACCESS_KEY

Pricing relevant constraints
----------------------------
- Pre-signed URL expiry capped at 7 days (S3/R2 hard limit).
- We default to 1-hour pre-signed URLs to keep students from sharing links
  with the wider internet.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import BinaryIO, Optional

from .base import Storage, validate_key

logger = logging.getLogger(__name__)


try:
    import boto3
    from botocore.config import Config
    from botocore.exceptions import ClientError

    _HAS_BOTO3 = True
except ImportError:
    _HAS_BOTO3 = False


class R2Storage(Storage):
    """Cloudflare R2 backend, accessed via boto3's S3 client."""

    DEFAULT_PRESIGN_EXPIRY = 3600       # 1 hour
    MAX_PRESIGN_EXPIRY = 7 * 24 * 3600  # 7 days, S3/R2 hard limit

    def __init__(
        self,
        *,
        bucket: str,
        endpoint: str,
        access_key: str,
        secret_key: str,
    ):
        if not _HAS_BOTO3:
            raise RuntimeError(
                "boto3 is required for R2Storage. Install with: pip install boto3"
            )

        self.bucket = bucket
        self.endpoint = endpoint

        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name="auto",
            config=Config(
                signature_version="s3v4",
                retries={"max_attempts": 3, "mode": "adaptive"},
            ),
        )

    @classmethod
    def from_env(cls) -> "R2Storage":
        """Build an R2Storage instance from environment variables."""
        required = ("R2_BUCKET_NAME", "R2_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY")
        missing = [k for k in required if not os.environ.get(k, "").strip()]
        if missing:
            raise RuntimeError(
                f"Missing required env var(s) for R2: {', '.join(missing)}. "
                "Populate these in .env or your deployment's secret manager."
            )
        return cls(
            bucket=os.environ["R2_BUCKET_NAME"].strip(),
            endpoint=os.environ["R2_ENDPOINT"].strip(),
            access_key=os.environ["R2_ACCESS_KEY_ID"].strip(),
            secret_key=os.environ["R2_SECRET_ACCESS_KEY"].strip(),
        )

    def exists(self, key: str) -> bool:
        validate_key(key)
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError as e:
            code = str(e.response.get("Error", {}).get("Code", ""))
            status = e.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
            if code in ("404", "NoSuchKey", "NotFound") or status == 404:
                return False
            raise

    def open(self, key: str) -> BinaryIO:
        validate_key(key)
        obj = self.client.get_object(Bucket=self.bucket, Key=key)
        return obj["Body"]

    def size(self, key: str) -> int:
        validate_key(key)
        return int(self.client.head_object(Bucket=self.bucket, Key=key)["ContentLength"])

    def url(
        self,
        key: str,
        expires_in: Optional[int] = None,
        *,
        attachment_filename: Optional[str] = None,
    ) -> str:
        validate_key(key)
        expires = expires_in if expires_in is not None else self.DEFAULT_PRESIGN_EXPIRY
        expires = min(int(expires), self.MAX_PRESIGN_EXPIRY)
        params: dict = {"Bucket": self.bucket, "Key": key}
        if attachment_filename:
            safe = attachment_filename.replace('"', "").replace("\r", "").replace("\n", "")
            params["ResponseContentDisposition"] = (
                f'attachment; filename="{safe}"'
            )
        return self.client.generate_presigned_url(
            "get_object",
            Params=params,
            ExpiresIn=expires,
        )

    def put_file(
        self,
        key: str,
        src: Path,
        *,
        content_type: str = "application/pdf",
        cache_control: str | None = None,
    ) -> None:
        """Upload a local file to R2 under `key`.

        Used by the bulk uploader; not part of the abstract Storage interface
        because reads & writes have different concurrency / auth needs in
        practice.
        """
        validate_key(key)
        src = Path(src)
        if not src.is_file():
            raise FileNotFoundError(f"source file does not exist: {src}")

        extras: dict = {}
        if cache_control:
            extras["CacheControl"] = cache_control

        with src.open("rb") as f:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=f,
                ContentType=content_type,
                **extras,
            )

    def __repr__(self) -> str:
        return f"R2Storage(bucket={self.bucket!r}, endpoint={self.endpoint!r})"
