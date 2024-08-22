"""Functions that require lru_cache"""
from functools import lru_cache

from src.rnr.app.consumer_manager import ConsumerManager


@lru_cache
def get_consumer_manager():
    return ConsumerManager()