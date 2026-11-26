from decouple import Csv

# BASE_DIR is re-exported through this module's star import, which is how
# the rest of the settings package and Django itself reach it.
# Do NOT add __all__ here: it would restrict `from .base import *` to just
# the listed names and silently drop every setting in this file.
from core.settings.env import BASE_DIR, config

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "django_filters",
    "corsheaders",
    "common",
    "accounts",
    "users",
    "audit",
    "example",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "core.urls"
WSGI_APPLICATION = "core.wsgi.application"
ASGI_APPLICATION = "core.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": config("DB_NAME", default="acme"),
        "USER": config("DB_USER", default="acme"),
        "PASSWORD": config("DB_PASSWORD", default=""),
        "HOST": config("DB_HOST", default="localhost"),
        "PORT": config("DB_PORT", default="5432"),
        # MIRROR makes the test runner use DB_NAME directly instead of creating
        # a throwaway database. That is deliberate — it keeps CI and local runs
        # on one migration path — but it means you MUST point DB_NAME at a
        # scratch database when testing, never at your dev data. See C-8.
        # TEST_PARALLEL opts out for CI's `manage.py test --parallel`: it needs
        # a test database of its own to clone per worker, and MIRROR leaves it none.
        "TEST": {} if config("TEST_PARALLEL", default=False, cast=bool) else {"MIRROR": "default"},
    }
}

AUTH_USER_MODEL = "users.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# Throttle counters must be shared across gunicorn workers, or the effective
# rate is (configured rate x worker count). A local-memory cache silently
# multiplies every limit; the database cache does not, and this application
# does not run Redis.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "cache_table",
    }
}

LANGUAGE_CODE = "en-us"
TIME_ZONE = config("TIME_ZONE", default="UTC")
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
TEST_RUNNER = "core.test_runner.QuietTestRunner"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": config("PAGE_SIZE", default=25, cast=int),
    "DEFAULT_FILTER_BACKENDS": ("django_filters.rest_framework.DjangoFilterBackend",),
    "DEFAULT_THROTTLE_CLASSES": ("rest_framework.throttling.ScopedRateThrottle",),
    "DEFAULT_THROTTLE_RATES": {
        "auth_login": config("AUTH_LOGIN_THROTTLE_RATE", default="5/min"),
        "auth_refresh": config("AUTH_REFRESH_THROTTLE_RATE", default="30/min"),
        "webhook": config("WEBHOOK_THROTTLE_RATE", default="60/min"),
    },
    # The gateway is the only ingress, so REMOTE_ADDR is the gateway and the
    # real client is the last entry in X-Forwarded-For. One proxy, one hop.
    "NUM_PROXIES": config("NUM_PROXIES", default=1, cast=int),
}

ADMIN_PATH = config("DJANGO_ADMIN_PATH", default="admin")
CORS_ALLOWED_ORIGINS = config("CORS_ALLOWED_ORIGINS", default="", cast=Csv())
CORS_ALLOW_CREDENTIALS = True
