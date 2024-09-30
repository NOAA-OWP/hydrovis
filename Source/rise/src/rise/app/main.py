from contextlib import asynccontextmanager

from fastapi import FastAPI, status
from fastapi.responses import Response

from src.rise.app.api.router import api_router
from src.rise.app.core.cache import get_settings
from src.rise.app.core.logging_module import setup_logger
from src.rise.app.core.rabbit_connection import rabbit_connection

settings = get_settings()

logger = setup_logger("default", "app.log")


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Defining the rabbitmq connection"""
    await rabbit_connection.connect()
    yield
    await rabbit_connection.disconnect()


app = FastAPI(title=settings.project_name, lifespan=lifespan)

app.include_router(api_router, prefix=settings.api_v1_str)


@app.head("/health")
async def health_check() -> Response:
    """Establishing uptime through a healthcheck

    Returns:
    --------
    Response:
        An HTTP 200 response
    """
    return Response(status_code=status.HTTP_200_OK)
