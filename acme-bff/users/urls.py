from django.urls import path

from users.views import (
    CookieTokenLogoutView,
    CookieTokenObtainPairView,
    CookieTokenRefreshView,
    LoggedUserView,
)

urlpatterns = [
    path("token/", CookieTokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("token/refresh/", CookieTokenRefreshView.as_view(), name="token_refresh"),
    path("token/logout/", CookieTokenLogoutView.as_view(), name="token_logout"),
    path("logged/", LoggedUserView.as_view(), name="auth_logged"),
]
