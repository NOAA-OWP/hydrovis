import pika

from src.rise.app.core.cache import Settings


def start_work_queues(
    connection: pika.BlockingConnection, settings: Settings
) -> pika.BlockingConnection.channel:
    """
    Initialize work queues.

    Parameters
    ----------
    connection : pika.BlockingConnection
    - The RabbitMQ connection.

    settings : Settings
    - The application settings.

    Returns
    -------
    pika.BlockingConnection.channel
    - The initialized channel with declared queues.
    """
    channel = connection.channel()
    channel.queue_declare(queue=settings.priority_queue, durable=True)
    channel.queue_declare(queue=settings.base_queue, durable=True)
    channel.queue_declare(queue=settings.error_queue, durable=True)
    return channel


def start_connection(url: str) -> pika.BlockingConnection:
    """
    Start a RabbitMQ connection.

    Parameters
    ----------
    url : str
    - The URL for the RabbitMQ server.

    Returns
    -------
    pika.BlockingConnection
    - The established RabbitMQ connection.
    """
    connection = pika.BlockingConnection(pika.ConnectionParameters(url))
    return connection


def close_connection(connection: pika.BlockingConnection) -> None:
    """
    Close a RabbitMQ connection.

    Parameters
    ----------
    connection : pika.BlockingConnection
    - The RabbitMQ connection to close.
    """
    connection.close()


def publish_messages(
    message: str, channel: pika.BlockingConnection.channel, queue: str
) -> None:
    """
    Publish processed data messages to a specified queue.

    Parameters
    ----------
    processed_data : ProcessedData
    - The processed data to be published.

    channel : pika.BlockingConnection.channel
    - The RabbitMQ channel for publishing.

    queue : str
    - The name of the queue to publish to.
    """
    channel.basic_publish(
        exchange="",
        routing_key=queue,
        body=message,
        properties=pika.BasicProperties(delivery_mode=pika.DeliveryMode.Persistent),
    )


def publish_error(
    channel: pika.BlockingConnection.channel,
    error_queue: str,
    message: str = "Default error message",
) -> None:
    """
    Publish error messages to a specified error queue.

    Parameters
    ----------
    channel : pika.BlockingConnection.channel
    - The RabbitMQ channel for publishing.

    error_queue : str
    - The name of the error queue to publish to.

    message : str, optional
    - The error message to be published. Defaults to "Default error message".
    """
    channel.basic_publish(
        exchange="",
        routing_key=error_queue,
        body=message,
        properties=pika.BasicProperties(delivery_mode=pika.DeliveryMode.Persistent),
    )
