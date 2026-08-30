from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.mixins import TenantQuerysetMixin
from example.models import ExampleRecord
from example.permissions import AccountHasExampleEntitlement
from example.serializers import ExampleRecordSerializer
from example.services import deliver_example_record
from users.permissions import HasFeaturePermission, ResourceArea


class ExampleRecordViewSet(TenantQuerysetMixin, viewsets.ModelViewSet):
    """The reference viewset shape.

    Three permission classes, stacked deliberately: authenticated, then the
    plan gate, then the role gate (C-2). Reordering them changes which error
    the client sees, and "upgrade your plan" is a different message from
    "ask your admin".
    """

    serializer_class = ExampleRecordSerializer
    permission_classes = [IsAuthenticated, AccountHasExampleEntitlement, HasFeaturePermission]
    resource_area = ResourceArea.EXAMPLE
    filterset_fields = ["status"]
    ordering_fields = ["created_at", "status"]

    def get_queryset(self):
        return self.filter_by_tenant(
            ExampleRecord.objects.filter(is_active=True).select_related("account")
        )

    def perform_create(self, serializer) -> None:
        # The account comes from the authenticated user, never from the body.
        # Accepting it from the client is how one tenant writes into another.
        serializer.save(account=self.request.user.account)

    def perform_destroy(self, instance) -> None:
        instance.deactivate()

    def destroy(self, request, *args, **kwargs):
        # 200 with the row rather than 204: the client can show what it just
        # archived, and a soft delete is not really a deletion (C-7).
        instance = self.get_object()
        self.perform_destroy(instance)
        return Response(self.get_serializer(instance).data, status=status.HTTP_200_OK)

    @action(detail=True, methods=["post"])
    def deliver(self, request, pk=None):
        """Attempt delivery now.

        Always 200: the service function never raises, and the row carries the
        verdict. A 502 here would make the client handle a failure the domain
        has already absorbed (C-1).
        """
        record = deliver_example_record(self.get_object())
        return Response(self.get_serializer(record).data)
