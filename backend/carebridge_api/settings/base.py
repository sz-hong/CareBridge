"""
CareBridge API — 共用設定
"""
import os
from pathlib import Path
from datetime import timedelta
from dotenv import load_dotenv
from corsheaders.defaults import default_headers

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def env_list(name, default=''):
    raw = os.environ.get(name, default)
    return [item.strip() for item in raw.split(',') if item.strip()]


SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'django-insecure-change-me-in-production')

ALLOWED_HOSTS = env_list('ALLOWED_HOSTS', 'localhost,127.0.0.1')

# ==============================================================================
# Application Definition
# ==============================================================================

DJANGO_APPS = [
    'daphne',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

THIRD_PARTY_APPS = [
    'channels',
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'django_filters',
]

LOCAL_APPS = [
    'apps.auth_account',
    'apps.family',
    'apps.chat',
    'apps.board',
    'apps.care_log',
    'apps.medication',
    'apps.expense',
    'apps.leave',
    'apps.health',
    'apps.calendar_event',
    'apps.todo',
    'apps.document',
    'apps.ai_assistant',
    'apps.sos',
    'apps.notification',
    'apps.admin_api',
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'apps.admin_api.middleware.AdminRequestLogMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'carebridge_api.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'carebridge_api.wsgi.application'
ASGI_APPLICATION = 'carebridge_api.asgi.application'

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [os.environ.get('REDIS_URL', 'redis://localhost:6379/2')],
        },
    },
}

# ==============================================================================
# Authentication
# ==============================================================================

AUTH_USER_MODEL = 'auth_account.User'

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ==============================================================================
# Django REST Framework
# ==============================================================================

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'core.pagination.StandardPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_FILTER_BACKENDS': (
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ),
    'EXCEPTION_HANDLER': 'core.exceptions.custom_exception_handler',
    'DEFAULT_RENDERER_CLASSES': (
        'rest_framework.renderers.JSONRenderer',
    ),
    'DATETIME_FORMAT': 'iso-8601',
    'DATE_FORMAT': 'iso-8601',
}

# ==============================================================================
# Simple JWT
# ==============================================================================

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=1),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
}

# ==============================================================================
# Internationalization
# ==============================================================================

LANGUAGE_CODE = 'zh-hant'
TIME_ZONE = 'Asia/Taipei'
USE_I18N = True
USE_TZ = True

# ==============================================================================
# Static Files
# ==============================================================================

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# ==============================================================================
# File Upload
# ==============================================================================

DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB

# ==============================================================================
# Default Primary Key
# ==============================================================================

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ==============================================================================
# CORS
# ==============================================================================

CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = env_list(
    'CORS_ALLOWED_ORIGINS',
    'http://localhost:3000,http://127.0.0.1:3000,https://shao-zhen.com,http://127.0.0.1:4173,http://localhost:4321'
)
CORS_ALLOW_CREDENTIALS = False
CORS_ALLOW_HEADERS = list(default_headers)

# ==============================================================================
# Celery
# ==============================================================================

CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://localhost:6379/1')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://localhost:6379/1')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = 'Asia/Taipei'
ADMIN_REQUEST_LOG_RETENTION_DAYS = int(os.environ.get('ADMIN_REQUEST_LOG_RETENTION_DAYS', '14'))
ADMIN_AUDIT_LOG_RETENTION_DAYS = int(os.environ.get('ADMIN_AUDIT_LOG_RETENTION_DAYS', '180'))
CELERY_BEAT_SCHEDULE = {
    'delete-expired-admin-logs-daily': {
        'task': 'apps.admin_api.tasks.delete_expired_admin_logs_task',
        'schedule': 86400.0,
    },
    'delete-expired-document-quarantine-files-hourly': {
        'task': 'apps.document.tasks.delete_expired_document_quarantine_files_task',
        'schedule': 3600.0,
    },
    'delete-expired-receipt-quarantine-files-hourly': {
        'task': 'apps.expense.tasks.delete_expired_receipt_quarantine_files_task',
        'schedule': 3600.0,
    },
    'delete-read-notifications-daily': {
        'task': 'apps.notification.tasks.delete_read_notifications_task',
        'schedule': 86400.0,
    },
}

# ==============================================================================
# Cache (Redis)
# ==============================================================================

CACHES = {
    'default': {
        'BACKEND': 'django_redis.cache.RedisCache',
        'LOCATION': os.environ.get('REDIS_URL', 'redis://localhost:6379/0'),
        'OPTIONS': {
            'CLIENT_CLASS': 'django_redis.client.DefaultClient',
        },
    }
}

# ==============================================================================
# AWS S3 Storage
# ==============================================================================

AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID', '')
AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY', '')
AWS_STORAGE_BUCKET_NAME = os.environ.get('AWS_STORAGE_BUCKET_NAME', 'carebridge-storage')
AWS_S3_REGION_NAME = os.environ.get('AWS_S3_REGION_NAME', 'ap-northeast-1')
# Set to http://localhost:9000 for local MinIO; leave blank for real AWS S3.
AWS_S3_ENDPOINT_URL = os.environ.get('AWS_S3_ENDPOINT_URL') or None
# Optional externally reachable endpoint used only when signing client-facing
# upload/download URLs. This lets Docker talk to MinIO through `minio:9000`
# while physical devices use the Mac's Tailscale/LAN address.
AWS_S3_PUBLIC_ENDPOINT_URL = (
    os.environ.get('AWS_S3_PUBLIC_ENDPOINT_URL') or AWS_S3_ENDPOINT_URL
)
AWS_QUERYSTRING_AUTH = True
AWS_QUERYSTRING_EXPIRE = 3600  # Presigned URL 有效期 1 小時

# ==============================================================================
# External API Keys
# ==============================================================================

OPENAI_API_KEY = os.environ.get('OPENAI_API_KEY', '')
OPENAI_MODEL = os.environ.get('OPENAI_MODEL', 'gpt-4o')
OPENAI_EMBEDDING_MODEL = os.environ.get('OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small')

# ==============================================================================
# De-identification / DLP
# ==============================================================================

DLP_PROVIDER = os.environ.get('DLP_PROVIDER', 'mock')
GOOGLE_CLOUD_PROJECT = os.environ.get('GOOGLE_CLOUD_PROJECT', '')
GOOGLE_DLP_LOCATION = os.environ.get('GOOGLE_DLP_LOCATION', 'global')
DLP_MIN_LIKELIHOOD = os.environ.get('DLP_MIN_LIKELIHOOD', 'LIKELY')
DLP_DELETE_RAW_AFTER_HOURS = int(os.environ.get('DLP_DELETE_RAW_AFTER_HOURS', '24'))
DLP_INFO_TYPES = env_list(
    'DLP_INFO_TYPES',
    'EMAIL_ADDRESS,PHONE_NUMBER,CREDIT_CARD_NUMBER,PERSON_NAME,STREET_ADDRESS,'
    'DATE_OF_BIRTH,MEDICAL_RECORD_NUMBER,TAIWAN_PHONE_NUMBER,TAIWAN_NATIONAL_ID,'
    'TAIWAN_ARC_ID,NHI_CARD_NUMBER,BANK_ACCOUNT',
)

# ==============================================================================
# APNs
# ==============================================================================

APNS_AUTH_KEY_PATH = os.environ.get('APNS_AUTH_KEY_PATH', '')
APNS_KEY_ID = os.environ.get('APNS_KEY_ID', '')
APNS_TEAM_ID = os.environ.get('APNS_TEAM_ID', '')
APNS_TOPIC = os.environ.get('APNS_TOPIC', 'com.carebridge.app')
APNS_USE_SANDBOX = os.environ.get('APNS_USE_SANDBOX', 'True').lower() == 'true'

# ==============================================================================
# Logging
# ==============================================================================

LOG_DIR = BASE_DIR / 'logs'
LOG_DIR.mkdir(parents=True, exist_ok=True)

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'standard': {
            'format': '{asctime} {name} {levelname} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'standard',
        },
        'runtime_file': {
            'class': 'logging.FileHandler',
            'filename': LOG_DIR / 'runtime.log',
            'formatter': 'standard',
            'encoding': 'utf-8',
        },
        'api_errors_file': {
            'class': 'logging.FileHandler',
            'filename': LOG_DIR / 'api-errors.log',
            'formatter': 'standard',
            'encoding': 'utf-8',
        },
    },
    'loggers': {
        'carebridge.api': {
            'handlers': ['console', 'api_errors_file'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['console', 'runtime_file'],
        'level': 'INFO',
    },
}
