from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Configuration settings for the frontend application.

    This class uses Pydantic's BaseSettings to manage configuration,
    allowing for easy integration with environment variables and
    configuration files.
    """

    frontend_v1_str: str = "/frontend/v1"

    csv_docs_location: str = "data/rfc_channel_forcings"

    project_name: str = "Replace and Route"
