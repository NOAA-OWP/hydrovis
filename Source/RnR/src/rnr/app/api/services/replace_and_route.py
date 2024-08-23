import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict

import geopandas as gpd
import numpy as np
import pandas as pd
import redis
from aio_pika.abc import AbstractIncomingMessage
import xarray as xr

from src.rnr.app.core.cache import get_settings
from src.rnr.app.api.client.troute import run_troute
from src.rnr.app.core.exceptions import ManyToOneError

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
    

    def troute(self, lid: str, feature_id: str, json_data: Dict[str, Any]):
        unique_dates = set()
        for time_str in json_data["times"]:
            date = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S")
            unique_dates.add(date.date())

        num_forecast_days = len(unique_dates) - 1 # the set ending is inclusive, we want exclusive

        response = run_troute(
            lid=lid,
            feature_id=feature_id,
            start_time=json_data["times"][0],
            num_forecast_days=num_forecast_days,
            base_url=settings.base_troute_url
        )
        return response
	
    
    def create_plot_file(
            self, 
            json_data: Dict[str, Any], 
            mapped_feature_id: int, 
            troute_file_dir: str = settings.troute_output_format, 
            plot_dir: str = settings.plot_path
        ):
        
        try:
            t0 = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%SZ")
            t_n = datetime.strptime(json_data["times"][-1], "%Y-%m-%dT%H:%M:%SZ")
            json_data["formatted_times"] = [datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ") for time in json_data["times"]]

        except Exception:
            t0 = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%S")
            t_n = datetime.strptime(json_data["times"][-1], "%Y-%m-%dT%H:%M:%S")
            json_data["formatted_times"] = [datetime.strptime(time, "%Y-%m-%dT%H:%M:%S") for time in json_data["times"]]

        message_time_delta = json_data["formatted_times"]
        message_flow_cfs = [float(flow_value) * 35.3147 for flow_value in json_data['secondary_forecast']]  # converting to cfs

        formatted_timestamps = []
        t = t0
        while t <= t_n:
            formatted_timestamp = t.strftime("%Y%m%d%H%M")
            formatted_timestamps.append(formatted_timestamp)
            t += timedelta(hours=1)
        
        troute_flow = []
        troute_time_delta = []
        dataset_names = [troute_file_dir.format(json_data["lid"], timestamp) for timestamp in formatted_timestamps]
        for idx, file_name in enumerate(dataset_names):
            ds = xr.open_dataset(file_name, engine="netcdf4").copy(deep=True)
            troute_flow.append(ds.sel(feature_id=mapped_feature_id).flow.values[0])
            troute_time_delta.append(datetime.strptime(Path(file_name).stem.split("_")[-1], "%Y%m%d%H%M"))

        troute_flow_cfs = [float(flow_value) * 35.3147 for flow_value in troute_flow]  # converting to cfs

        plot_file_name = "RFC_plot_output_" + json_data["lid"] + "_"
        dt_start_formatted = message_time_delta[0].strftime("%Y%m%d")
        dt_end_formatted = message_time_delta[-1].strftime("%Y%m%d")
        if dt_start_formatted != dt_end_formatted:
            plot_file_name += dt_start_formatted + "_"
        plot_file_name += dt_end_formatted + ".png"
        plot_file_dir = Path(os.path.join(plot_dir, json_data["lid"]))
        plot_file_location = Path(os.path.join(plot_dir, json_data["lid"], plot_file_name))

        plt.plot(troute_time_delta, troute_flow_cfs, c="k", label="LowerColorado Test NHDPlus")
        plt.plot(message_time_delta, message_flow_cfs, c="tab:blue", label=f"{json_data['lid']} Routed Flow")
        plt.xlabel("timedelta64[ns]")
        plt.ylabel("discharge cfs")
        plt.legend()

        if not os.path.exists(plot_file_dir):
            os.makedirs(plot_file_dir)
        plt.savefig(plot_file_location)

        return {
            'status': 'OK',
            'plot_file_location': plot_file_location
        }
    
    def post_process(
            self, 
            json_data: Dict[str, Any], 
            mapped_feature_id: int, 
            is_flooding: bool,
            troute_file_dir: str = settings.troute_output_format, 
            rnr_dir: str = settings.rnr_output_path
        ):
        
        rnr_output_path = Path(rnr_dir.format(json_data["lid"]))
        if not os.path.exists(rnr_output_path):
            os.makedirs(rnr_output_path)
        
        try:
            t0 = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%SZ")
            t_n = datetime.strptime(json_data["times"][-1], "%Y-%m-%dT%H:%M:%SZ")
            json_data["formatted_times"] = [datetime.strptime(time, "%Y-%m-%dT%H:%M:%SZ") for time in json_data["times"]]

        except Exception:
            t0 = datetime.strptime(json_data["times"][0], "%Y-%m-%dT%H:%M:%S")
            t_n = datetime.strptime(json_data["times"][-1], "%Y-%m-%dT%H:%M:%S")
            json_data["formatted_times"] = [datetime.strptime(time, "%Y-%m-%dT%H:%M:%S") for time in json_data["times"]]

        formatted_timestamps = []
        json_data["formatted_times"] = []
        t = t0
        while t <= t_n:
            formatted_timestamp = t.strftime("%Y%m%d%H%M")
            formatted_timestamps.append(formatted_timestamp)
            t += timedelta(hours=1)
        
        dataset_names = [troute_file_dir.format(json_data["lid"], formatted_timestamp) for formatted_timestamp in formatted_timestamps]
        stage_idx = 0
        for idx, file_name in enumerate(dataset_names):
            ds = xr.open_dataset(file_name, engine="netcdf4").copy(deep=True)
            formatted_timestamp = formatted_timestamps[idx]
            if formatted_timestamp in json_data["formatted_times"]:
                primary_forecast_values = np.zeros_like(ds.depth.values)
                mask = ds.feature_id.values == mapped_feature_id
                primary_forecast_values[:, 0][mask] = json_data["primary_forecast"][stage_idx]
                x = xr.Dataset(
                    {
                        json_data["primary_name"]: (("feature_id", "time"), primary_forecast_values),
                    },
                    coords={"feature_id": ds.feature_id.values, "time": ds.time.values},
                )
                ds = ds.merge(x)
                ds = ds[json_data["primary_name"]].assign_attrs(units=json_data["primary_unit"])
                stage_idx = stage_idx + 1
            assimilated_point = "True" if is_flooding else "False"
            ds = ds.assign_attrs(assimilated_rfc_point=assimilated_point)
            ds = ds.assign_attrs(observed_flood_status=json_data["status"]["observed"]["floodCategory"])
            ds = ds.assign_attrs(forecasted_flood_status=json_data["status"]["forecast"]["floodCategory"])
            ds = ds.assign_attrs(RFC_location_id=json_data["lid"])
            ds = ds.assign_attrs(upstream_RFC_location_id=json_data["upstream_lid"])
            ds = ds.assign_attrs(downstream_RFC_location_id=json_data["downstream_lid"])
            ds = ds.assign_attrs(RFC=json_data["rfc"]["abbreviation"])
            ds = ds.assign_attrs(WFO=json_data["wfo"]["abbreviation"])
            ds = ds.assign_attrs(USGS=json_data["usgs_id"])
            ds = ds.assign_attrs(county=json_data["county"])
            ds = ds.assign_attrs(state=json_data["state"]["abbreviation"])
            ds = ds.assign_attrs(Latitude=json_data["latitude"])
            ds = ds.assign_attrs(Longitude=json_data["longitude"])
            ds = ds.assign_attrs(Last_Forecast_Time=json_data["times"][stage_idx])
            ds.to_netcdf(rnr_output_path / settings.rnr_output_file.format(str(formatted_timestamp)))
        return {"status": "OK"}
    
    async def process_flood_request(self, message: AbstractIncomingMessage):
        await self.process_request(message, is_flooding=True)
    
    async def process_request(self, message: AbstractIncomingMessage, is_flooding = False):
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
		
        troute_response = self.troute(lid, feature_id, json_data)

        plot_file_json = self.create_plot_file(json_data, mapped_feature_id)
    
        self.post_process(json_data, mapped_feature_id, is_flooding)

        if plot_file_json["status"] == "OK":
            print(" [x] Plot file created:")
            print("   - " + plot_file_json['file_location'])

        await message.ack()
