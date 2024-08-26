from typing import List

import pytest
from fastapi.testclient import TestClient
from httpx import ASGITransport, AsyncClient

from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import convert_to_m3_per_sec
from src.rnr.app.main import app
from src.rnr.app.schemas import GaugeForecast


def get_settings_override() -> Settings:
    """Overriding the BaseSettings for testing

    Returns
    -------
    Settings
        The test settings
    """
    return Settings(testing_queue="testing", log_path="./logs/")


app.dependency_overrides[get_settings] = get_settings_override
client = TestClient(app)


@pytest.mark.asyncio
async def test_get_gauge_data(identifier: str) -> None:
    """Testing the gauges identifier

    Parameters
    ----------
    identifier: str
        The gauge identification (USGS ID, LID, etc.)
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        response = await ac.get(f"/api/v1/nwps/{identifier}")

        assert response.status_code == 200


@pytest.mark.asyncio
async def test_get_gauge_forecast(identifier: str) -> None:
    """Testing the gauge forecast endpoint

    Parameters
    ----------
    identifier: str
        The gauge identification (USGS ID, LID, etc.)
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        response = await ac.get(f"/api/v1/nwps/{identifier}/forecast")

        assert response.status_code == 200
        data = response.json()

        gauge_forecast = GaugeForecast(**data)
        assert len(gauge_forecast.times) > 0
        assert len(gauge_forecast.primary_forecast) > 0
        assert len(gauge_forecast.secondary_forecast) > 0
        assert gauge_forecast.primary_name != ""
        assert gauge_forecast.secondary_name != ""
        assert gauge_forecast.primary_unit != ""
        assert gauge_forecast.secondary_unit != ""


def test_convert_to_m3_per_sec(kcfs_data: List[float]) -> None:
    """Testing the conversion from kcfs to m3/s

    Parameters
    ----------
    kcfs_data: List[float]
        The data in kcfs
    """
    result, unit = convert_to_m3_per_sec(kcfs_data, "kcfs")

    assert unit == "m3 s-1"
    assert len(result) == len(kcfs_data)
    assert result[0] == pytest.approx(566.33693, rel=1e-5)  # 20 kcfs in m3/s
