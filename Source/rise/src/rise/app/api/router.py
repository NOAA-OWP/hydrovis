from fastapi import APIRouter

from src.rise.app.api.routes import publish

api_router = APIRouter()
api_router.include_router(
    publish.router,
    prefix="/publish",
    tags=["Publish Forecasts to the RISE pipeline"],
)
