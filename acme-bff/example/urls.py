from rest_framework.routers import DefaultRouter

from example.views import ExampleRecordViewSet

router = DefaultRouter()
router.register("records", ExampleRecordViewSet, basename="example-record")

urlpatterns = router.urls
