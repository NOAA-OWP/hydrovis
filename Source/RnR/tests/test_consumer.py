# import time

# import pytest
# from fastapi.testclient import TestClient
# from httpx import ASGITransport, AsyncClient

# from src.rnr.app.core import get_settings
# from src.rnr.app.core.settings import Settings
# from src.rnr.app.main import app
# from src.rnr.app.consumer_manager import ConsumerManager
# from src.rnr.app.api.routes.consumer import get_consumer_manager


# def get_settings_override() -> Settings:
#     """Overriding the BaseSettings for testing

#     Returns
#     -------
#     Settings
#         The test settings
#     """
#     return Settings(
#         priority_queue="testing_floods",
#         base_queue="testing_non_floods",
#         error_queue="testing_errors",
#     )


# app.dependency_overrides[get_settings] = get_settings_override
# client = TestClient(app)


# @pytest.mark.asyncio
# async def test_consumer_lifecycle():
#     """Currently only testing the status as there are problems spawning the consumer in a testing suite
#     """
#     async with AsyncClient(
#         transport=ASGITransport(app=app), base_url="http://test"
#     ) as ac:
#         response =  await ac.get("/api/v1/consumer/status")
#         assert response.status_code == 200
#         assert response.json() == {'is_running': False}

#         response =  await ac.post("/api/v1/consumer/start")
#         assert response.status_code == 200
#         assert response.json() == {"message": "Notification sent in the background"}

#         response =  await ac.get("/api/v1/consumer/status")
#         assert response.status_code == 200
#         assert response.json() == {'is_running': True}

#         # Stop the consumer
#         response =  await ac.post("/api/v1/consumer/stop")
#         assert response.status_code == 200
#         assert response.json() == {"message": "Notification sent in the background"}

#         response =  await ac.get("/api/v1/consumer/status")
#         assert response.status_code == 200
#         assert response.json() == {'is_running': False}
#         # Check if the consumer has stopped
#         # assert not test_consumer_manager.get_status().is_running, "Container not stopped"
