from django.conf import settings
from django.contrib import admin
from django.urls import include, path

from core.csp_report import csp_report
from core.views import health_check, jwks

urlpatterns = [
    path(f"{settings.ADMIN_PATH}/", admin.site.urls),
    path("api/health", health_check, name="health"),
    # The gateway fetches this to verify every token it forwards (ADR-001).
    path("api/.well-known/jwks.json", jwks, name="jwks"),
    # Anonymous by design; the gateway routes /api/public/ to public-anon-chain.
    path("api/public/csp-report/", csp_report, name="csp-report"),
    path("api/auth/", include("users.urls")),
    path("api/example/", include("example.urls")),
]
