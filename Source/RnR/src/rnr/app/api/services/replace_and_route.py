import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

import geopandas as gpd
import numpy as np
import pandas as pd
import redis
from aio_pika.abc import AbstractIncomingMessage

from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.exceptions import ManyToOneError

settings = get_settings()

r_cache = redis.Redis(host=settings.redis_url, port=6379, decode_responses=True)


class ReplaceAndRoute:
    """
    This is the service for your T-Route data formatting
    """

    def read_message(self, body: str) -> Dict[str, Any]:
        message_str = body.decode()
        json_start = message_str.find("{")
        json_end = message_str.rfind("}")
        json_string = message_str[json_start : json_end + 1].replace("\\", "")
        json_data = json.loads(json_string)
        return json_data

    def create_troute_domains(self, mapped_feature_id, json_data, output_forcing_path):
        rfc_data = {}

        lid = json_data["lid"]
        if mapped_feature_id is None:
            print(f"Skipping {lid} as there is no defined feature_id")
            domain_files_json = {
                "status": "ERROR",
                "domain_files": [],
                "msg": f"No defined feature_id for {lid}",
            }
        else:
            rfc_data[lid] = {
                "times": json_data["times"],
                "secondary_forecast": json_data["secondary_forecast"],
            }
            domain_files_json = self.write_domain_files(
                rfc_data, lid, mapped_feature_id, output_forcing_path
            )

        return domain_files_json

    def write_domain_files(
        self,
        rfc_data: Dict[str, Dict[str, str]],
        lid,
        mapped_feature_id,
        output_path: Path,
    ) -> None:
        """Creates the domain files for t-route to run

        Parameters
        ----------
        mapping: Dict[str, str]
            The dictionary to map RFC feature ids to new hydrofabric

        rfc_data: Dict[str, Dict[str, str]]
            The dictionary of the converted RFC forecast

        rfc_locations: List[Tuple[str, str]]
            The DB query containing all RFC locations and features IDs

        output_path: Path
            The output directory where the domain files will be generated
        """

        output_path_full = Path(output_path)
        output_path_full.mkdir(parents=True, exist_ok=True)

        times = rfc_data[lid]["times"]
        filtered_data = np.array(rfc_data[lid]["secondary_forecast"])
        domain_files = []
        for idx, time in enumerate(times):
            try:
                dt = datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ")
            except Exception:
                dt = datetime.strptime(time, "%Y-%m-%dT%H:%M:%S")
            formatted_time = dt.strftime("%Y%m%d%H%M")
            _df = pd.DataFrame(
                {
                    "feature_id": [mapped_feature_id],
                    formatted_time: [filtered_data[idx]],
                }
            )
            if not os.path.exists(os.path.join(output_path, lid)):
                os.makedirs(os.path.normpath(os.path.join(output_path, lid)))
            file_path = os.path.normpath(
                os.path.join(output_path, lid, formatted_time + ".CHRTOUT_DOMAIN1.csv")
            )
            _df.to_csv(file_path, index=False)
            domain_files.append(
                {
                    "lid": lid,
                    "formatted_time": formatted_time,
                    "file_location": file_path,
                    "secondary_forecast": filtered_data[idx],
                }
            )
        return {"status": "OK", "domain_files": domain_files}

    async def process_request(self, message: AbstractIncomingMessage):
        json_data = self.read_message(message.body)
        lid = json_data["lid"]
        feature_id = json_data["feature_id"]
        output_forcing_path = settings.csv_forcing_path
        gpkg_file = Path(settings.domain_path.format(feature_id))
        mapped_feature_id = self.map_feature_id(feature_id, lid, r_cache, gpkg_file)
        domain_files_json = self.create_troute_domains(
            mapped_feature_id, json_data, output_forcing_path
        )

        if domain_files_json["status"] == "OK":
            try:
                dt = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%SZ")
            except Exception:
                dt = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%S")
            formatted_time = dt.strftime("%Y%m%d%H%M")
            cache_key = json_data["lid"] + "_" + formatted_time
            cache_value = hash(json.dumps(json_data["secondary_forecast"]))
            r_cache.set(cache_key, cache_value)
            print(" [x] Done. Files created:")
            for file in domain_files_json["domain_files"]:
                print("   - " + file["file_location"])
        else:
            print(f"STATUS: {domain_files_json['status']}: {domain_files_json['msg']}")

        await message.ack()

    def map_feature_id(self, feature_id: str, lid: str, _r_cache, gpkg_file) -> str:
        if gpkg_file.exists():
            cache_key = f"{lid}_mapped_feature_id"
            if not _r_cache.exists(cache_key):
                gdf = gpd.read_file(gpkg_file, layer="network")
                _divide_ids = gdf[gdf["hf_id"] == int(feature_id)]["divide_id"].values
                if np.all(_divide_ids == _divide_ids[0]):
                    mapped_feature_id = _divide_ids[0][
                        4:
                    ]  # removing the cat- from in front of the ID
                else:
                    raise ManyToOneError
                cache_value = mapped_feature_id
                _r_cache.set(cache_key, cache_value)
            else:
                mapped_feature_id = _r_cache.get(cache_key)
        else:
            raise FileNotFoundError
        return mapped_feature_id
