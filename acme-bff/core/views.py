from django.db import DatabaseError, connections
from django.http import JsonResponse
from rest_framework.decorators import api_view, authentication_classes, permission_classes

from core.jwks import public_jwk


@api_view(["GET"])
@authentication_classes([])
@permission_classes([])
def health_check(request) -> JsonResponse:
    """Liveness plus the one dependency that matters.

    Answering 200 while the database is unreachable makes this useless as a
    deploy readiness signal — the proxy would be reloaded onto a container that
    cannot serve a single request.
    """
    try:
        with connections["default"].cursor() as cursor:
            cursor.execute("SELECT 1")
    except DatabaseError:
        return JsonResponse({"status": "degraded", "database": "unreachable"}, status=503)

    return JsonResponse({"status": "ok"})


@api_view(["GET"])
@authentication_classes([])
@permission_classes([])
def jwks(request) -> JsonResponse:
    """The public half of the signing key.

    Deliberately unauthenticated: a public key is public, and the gateway must
    be able to fetch it before it can authenticate anything.
    """
    return JsonResponse({"keys": [public_jwk()]})
