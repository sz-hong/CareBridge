import logging

import boto3
from django.conf import settings

logger = logging.getLogger(__name__)


def _get_s3_client():
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
    endpoint_url = getattr(settings, 'AWS_S3_ENDPOINT_URL', None)

    client_kwargs = {
        'service_name': 's3',
        'region_name': region,
        'aws_access_key_id': getattr(settings, 'AWS_ACCESS_KEY_ID', None),
        'aws_secret_access_key': getattr(settings, 'AWS_SECRET_ACCESS_KEY', None),
    }

    if endpoint_url:
        client_kwargs['endpoint_url'] = endpoint_url

    return boto3.client(**client_kwargs)


def _get_bucket_name():
    """Return the configured S3 bucket name."""
    bucket = getattr(settings, 'AWS_STORAGE_BUCKET_NAME', None)
    if not bucket:
        raise RuntimeError(
            'AWS_STORAGE_BUCKET_NAME is not configured in Django settings.'
        )
    return bucket


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
    client = _get_s3_client()
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
    client = _get_s3_client()
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
