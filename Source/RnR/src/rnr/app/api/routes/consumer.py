from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel

from src.rnr.app.cache import get_consumer_manager
from src.rnr.app.consumer_manager import ConsumerManager
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.schemas import ConsumerStatus

router = APIRouter()


class Message(BaseModel):
    message: str = "Notification sent in the background"


@router.post("/start", response_model=Message)
async def start_consumer_endpoint(
    background_tasks: BackgroundTasks,
    settings: Settings = Depends(get_settings),
    consumer_manager: ConsumerManager = Depends(get_consumer_manager),
) -> Message:
    background_tasks.add_task(consumer_manager.start_consumer, settings)
    return Message()


@router.post("/stop", response_model=Message)
async def stop_consumer_endpoint(
    background_tasks: BackgroundTasks,
    consumer_manager: ConsumerManager = Depends(get_consumer_manager),
) -> Message:
    background_tasks.add_task(consumer_manager.stop_consumer)
    return Message()


@router.get("/status", response_model=ConsumerStatus)
async def get_consumer_status(
    consumer_manager: ConsumerManager = Depends(get_consumer_manager),
) -> ConsumerStatus:
    return consumer_manager.status
