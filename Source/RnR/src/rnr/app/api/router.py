from fastapi import APIRouter

from src.rnr.app.api.routes import consumer, nwps, publish, rfc

api_router = APIRouter()
api_router.include_router(nwps.router, prefix="/nwps", tags=["NWPS Forecast Retrieval"])
api_router.include_router(rfc.router, prefix="/rfc", tags=["RFC Information"])
api_router.include_router(
    publish.router,
    prefix="/publish",
    tags=["Publish Forecasts to the Replace and Route pipeline"],
)
api_router.include_router(
    consumer.router, prefix="/consumer", tags=["The Replace and Route Pipeline"]
)
