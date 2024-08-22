from datetime import datetime, timezone

import pytest
import sqlalchemy
from fastapi.testclient import TestClient
from httpx import ASGITransport, AsyncClient

from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import parse_datetime
from src.rnr.app.main import app


def get_settings_override() -> Settings:
    """Overriding the BaseSettings for testing

    Returns
    -------
    Settings
        The test settings
    """
    return Settings(testing_queue="testing")


app.dependency_overrides[get_settings] = get_settings_override
client = TestClient(app)


def test_parse_datetime(timestamp: str) -> None:
    """A function for testing the parse_datetime utils

    Parameters
    ----------
    timestamp: str
        The sample timestamp string to test
    """
    expected_datetime = datetime(2024, 6, 12, 1, 50, 0, tzinfo=timezone.utc)
    converted_datetime = parse_datetime(timestamp)
    assert (
        converted_datetime == expected_datetime
    ), f"Parsed datetime {converted_datetime} does not match expected {expected_datetime}"


@pytest.mark.asyncio
async def test_rfc_routes() -> None:
    """Testing to see if the localhost route is working"""
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        try:
            response = await ac.get("/api/v1/rfc/")
        except sqlalchemy.exc.OperationalError:
            pytest.skip("Cannot test as docker compose is not up")
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_single_rfc_route(rfc_table_identifier: str) -> None:
    """Testing to see if the localhost route is working

    Parameters
    ----------
    rfc_table_identifier: str
        The LID identifier we're testing with
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        try:
            response = await ac.get(f"/api/v1/rfc/{rfc_table_identifier}")
        except sqlalchemy.exc.OperationalError:
            pytest.skip("Cannot test as docker compose is not up")
        assert response.status_code == 200
