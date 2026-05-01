"""
Cloud storage backends — to be implemented when you're ready to deploy.

Recommended provider: Cloudflare R2
-----------------------------------
- S3-compatible API (works with boto3)
- 10 GB free storage
- Zero egress fees (S3 charges per GB pulled out — adds up fast)
- One-click signed URLs for fine-grained access control

Skeleton (uncomment + finish when ready):

    import boto3
    from botocore.config import Config
    from .base import Storage, validate_key

    class R2Storage(Storage):
        def __init__(self, bucket: str, account_id: str, access_key: str, secret_key: str):
            self.bucket = bucket
            self.client = boto3.client(
                "s3",
                endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
                aws_access_key_id=access_key,
                aws_secret_access_key=secret_key,
                config=Config(signature_version="s3v4"),
            )

        def exists(self, key):
            validate_key(key)
            try:
                self.client.head_object(Bucket=self.bucket, Key=key)
                return True
            except self.client.exceptions.ClientError:
                return False

        def open(self, key):
            validate_key(key)
            obj = self.client.get_object(Bucket=self.bucket, Key=key)
            return obj["Body"]

        def size(self, key):
            validate_key(key)
            return self.client.head_object(Bucket=self.bucket, Key=key)["ContentLength"]

        def url(self, key, expires_in=3600):
            validate_key(key)
            return self.client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self.bucket, "Key": key},
                ExpiresIn=expires_in or 3600,
            )

Don't forget to:
  1. pip install boto3
  2. add R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET to .env
  3. wire R2Storage into get_storage() in pipeline/storage/__init__.py
  4. write a one-time `python main.py upload-pdfs` command to push every
     local PDF up to the bucket using the same storage keys
"""
