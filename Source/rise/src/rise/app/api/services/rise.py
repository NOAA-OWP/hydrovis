import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable, Dict

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import redis
import xarray as xr
from aio_pika.abc import AbstractIncomingMessage
from hydromt_sfincs import SfincsModel, utils

from src.rise.app.core.cache import get_settings
from src.rise.app.core.logging_module import setup_logger

settings = get_settings()

r_cache = redis.Redis(host=settings.redis_url, port=6379, decode_responses=True)

log = setup_logger("default", "consumer.log")


class RISE:
    def read_message(self, body: str) -> Dict[str, Any]:
        message_str = body.decode()
        json_start = message_str.find("{")
        json_end = message_str.rfind("}")
        json_string = message_str[json_start : json_end + 1].replace("\\", "")
        json_data = json.loads(json_string)
        return json_data

    def run_sfincs(self, lid: str):
        sf = SfincsModel(
            data_libs=["artifact_data"], root="tmp_sfincs_compound", mode="w+"
        )
        sf.setup_grid(
            x0=318650,
            y0=5040000,
            dx=50.0,
            dy=50.0,
            nmax=107,
            mmax=250,
            rotation=27,
            epsg=32633,
        )

    async def process_request(self, message: AbstractIncomingMessage):
        json_data = self.read_message(message.body)
        lid = json_data["lid"]
        self.run_sfincs(lid)
        log.info(f"Consumed message for {lid}")

    async def process_error(self, message: AbstractIncomingMessage):
        log.error("ERROR QUEUE TRIGGERED")
