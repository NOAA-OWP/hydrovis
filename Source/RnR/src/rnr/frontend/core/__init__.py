from functools import lru_cache

from src.rnr.frontend.core.settings import Settings


@lru_cache
def get_settings() -> Settings:
    """Instantiating the Settings object using LRU caching

    Returns
    -------
    Settings
        The Settings config object
    """
    return Settings()
