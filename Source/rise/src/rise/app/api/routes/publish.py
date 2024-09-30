from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends

from src.rise.app.api.services.publish import MessagePublisherService
from src.rise.app.core.cache import get_settings
from src.rise.app.core.settings import Settings
from src.rise.app.schemas import HTTPStatus, PublishSingleMessage

router = APIRouter()


@router.get("/start/", response_model=PublishSingleMessage)
async def publish_single_message(
    background_tasks: BackgroundTasks,
    settings: Annotated[Settings, Depends(get_settings)],
) -> PublishSingleMessage:
    async def _publish():
        return await MessagePublisherService.publish_forecast(settings)

    background_tasks.add_task(_publish)

    return PublishSingleMessage(
        status=HTTPStatus.OK, message="Published message successfully"
    )
