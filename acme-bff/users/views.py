"""Login, refresh and logout, with the refresh token kept out of JavaScript.

The access token is short-lived and returned in the body, where the SPA keeps
it in memory only. The refresh token is long-lived and never touches the
response body: it goes in an HttpOnly cookie, so an XSS can make requests while
the tab is open but cannot steal a credential that outlives it.
"""

from django.conf import settings
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from users.serializers import UserSerializer


def _set_refresh_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        settings.AUTH_REFRESH_COOKIE_NAME,
        token,
        httponly=True,
        secure=settings.AUTH_REFRESH_COOKIE_SECURE,
        samesite=settings.AUTH_REFRESH_COOKIE_SAMESITE,
        path=settings.AUTH_REFRESH_COOKIE_PATH,
        domain=settings.AUTH_REFRESH_COOKIE_DOMAIN,
    )


class CookieTokenObtainPairView(TokenObtainPairView):
    throttle_scope = "auth_login"

    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        refresh = response.data.pop("refresh", None)
        if refresh:
            _set_refresh_cookie(response, refresh)
        return response


class CookieTokenRefreshView(TokenRefreshView):
    throttle_scope = "auth_refresh"

    def post(self, request, *args, **kwargs):
        cookie = request.COOKIES.get(settings.AUTH_REFRESH_COOKIE_NAME)
        if cookie:
            # The SPA cannot read the cookie, so it cannot put the token in the
            # body. Inject it here so SimpleJWT's serializer sees what it
            # expects without the client ever holding it.
            request.data["refresh"] = cookie
        elif not request.data.get("refresh"):
            # SimpleJWT would answer 400 for a missing field. The client treats
            # 401 as "your session is over, go to login" and 400 as "this
            # request was malformed, do not retry" — and a cleared or expired
            # cookie is the former.
            return Response(
                {"detail": "No refresh token."}, status=status.HTTP_401_UNAUTHORIZED
            )

        response = super().post(request, *args, **kwargs)
        rotated = response.data.pop("refresh", None)
        if rotated:
            _set_refresh_cookie(response, rotated)
        return response


class CookieTokenLogoutView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        cookie = request.COOKIES.get(settings.AUTH_REFRESH_COOKIE_NAME)
        if cookie:
            try:
                RefreshToken(cookie).blacklist()
            except TokenError:
                # Already expired or already blacklisted. The user asked to be
                # logged out and they are; there is nothing to report.
                pass

        response = Response(status=status.HTTP_204_NO_CONTENT)
        response.delete_cookie(
            settings.AUTH_REFRESH_COOKIE_NAME,
            path=settings.AUTH_REFRESH_COOKIE_PATH,
            domain=settings.AUTH_REFRESH_COOKIE_DOMAIN,
        )
        return response


class LoggedUserView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """Identity plus both gates, in one call.

        The SPA needs the permissions and entitlements maps to decide what to
        render, and getting them from the same payload as the user means they
        cannot be fetched out of step with each other.
        """
        return Response(UserSerializer(request.user).data)
