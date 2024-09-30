import json

from src.rise.app.core.logging_module import setup_logger
from src.rise.app.core.rabbit_connection import rabbit_connection
from src.rise.app.core.settings import Settings
from src.rise.app.schemas import ProcessedData

# import redis


log = setup_logger("default", "publisher.log")

# _settings = get_settings()

# r_cache = redis.Redis(host=_settings.redis_url, port=6379, decode_responses=True)


class MessagePublisherService:
    @staticmethod
    async def publish_forecast(
        settings: Settings,
    ) -> None:
        lid = "test"
        processed_data = ProcessedData(message="Sending Message")
        message = json.dumps(processed_data.model_dump_json())
        log.info(f"Sending message for LID: {lid}")
        await rabbit_connection.send_message(
            message=message, routing_key=settings.base_queue
        )
