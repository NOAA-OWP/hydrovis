from datetime import datetime

from src.rnr.app.api.client.nwps import gauge_data, gauge_product
from src.rnr.app.core.exceptions import NoForecastError
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import convert_to_m3_per_sec
from src.rnr.app.schemas import GaugeData, GaugeForecast


class NWPSService:
    """
    Service class for reading National Weather Prediction Service (NWPS) data from their API.

    This class provides static methods to interact with the API and retrieve
    RFC/Gauge forecast data. It encapsulates the logic for querying the database,
    processing the results, and creating Gauge objects.

    Methods
    -------
    get_gauge_data(identifier: str, settings: Settings) -> GaugeData
        Asynchronously get gauge metadata.
    get_gauge_product_forecast(identifier: str, settings: Settings) -> GaugeForecast
        Asynchronously get gauge forecast data.
    """

    @staticmethod
    async def get_gauge_data(identifier: str, settings: Settings) -> GaugeData:
        """ "An async method for getting gauge metadata

        Parameters
        ----------
        identifier : str
            The identifier for the API endpoint.
        settings : Settings
            The application settings.

        Returns
        -------
        GaugeData
            Validated outputs based on the API docs.
        """
        api_url = settings.base_url
        data = await gauge_data(identifier, api_url)
        return GaugeData(**data)

    @staticmethod
    async def get_gauge_product_forecast(
        identifier: str, settings: Settings
    ) -> GaugeForecast:
        """ "An async method for getting gauge forecast data

        Parameters
        ----------
        identifier : str
            The identifier for the API endpoint.
        settings : Settings
            The application settings.

        Returns
        -------
        GaugeForecast
            Validated outputs based on the API docs.

        Raises
        ------
        NoForecastError
            If no forecast data is available for the given identifier.
        """
        api_url = settings.base_url
        gauge_forecast = await gauge_product(identifier, api_url, "forecast")
        gauge_observations = await gauge_product(identifier, api_url, "observed")

        latest_observation_units = gauge_observations["secondaryUnits"]
        latest_observation_flow = [gauge_observations["data"][-1]["secondary"]]

        times = [
            datetime.fromisoformat(entry["validTime"].rstrip("Z"))
            for entry in gauge_forecast["data"]
        ]
        primary_forecast = [entry["primary"] for entry in gauge_forecast["data"]]
        secondary_forecast = [entry["secondary"] for entry in gauge_forecast["data"]]

        if len(secondary_forecast) == 0:
            raise NoForecastError(identifier=identifier)

        secondary_m3_forecast, secondary_units = convert_to_m3_per_sec(
            secondary_forecast, gauge_forecast["secondaryUnits"]
        )

        latest_observation_m3, latest_obs_units = convert_to_m3_per_sec(
            latest_observation_flow, latest_observation_units
        )

        return GaugeForecast(
            times=times,
            primary_name=gauge_forecast["primaryName"],
            primary_forecast=primary_forecast,
            primary_unit=gauge_forecast["primaryUnits"],
            latest_observation=latest_observation_m3, 
            latest_obs_units=latest_obs_units, 
            secondary_name=gauge_forecast["secondaryName"],
            secondary_forecast=secondary_m3_forecast,
            secondary_unit=secondary_units,
        )
