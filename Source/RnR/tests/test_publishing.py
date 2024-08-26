import time

import pytest
import sqlalchemy
from fastapi.testclient import TestClient
from httpx import ASGITransport, AsyncClient

from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.rabbit_connection import rabbit_connection
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import AsyncRateLimiter
from src.rnr.app.main import app


def get_settings_override() -> Settings:
    """Overriding the BaseSettings for testing

    Returns
    -------
    Settings
        The test settings
    """
    return Settings(
        priority_queue="testing_floods",
        base_queue="testing_non_floods",
        error_queue="testing_errors",
        log_path="./logs/"
    )


app.dependency_overrides[get_settings] = get_settings_override
client = TestClient(app)


@pytest.mark.asyncio
async def test_single_message_passing(rfc_table_identifier: str) -> None:
    """Testing a single, successful passed message

    Parameters
    ----------
    rfc_table_identifier: str
        The identifier for a successful message
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        try:
            await rabbit_connection.connect()
            response = await ac.post(f"/api/v1/publish/start/{rfc_table_identifier}")
        except sqlalchemy.exc.OperationalError:
            pytest.skip("Cannot test this as docker compose is not up")
        except AttributeError:
            pytest.skip("Cannot test this as docker compose is not up")
        assert response.status_code == 200, "Invalid route"
        data = response.json()
        assert data["summary"]["success"] == 1, "Problem with your request"
        assert data["results"][0]["status"] == "success", "Problem with your request"
        await rabbit_connection.disconnect()


@pytest.mark.asyncio
async def test_single_no_forecast_passing(no_rfc_forecast_identifier: str) -> None:
    """Testing a single passed message that does not have a forecast

    Parameters
    ----------
    no_rfc_forecast_identifier: str
        The identifier that has no forecast
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        try:
            response = await ac.post(
                f"/api/v1/publish/start/{no_rfc_forecast_identifier}"
            )
        except sqlalchemy.exc.OperationalError:
            pytest.skip("Cannot test this as docker compose is not up")
        except AttributeError:
            pytest.skip("Cannot test this as docker compose is not up")
        assert response.status_code == 200, "Invalid route"
        data = response.json()
        assert data["summary"]["no_forecast"] == 1, "Not picking up the API error"
        assert (
            data["results"][0]["error_type"] == "NoForecastError"
        ), "Not picking up the API error"


@pytest.mark.asyncio
async def test_single_error_passing(no_gauge_identifier: str) -> None:
    """Testing a single passed message that does not exist in the API

    Parameters
    ----------
    no_gauge_identifier: str
        The identifier that creates an error
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        try:
            await rabbit_connection.connect()
            response = await ac.post(f"/api/v1/publish/start/{no_gauge_identifier}")
        except sqlalchemy.exc.OperationalError:
            pytest.skip("Cannot test this as docker compose is not up")
        except AttributeError:
            pytest.skip("Cannot test this as docker compose is not up")
        assert response.status_code == 200, "Invalid route"
        data = response.json()
        assert data["summary"]["api_error"] == 1, "Not picking up the API error"
        assert (
            data["results"][0]["error_type"] == "NWPSAPIError"
        ), "Not picking up the API error"
        await rabbit_connection.disconnect()


# @pytest.mark.asyncio
# async def test_all_message_passing():
#     async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
#         response =  await ac.post("/api/v1/rnr/start/")

#         assert response.status_code == 200, "Invalid route"
#         data = response.json()
#         print(data)


@pytest.mark.asyncio
async def test_rate_limiter_basic() -> None:
    """Testing the rate limiter implemented in this endpoint"""
    limiter = AsyncRateLimiter(rate_limit=10, time_period=1)
    start_time = time.time()

    for _ in range(10):
        async with limiter:
            pass

    end_time = time.time()
    assert end_time - start_time < 1, "10 operations should complete within 1 second"
