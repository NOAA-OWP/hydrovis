import asyncio
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Tuple


def parse_datetime(date_string: str) -> datetime:
    """A function used for parsing datetime information

    Parameters
    ----------
    data_string: str
    - The date that we are parsing into a datetime

    Returns
    -------
    datetime
    - The string passed in, but in datetime form with it's timezone accounted for
    """
    dt = datetime.fromisoformat(date_string.replace(" UTC", ""))
    return dt.replace(tzinfo=timezone.utc)


def convert_to_m3_per_sec(forecast: List[float], unit: str) -> Tuple[List[float], str]:
    """Convert forecast units to m3/s.

    Parameters
    ----------
    forecast: List[float]
    - The list of forecasts to convert

    unit: str
    - The units of the forecast

    Returns
    -------
    Tuple[List[float], str]:
    - The forecast, and the units str
    """
    if unit == "kcfs":
        forecast = [flow * 1000 * 0.028316846592 for flow in forecast]
        return forecast, "m3 s-1"
    else:
        raise ValueError(f"Unit conversion not supported for {unit}")


class AsyncRateLimiter:
    """
    An asynchronous rate limiter that uses a token bucket algorithm.

    This class allows you to limit the rate of operations in an asynchronous context.
    It's useful for controlling the rate of API calls or other resource-intensive operations.

    Parameters
    ----------
    rate_limit : float
    - The maximum number of operations allowed per time period.

    time_period : float
    - The time period (in seconds) over which the rate limit applies.

    Attributes
    ----------
    rate_limit : float
    - The maximum number of operations allowed per time period.

    time_period : float
    - The time period (in seconds) over which the rate limit applies.

    tokens : float
    - The current number of available tokens.

    last_refill_time : float
    - The last time the token bucket was refilled.

    lock : asyncio.Lock
    - A lock to ensure thread-safe operations.
    """

    def __init__(self, rate_limit: int, time_period: int) -> None:
        self.rate_limit = rate_limit
        self.time_period = time_period
        self.tokens = rate_limit
        self.last_refill_time = time.monotonic()
        self.lock = asyncio.Lock()

    async def acquire(self) -> None:
        """Acquire a token from the bucket"""
        async with self.lock:
            while True:
                current_time = time.monotonic()
                time_passed = current_time - self.last_refill_time
                new_tokens = time_passed * (self.rate_limit / self.time_period)

                if new_tokens > 1:
                    self.tokens = min(self.rate_limit, self.tokens + new_tokens)
                    self.last_refill_time = current_time

                if self.tokens >= 1:
                    self.tokens -= 1
                    return
                else:
                    sleep_time = (1 - self.tokens) / (
                        self.rate_limit / self.time_period
                    )
                    await asyncio.sleep(sleep_time)

    async def __aenter__(self):
        await self.acquire()

    async def __aexit__(self, exc_type, exc, tb):
        pass


def setup_logging(log_level: str) -> logging.Logger:
    """Setting up logging for all errors and debugging

    Parameters
    ----------
    log_level: str
    - The logging level(DEBUG, INFO, etc)

    Returns
    -------
    logging.Logger
    - The logging object
    """
    log_path = Path(__file__).resolve().parents[1] / "logs"
    log_path.mkdir(parents=True, exist_ok=True)

    log_file = log_path / "rise.log"

    logger = logging.getLogger(__name__)
    logger.setLevel(getattr(logging, log_level))

    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(getattr(logging, log_level))

    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, log_level))

    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

    return logger
