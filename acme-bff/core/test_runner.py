import logging
import os

from django.test.runner import DiscoverRunner


class QuietTestRunner(DiscoverRunner):
    """Silence application logging during the suite.

    The suite deliberately exercises failure paths, and each one logs a warning
    with a stack trace. Left on, the real signal — which test failed — scrolls
    off the top, and people stop reading the output at all. That defeats C-8,
    which is built on the output being the evidence.

    Set SHOW_TEST_LOGS=1 when you are debugging one of those paths.
    """

    def run_tests(self, *args, **kwargs):
        if os.environ.get("SHOW_TEST_LOGS") != "1":
            logging.disable(logging.CRITICAL)
        return super().run_tests(*args, **kwargs)
