from dataclasses import dataclass
from typing import Any, Dict, List, Union

from aio_pika import Message, connect_robust
from aio_pika.abc import AbstractRobustChannel, AbstractRobustConnection

from src.rise.app.core.cache import get_settings
from src.rise.app.core.settings import Settings


@dataclass
class RabbitConnection:
    settings: Settings
    connection: Union[AbstractRobustConnection, None] = None
    channel: Union[AbstractRobustChannel, None] = None

    def status(self) -> bool:
        """
        Checks if connection established

        :return: True if connection established
        """
        if self.connection.is_closed or self.channel.is_closed:
            return False
        return True

    async def _clear(self) -> None:
        if not self.channel.is_closed:
            await self.channel.close()
        if not self.connection.is_closed:
            await self.connection.close()

        self.connection = None
        self.channel = None

    async def connect(self) -> None:
        """
        Establish connection with the RabbitMQ
        """
        print("Connecting to RabbitMQ")
        try:
            self.connection = await connect_robust(self.settings.aio_pika_url)
            self.channel = await self.connection.channel(publisher_confirms=False)
            print("Successfully connected to RabbitMQ")
        except Exception as e:
            await self._clear()
            print(e.__dict__)

    async def disconnect(self) -> None:
        """
        Disconnect and clear connections from RabbitMQ
        """
        await self._clear()

    async def send_message(
        self, message: Union[List[Any], Dict[str, Any]], routing_key: str
    ) -> None:
        """
        Public message or messages to the RabbitMQ queue.

        :param messages: list or dict with messages objects.
        :param routing_key: Routing key of RabbitMQ, not required. Tip: the same as in the consumer.
        """
        if not self.channel:
            raise RuntimeError(
                "Message could not be sent as there is no RabbitMQ Connection"
            )

        async with self.channel.transaction():
            message = Message(body=message.encode())

            await self.channel.default_exchange.publish(
                message,
                routing_key=routing_key,
            )


rabbit_connection = RabbitConnection(get_settings())
