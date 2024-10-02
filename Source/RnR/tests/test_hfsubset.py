import httpx
import pytest

from src.rnr.app.api.client.hfsubset import subset
from src.rnr.app.core.settings import Settings


def get_settings_override() -> Settings:
    """Overriding the BaseSettings for testing

    Returns
    -------
    Settings
        The test settings
    """
    return Settings(testing_queue="testing")


@pytest.mark.asyncio
async def test_subset() -> None:
    """Testing the gauges identifier

    Parameters
    ----------
    identifier: str
        The gauge identification (USGS ID, LID, etc.)
    """
    feature_id = 13361908
    try:
        response = subset(feature_id, "http://localhost:8008/api/v1")
    except httpx.HTTPStatusError as e:
        raise e
    except httpx.ConnectError:
        pytest.skip("Cannot test this as the docker compose is not up")
    assert isinstance(response, dict), "Response invalid"
    assert (
        response["message"] == "Subset created successfully"
        or response["message"] == "Subset pulled from cache"
    ), "Subset not created correctly"
