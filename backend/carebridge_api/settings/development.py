"""
CareBridge API — 開發環境設定
"""
from .base import *

DEBUG = True

ALLOWED_HOSTS = ['*']

# 開發環境使用 SQLite（不需要 PostgreSQL）
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

# 開發環境 CORS 允許所有
CORS_ALLOW_ALL_ORIGINS = True

# 開發環境也啟用 BrowsableAPI
REST_FRAMEWORK['DEFAULT_RENDERER_CLASSES'] = (
    'rest_framework.renderers.JSONRenderer',
    'rest_framework.renderers.BrowsableAPIRenderer',
)

# Celery 開發環境同步執行
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

# 開發環境 Email 輸出到 console
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

print('CareBridge API -- Development Mode')
