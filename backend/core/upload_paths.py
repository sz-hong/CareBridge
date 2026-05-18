import mimetypes
import uuid


CONTENT_TYPE_EXTENSIONS = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/heic': 'heic',
    'application/pdf': 'pdf',
    'text/plain': 'txt',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
}


def extension_for_upload(content_type, filename=None, default='bin'):
    if filename and '.' in filename:
        candidate = filename.rsplit('.', 1)[1].lower()
        if candidate.isalnum() and len(candidate) <= 8:
            return candidate

    if content_type in CONTENT_TYPE_EXTENSIONS:
        return CONTENT_TYPE_EXTENSIONS[content_type]

    guessed = mimetypes.guess_extension(content_type or '')
    if guessed:
        return guessed.lstrip('.').lower()
    return default


def build_quarantine_key(family_id, object_type, content_type, filename=None):
    ext = extension_for_upload(content_type, filename)
    return f'quarantine/{family_id}/{object_type}/{uuid.uuid4().hex}.{ext}'


def processed_key_for_raw_key(raw_key, content_type=None):
    key = raw_key.replace('quarantine/', 'processed/', 1)
    if not content_type:
        return key

    ext = extension_for_upload(content_type)
    if '.' not in key.rsplit('/', 1)[-1]:
        return f'{key}.{ext}'
    stem = key.rsplit('.', 1)[0]
    return f'{stem}.{ext}'


def is_valid_quarantine_key(raw_key, family_id, object_type):
    if not raw_key:
        return False
    if '\\' in raw_key or '//' in raw_key or '..' in raw_key:
        return False
    expected_prefix = f'quarantine/{family_id}/{object_type}/'
    return raw_key.startswith(expected_prefix) and not raw_key.endswith('/')
