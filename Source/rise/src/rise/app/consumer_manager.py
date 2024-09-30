import asyncio

import aio_pika

from src.rise.app.api.services.rise import RISE
from src.rise.app.core.cache import get_settings
from src.rise.app.core.logging_module import setup_logger
from src.rise.app.core.settings import Settings

PARALLEL_TASKS = 10

log = setup_logger("default", "consumer.log")


async def main(settings: Settings) -> None:
    """The consumer manager main function to define queues

    Parameters:
    -----------
    settings: Settings
        API settings object
    """
    connection = await aio_pika.connect_robust(settings.aio_pika_url)
    rise = RISE()

    async with connection:
        channel = await connection.channel()
        await channel.set_qos(prefetch_count=PARALLEL_TASKS)
        base_queue = await channel.declare_queue(
            settings.base_queue,
            durable=True,
        )
        error_queue = await channel.declare_queue(
            settings.error_queue,
            durable=True,
        )

        log.info("Consumer started")

        await base_queue.consume(rise.process_request)
        await error_queue.consume(rise.process_error)

        try:
            await asyncio.Future()
        finally:
            await connection.close()


if __name__ == "__main__":
    log.info("Starting Consumer")
    asyncio.run(main(get_settings()))
