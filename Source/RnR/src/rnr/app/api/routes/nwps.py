from typing import Annotated

from fastapi import APIRouter, Depends

from src.rnr.app.api.services.nwps import NWPSService
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.schemas import GaugeData, GaugeForecast

router = APIRouter()


@router.get("/{lid}", response_model=GaugeData)
async def get_gauge_data(
    lid: str, settings: Annotated[Settings, Depends(get_settings)]
) -> GaugeData:
    """A route to get the gauge metadata

    Parameters
    ----------
    lid: str
    - The identifier for the API endpoint
    
    settings: Settings
    - The BaseSettings config object

    Returns
    -------
    GaugeData
    - The validated gauge metadata
    """
    return await NWPSService.get_gauge_data(lid, settings)


@router.get("/{lid}/forecast", response_model=GaugeForecast)
async def get_gauge_product_forecast(
    lid: str, settings: Annotated[Settings, Depends(get_settings)]
) -> GaugeForecast:
    """ A route to get the gauge forecast

    Parameters
    ----------
    lid: str
    - The identifier for the API endpoint
    
    settings: Settings
    - The BaseSettings config object

    Returns
    -------
    GaugeForecast
    - The validated gauge forecast
    """
    return await NWPSService.get_gauge_product_forecast(lid, settings)
