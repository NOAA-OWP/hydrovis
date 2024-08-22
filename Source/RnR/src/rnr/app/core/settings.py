import os
from pathlib import Path

from pydantic import ConfigDict
from pydantic_settings import BaseSettings

from src.rnr.app.core.utils import read_config


class Settings(BaseSettings):
    """
    Configuration settings for the application.

    This class uses Pydantic's BaseSettings to manage configuration,
    allowing for easy integration with environment variables and
    configuration files.

    Parameters
    ----------
    **data : dict
        Additional keyword arguments to be passed to the parent class.

    Attributes
    ----------
    base_url : str
        The base URL for the NWPS API containing RFC informational data.
    sqlalchemy_database_url : str
        SQLAlchemy connection string for the main database.
    pika_url : str
        The URL for connecting to RabbitMQ.
    flooded_queue : str
        Queue name for sending data regarding flooded RFC locations.
    nonflooded_queue : str
        Queue name for sending data regarding non-flooded RFC locations.
    error_queue : str
        Queue name for sending any RFC locations that error out.

    Notes
    -----
    The configuration is initially read from a 'config.ini' file and can be
    overridden by environment variables.
    """

    api_v1_str: str = "/api/v1"

    base_url: str = "https://api.water.noaa.gov/nwps/v1"
    base_subset_url: str = "http://localhost:8008/api/v1"

    # download_dir: Path = Path.cwd().parents[1] / "data"
    output_file: str = "{}_output.gpkg"
    gpkg_map: Path = Path("/app/src/rnr/app/core/hf_id_to_divide_id_mapping.json")
    csv_forcing_path: Path = Path("/app/data/rfc_channel_forcings/")
    domain_path: str = "/app/data/rfc_geopackage_data/{}/subset.gpkg"

    sqlalchemy_database_url: str = "postgresql://{}:{}@localhost/{}"

    pika_url: str = "localhost"
    redis_url: str = "localhost"
    base_subset_url: str = "http://localhost:8008/api/v1"
    base_troute_url: str = "http://localhost:8004/api/v1"
    project_name: str = "Replace and Route"

    priority_queue: str = "flooded_data_queue"
    base_queue: str = "non_flooded_data_queue"
    error_queue: str = "error_queue"
    model_config = ConfigDict(extra="allow", arbitrary_types_allowed=True)

    def __init__(self, **data):
        super(Settings, self).__init__(**data)
        if os.getenv("SQLALCHEMY_DATABASE_URL") is not None:
            self.sqlalchemy_database_url = os.getenv("SQLALCHEMY_DATABASE_URL")

        try:
            config = read_config("config.ini")
            self.sqlalchemy_database_url = self.sqlalchemy_database_url.format(
                config.get("Database", "user"),
                config.get("Database", "password"),
                config.get("Database", "dbname"),
            )
        except FileNotFoundError:
            self.sqlalchemy_database_url = self.sqlalchemy_database_url.format(
                os.getenv("USER"),
                os.getenv("PASSWORD"),
                os.getenv("DBNAME")
            )

        if os.getenv("PIKA_URL") is not None:
            self.pika_url = os.getenv("PIKA_URL")
        if os.getenv("REDIS_URL") is not None:
            self.redis_url = os.getenv("REDIS_URL")
        if os.getenv("SUBSET_URL") is not None:
            self.base_subset_url = os.getenv("SUBSET_URL")
        if os.getenv("TROUTE_URL") is not None:
            self.base_troute_url = os.getenv("TROUTE_URL")
