from fastapi import FastAPI, status
from fastapi.responses import Response

from src.rnr.app.api.router import api_router
from src.rnr.app.core.cache import get_settings

settings = get_settings()

app = FastAPI(
    title=settings.project_name,
)

app.include_router(api_router, prefix=settings.api_v1_str)


@app.head("/health")
async def health_check():
    return Response(status_code=status.HTTP_200_OK)
