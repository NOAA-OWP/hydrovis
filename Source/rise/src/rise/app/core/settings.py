import os

from pydantic import ConfigDict
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Configuration settings for the application.

    This class uses Pydantic's BaseSettings to manage configuration,
    allowing for easy integration with environment variables and
    configuration files.

    Parameters
    ----------
    **data : dict
    - Additional keyword arguments to be passed to the parent class.

    Attributes
    ----------
    api_v1_str: str
        The API header
    rate_limit: int = 8
        The amount of concurrent requests
    rabbitmq_default_username: str
        The default rabbitmq login username
    rabbitmq_default_password: str
        The default rabbitmq password
    rabbitmq_default_host: str
        The default hostname for rabbitmq
    rabbitmq_default_port: int
        The default port for rasbbitmq
    aio_pika_url: str
        The URL for aiopika to be handling requests
    redis_url: str
        The URL for REDIS hosting
    project_name: str
        The name of the API
    base_queue: str
        The name of the base_queue
    error_queue: str
        The name of the error_queue
    log_path: str
        The path to where the logs are written to

    Notes
    -----
    The configuration is initially read from a 'config.ini' file and can be
    overridden by environment variables.
    """

    api_v1_str: str = "/api/v1"

    rate_limit: int = 8

    rabbitmq_default_username: str = "guest"
    rabbitmq_default_password: str = "guest"
    rabbitmq_default_host: str = "localhost"
    rabbitmq_default_port: int = 5672

    aio_pika_url: str = "ampq://{}:{}@{}:{}/"
    redis_url: str = "localhost"
    project_name: str = "RISE"

    base_queue: str = "rise_queue"
    error_queue: str = "error_queue"

    log_path: str = "/app/data/logs"

    model_config = ConfigDict(extra="allow", arbitrary_types_allowed=True)

    def __init__(self, **data):
        super(Settings, self).__init__(**data)
        if os.getenv("RABBITMQ_HOST") is not None:
            self.rabbitmq_default_host = os.getenv("RABBITMQ_HOST")

        self.aio_pika_url = self.aio_pika_url.format(
            self.rabbitmq_default_username,
            self.rabbitmq_default_password,
            self.rabbitmq_default_host,
            self.rabbitmq_default_port,
        )

        if os.getenv("PIKA_URL") is not None:
            self.pika_url = os.getenv("PIKA_URL")
        if os.getenv("REDIS_URL") is not None:
            self.redis_url = os.getenv("REDIS_URL")
