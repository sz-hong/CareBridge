import logging
from urllib.parse import urlparse

import boto3
from botocore.client import Config
from django.conf import settings

logger = logging.getLogger(__name__)


def _get_s3_client(endpoint_url=None):
    """
    Create and return a boto3 S3 client using Django settings.

    Expected settings:
        AWS_ACCESS_KEY_ID: AWS access key.
        AWS_SECRET_ACCESS_KEY: AWS secret key.
        AWS_S3_REGION_NAME: AWS region (default 'ap-northeast-1').
        AWS_STORAGE_BUCKET_NAME: The S3 bucket name.
        AWS_S3_ENDPOINT_URL: Optional custom endpoint URL (for S3-compatible services).
    """
    region = getattr(settings, 'AWS_S3_REGION_NAME', 'ap-northeast-1')
    if endpoint_url is None:
        endpoint_url = getattr(settings, 'AWS_S3_ENDPOINT_URL', None)

    client_kwargs = {
        'service_name': 's3',
        'region_name': region,
        'aws_access_key_id': getattr(settings, 'AWS_ACCESS_KEY_ID', None),
        'aws_secret_access_key': getattr(settings, 'AWS_SECRET_ACCESS_KEY', None),
    }

    if endpoint_url:
        # MinIO / S3-compatible services require path-style addressing
        # (virtual-hosted style needs DNS for <bucket>.<host>, which doesn't
        # exist for localhost). Also pin SigV4 so presigned URLs verify.
        client_kwargs['endpoint_url'] = endpoint_url
        client_kwargs['config'] = Config(
            signature_version='s3v4',
            s3={'addressing_style': 'path'},
        )

    return boto3.client(**client_kwargs)


def _get_bucket_name():
    """Return the configured S3 bucket name."""
    bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
    if not bucket:
        raise RuntimeError(
            'AWS_STORAGE_BUCKET_NAME is not configured in Django settings.'
        )
    return bucket


def _get_public_endpoint_url():
    return (
        getattr(settings, 'AWS_S3_PUBLIC_ENDPOINT_URL', None)
        or getattr(settings, 'AWS_S3_ENDPOINT_URL', None)
    )


def generate_upload_url(key, content_type, expires=3600):
    """
    Generate a pre-signed URL for uploading a file to S3.

    Args:
        key (str): The S3 object key (path) for the upload.
        content_type (str): The MIME content type of the file (e.g. 'image/png').
        expires (int): URL expiration time in seconds (default 3600).

    Returns:
        str: A pre-signed URL that allows PUT upload to the specified key.
    """
    client = _get_s3_client(endpoint_url=_get_public_endpoint_url())
    bucket = _get_bucket_name()

    url = client.generate_presigned_url(
        ClientMethod='put_object',
        Params={
            'Bucket': bucket,
            'Key': key,
            'ContentType': content_type,
        },
        ExpiresIn=expires,
    )

    logger.info('Generated upload URL for key: %s (expires in %ds)', key, expires)
    return url


def generate_download_url(key, expires=3600):
    """
    Generate a pre-signed URL for downloading a file from S3.

    Args:
        key (str): The S3 object key (path) to download.
        expires (int): URL expiration time in seconds (default 3600).

    Returns:
        str: A pre-signed URL that allows GET download of the specified key.
    """
    client = _get_s3_client(endpoint_url=_get_public_endpoint_url())
    bucket = _get_bucket_name()

    url = client.generate_presigned_url(
        ClientMethod='get_object',
        Params={
            'Bucket': bucket,
            'Key': key,
        },
        ExpiresIn=expires,
    )

    logger.info('Generated download URL for key: %s (expires in %ds)', key, expires)
    return url


def download_bytes(key):
    """Download an object from S3-compatible storage as bytes."""
    client = _get_s3_client()
    bucket = _get_bucket_name()
    response = client.get_object(Bucket=bucket, Key=key)
    return response['Body'].read()


def put_bytes(key, data, content_type):
    """Upload bytes to S3-compatible storage."""
    client = _get_s3_client()
    bucket = _get_bucket_name()
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=data,
        ContentType=content_type,
    )
    logger.info('Uploaded object for key: %s', key)


def delete_object(key):
    """Delete an object from S3-compatible storage."""
    client = _get_s3_client()
    bucket = _get_bucket_name()
    client.delete_object(Bucket=bucket, Key=key)
    logger.info('Deleted object for key: %s', key)


def build_public_url(key):
    """Build a bare (non-presigned) URL for an S3 object key."""
    bucket = _get_bucket_name()
    endpoint = _get_public_endpoint_url()
    if endpoint:
        return f'{endpoint.rstrip("/")}/{bucket}/{key}'
    region = getattr(settings, 'AWS_S3_REGION_NAME', 'ap-northeast-1')
    return f'https://{bucket}.s3.{region}.amazonaws.com/{key}'


def extract_key_from_url(url):
    """Extract the S3 object key from a bare (non-presigned) URL."""
    if not url:
        return None
    path = urlparse(url).path.lstrip('/')
    bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
    if bucket and path.startswith(f'{bucket}/'):
        path = path[len(bucket) + 1:]
    return path or None
