import pytest
import redis
import redis.exceptions

from src.rnr.app.core.settings import Settings

test_settings = Settings()


def test_redis_stack():
    try:
        r = redis.Redis(host=test_settings.redis_url, port=6379, decode_responses=True)
        assert r.set("foo", "bar"), "redis server not working"
        assert r.get("foo") == "bar", "key value pair not working"
    except redis.exceptions.ConnectionError:
        pytest.skip("Cannot test as docker compose is not running")
