from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    """Base for every wire schema: camelCase JSON, snake_case Python.

    The only place in the service that knows the wire is camelCase. Domain
    models stay snake_case and never grow an alias (C-5).
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
    )
