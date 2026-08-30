"""Settings, split by concern rather than by environment.

There is one environment shape and many knobs; every value comes from the
environment through `decouple.config` with a default. A `base/dev/prod` split
would put the interesting differences in a file nobody reads on the box.

Import order matters: `security` defines DEBUG, which `base` does not need but
`sentry` below does.
"""

from core.settings.base import *  # noqa: F401,F403
from core.settings.security import *  # noqa: F401,F403
from core.settings.celery import *  # noqa: F401,F403
from core.settings.logging_conf import *  # noqa: F401,F403
from core.settings.services import *  # noqa: F401,F403

if SENTRY_DSN:  # noqa: F405
    import sentry_sdk
    from sentry_sdk.integrations.django import DjangoIntegration

    from core.sentry import scrub_event

    sentry_sdk.init(
        dsn=SENTRY_DSN,  # noqa: F405
        environment=SENTRY_ENVIRONMENT,  # noqa: F405
        integrations=[DjangoIntegration()],
        traces_sample_rate=SENTRY_TRACES_SAMPLE_RATE,  # noqa: F405
        send_default_pii=False,
        # Local variables in a stack frame routinely hold a decrypted
        # credential. Sending them would defeat C-3 at the one moment it
        # matters most.
        include_local_variables=False,
        before_send=scrub_event,
    )
