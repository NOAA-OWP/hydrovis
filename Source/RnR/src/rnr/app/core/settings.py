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
    csv_forcing_path: Path = Path("/app/data/rfc_channel_forcings/")
    domain_path: str = "/app/data/rfc_geopackage_data/{}/subset.gpkg"
    downstream_domain_path: str = "/app/data/rfc_geopackage_data/{}/downstream.gpkg"
    plot_path: str = "/app/data/plots/{}"
    troute_output_path: str = "/app/data/troute_output/"
    rnr_output_path: str = "/app/data/replace_and_route/{}"
    rnr_output_file: str = "replace_route.t{}z.medium_range.channel_rt.nc"

    sqlalchemy_database_url: str = "postgresql://{}:{}@{}/{}"

    rate_limit: int = 12

    pika_url: str = "localhost"

    rabbitmq_default_username: str = "guest"
    rabbitmq_default_password: str = "guest"
    rabbitmq_default_host: str = "localhost"
    rabbitmq_default_port: int = 5672

    aio_pika_url: str = "ampq://{}:{}@{}:{}/"
    redis_url: str = "localhost"
    base_subset_url: str = "http://localhost:8008/api/v1"
    base_troute_url: str = "http://localhost:8004/api/v1"
    project_name: str = "Replace and Route"

    priority_queue: str = "flooded_data_queue"
    base_queue: str = "non_flooded_data_queue"
    error_queue: str = "error_queue"

    log_path: str = "/app/data/logs"

    db_host: str = "localhost"

    troute_output_format: str = "/app/data/troute_output/{}/troute_output_{}.nc"
    processed_output_form: str = "nwc.{0}"
    forcing_regex: str = "\d{12}\.CHRTOUT_DOMAIN1"
    hydro_rst_datetime_format: str = "%Y-%m-%d_%H:00"
    # forecast_output = f'replace_route/{ana_datetime_str[:-4]}/forecasts/{ana_datetime_str[-4:-2]}Z_run_issue_times.csv'
    # troute_output = f'replace_route/{ana_datetime_str[:-4]}/wrf_hydro/{os.path.basename(f)}'
    forecast_output: str = "replace_route/{}/forecasts/{}Z_run_issue_times.csv"

    model_config = ConfigDict(extra="allow", arbitrary_types_allowed=True)

    def __init__(self, **data):
        super(Settings, self).__init__(**data)
        if os.getenv("SQLALCHEMY_DATABASE_URL") is not None:
            self.sqlalchemy_database_url = os.getenv("SQLALCHEMY_DATABASE_URL")
        if os.getenv("RABBITMQ_HOST") is not None:
            self.rabbitmq_default_host = os.getenv("RABBITMQ_HOST")
        if os.getenv("DB_HOST") is not None:
            self.db_host = os.getenv("DB_HOST")

        try:
            config = read_config("config.ini")
            self.sqlalchemy_database_url = self.sqlalchemy_database_url.format(
                config.get("Database", "user"),
                config.get("Database", "password"),
                self.db_host,
                config.get("Database", "dbname"),
            )
        except FileNotFoundError:
            self.sqlalchemy_database_url = self.sqlalchemy_database_url.format(
                os.getenv("USER"), os.getenv("PASSWORD"), self.db_host, os.getenv("DBNAME")
            )

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
        if os.getenv("SUBSET_URL") is not None:
            self.base_subset_url = os.getenv("SUBSET_URL")
        if os.getenv("TROUTE_URL") is not None:
            self.base_troute_url = os.getenv("TROUTE_URL")
