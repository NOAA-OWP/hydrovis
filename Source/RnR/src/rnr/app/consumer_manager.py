import asyncio

from src.rnr.app.api.client.pika import (close_connection, start_connection,
                                         start_work_queues)
from src.rnr.app.api.services.error_handler import ErrorHandler
from src.rnr.app.api.services.replace_and_route import ReplaceAndRoute
from src.rnr.app.core.settings import Settings
from src.rnr.app.schemas import ConsumerStatus


class ConsumerManager:
    def __init__(self):
        self._status = ConsumerStatus(is_running=False)
        self._connection = None
        self._channel = None

    @property
    def status(self):
        return self._status

    @status.setter
    def status(self, value):
        if isinstance(value, ConsumerStatus):
            self._status = value
        else:
            raise ValueError("Status must be an instance of ConsumerStatus")

    @staticmethod
    def error_callback(ch, method, properties, body):
        error_handler = ErrorHandler()
        error_handler.process_request(ch, method, properties, body)
        ch.basic_ack(delivery_tag=method.delivery_tag)

    @staticmethod
    def callback(ch, method, properties, body):
        rnr = ReplaceAndRoute()
        _ = rnr.process_request(ch, method, properties, body)
        ch.basic_ack(delivery_tag=method.delivery_tag)

    async def start_consumer(self, settings: Settings):
        if not self.status.is_running:
            await self._run_consumer(settings)

    async def stop_consumer(self):
        if self.status.is_running:
            await self._stop_consumer()

    async def _run_consumer(self, settings: Settings):
        self.status.is_running = True
        try:
            self._connection = start_connection(settings.pika_url)
            self._channel = start_work_queues(self._connection, settings)

            self._channel.basic_qos(prefetch_count=1)
            self._channel.basic_consume(
                queue=settings.priority_queue, on_message_callback=self.callback
            )
            self._channel.basic_consume(
                queue=settings.base_queue, on_message_callback=self.callback
            )
            self._channel.basic_consume(
                queue=settings.error_queue, on_message_callback=self.error_callback
            )

            print(" [x] Awaiting requests")

            while self.status.is_running:
                self._connection.process_data_events(time_limit=1)
                await asyncio.sleep(0.1)  # Allow other tasks to run

        except Exception as e:
            print(f"An error occurred: {e}")
        finally:
            await self._close_connection()

    async def _stop_consumer(self):
        self.status.is_running = False
        await self._close_connection()

    async def _close_connection(self):
        if self._connection:
            close_connection(self._connection)
            self._connection = None
            self._channel = None
        self.status.is_running = False

    def get_status(self):
        return self.status
