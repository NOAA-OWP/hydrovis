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
from src.rnr.app.api.services.plot_data import get_fid_data

settings = get_settings()

r_cache = redis.Redis(host=settings.redis_url, port=6379, decode_responses=True)

import matplotlib.dates as mdates
import matplotlib.pyplot as plt

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
        rfc_data: Dict[str, Dict[str, str]]
            The dictionary of the converted RFC forecast

        lid:
            The location ID of the RFC forecast

        mapped_feature_id
            The mapped feature ID of the RFC forecast

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
	
    def create_plot_and_rnr_files(
            self, 
            lid,
            mapped_feature_id, 
            json_data,
            plot_output_path: Path,
            rnr_output_path: Path,
        ) -> None:
        """Creates the plot and netcdf files to be viewed in the frontend

        Parameters
        ----------
        lid:
            The location ID of the RFC forecast

        mapped_feature_id
            The mapped feature ID of the RFC forecast
        
        json_data
            The JSON data from the RFC forecast

        plot_output_path: Path
            The output directory where the plot files will be generated

        rnr_output_path: Path
            The output directory where the netcdf files will be generated
        """
        
        message_flow = json_data['secondary_forecast']
        message_flow_cfs = [float(flow_value) * 35.3147 for flow_value in message_flow]  # converting to cfs
        message_time_delta = []
        for time in json_data['times']:
            try:
                dt = datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ")
            except:
                dt = datetime.strptime(time, "%Y-%m-%dT%H:%M:%S")
            message_time_delta.append(dt)

        # Retrieve T-Route files for our lid/dates and process the data
        troute_flow, troute_time_delta = get_fid_data(output_dir=Path(os.path.join(settings.troute_output_path, lid)), fid=mapped_feature_id, start_date=message_time_delta[0], end_date=message_time_delta[-1])
        troute_flow_cfs = [float(flow_value) * 35.3147 for flow_value in troute_flow]  # converting to cfs

        plot_file_name = "RFC_plot_output_" + lid + "_"
        rnr_file_name = "RFC_rnr_output_" + lid + "_"
        dt_start_formatted = message_time_delta[0].strftime("%Y%m%d")
        dt_end_formatted = message_time_delta[-1].strftime("%Y%m%d")
        if dt_start_formatted != dt_end_formatted:
            plot_file_name += dt_start_formatted + "_"
            rnr_file_name += dt_start_formatted + "_"
        plot_file_name += dt_end_formatted + ".png"
        rnr_file_name += dt_end_formatted + ".txt"
        plot_file_dir = Path(os.path.join(plot_output_path, lid))
        rnr_file_dir = Path(os.path.join(rnr_output_path, lid))
        plot_file_location = Path(os.path.join(plot_output_path, lid, plot_file_name))
        rnr_file_location = Path(os.path.join(rnr_output_path, lid, rnr_file_name))

        plt.plot(troute_time_delta, troute_flow_cfs, c="k", label="LowerColorado Test NHDPlus")
        plt.plot(message_time_delta, message_flow_cfs, c="tab:blue", label=f"{lid} Routed Flow")
        plt.xlabel("timedelta64[ns]")
        plt.ylabel("discharge cfs")
        plt.legend()

        if not os.path.exists(plot_file_dir):
            os.makedirs(plot_file_dir)
        plt.savefig(plot_file_location)

        if not os.path.exists(rnr_file_dir):
            os.makedirs(rnr_file_dir)
        # Faking netcdf output for now
        rnr_file = open(rnr_file_location, "w")
        rnr_file.write(','.join([str(time) for time in troute_time_delta]) + '\n')
        rnr_file.write(','.join([str(flow) for flow in troute_flow_cfs]) + '\n')
        rnr_file.write(','.join([str(time) for time in message_time_delta]) + '\n')
        rnr_file.write(','.join([str(flow) for flow in message_flow_cfs]) + '\n')
        rnr_file.close()

        return {
            'status': 'OK',
            'plot_file_location': plot_file_location,
            'rnr_file_location': rnr_file_location,
        }
    
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
		
        # Plot data from both messages and T-Route
        plot_file_json = self.create_plot_and_rnr_files(lid, mapped_feature_id, json_data, settings.plot_path,  settings.rnr_output_path)

        if plot_file_json["status"] == "OK":
            print(" [x] Plot file created:")
            print("   - " + plot_file_json['file_location'])
        else:
            print(f"STATUS: {plot_file_json['status']}: {plot_file_json['msg']}")

        # Acknowledge message delivery only when all of the above steps are completed
        await message.ack()
