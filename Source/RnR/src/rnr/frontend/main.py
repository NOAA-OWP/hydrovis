from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from src.rnr.frontend.api.router import frontend_router
from src.rnr.frontend.core import get_settings

settings = get_settings()

app = FastAPI(
    title=settings.project_name,
)

app.mount("/data", StaticFiles(directory="data"), name="data")
app.mount("/static", StaticFiles(directory="static"), name="static")

app.include_router(frontend_router, prefix=settings.frontend_v1_str)
