from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, str]:
    """Unauthenticated, and it checks nothing.

    There is no database and no warm state to verify: if the process answers,
    it can serve. The container healthcheck and the deploy's readiness wait
    both key on this.
    """
    return {"status": "ok"}
