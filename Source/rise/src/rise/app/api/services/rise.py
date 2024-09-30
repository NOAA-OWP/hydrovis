import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

import geopandas as gpd
import numpy as np
import pandas as pd
from aio_pika.abc import AbstractIncomingMessage
from hydromt_sfincs import SfincsModel, utils
from shapely.ops import unary_union

from src.rise.app.core.logging_module import setup_logger
from src.rise.utils import formatting_sfincs

log = setup_logger("default", "consumer.log")


class RISE:
    def read_message(self, body: str) -> Dict[str, Any]:
        message_str = body.decode()
        json_start = message_str.find("{")
        json_end = message_str.rfind("}")
        json_string = message_str[json_start : json_end + 1].replace("\\", "")
        json_data = json.loads(json_string)
        return json_data

    async def process_request(self, message: AbstractIncomingMessage):
        _ = self.read_message(message.body)
        log.info("Consumed message")

        log.info("Creating Model")
        data_lib = Path.cwd() / "data/SFINCS/data_catalogs/10m_huc6_lidar.yml"
        root_dir = Path.cwd() / "data/SFINCS/ngwpc_data"
        sf = SfincsModel(data_libs=[data_lib], root=root_dir, mode="w+")

        # huc_8 = "11070103"
        start_node = "nex-2175874"
        end_node = "nex-2175887"

        file_path = Path.cwd() / "data/NWM/nextgen_11.gpkg"

        _subset_nexus, _subset_flowlines, _subset_divides, flowpath_attributes = (
            formatting_sfincs.create_subset(file_path, start_node, end_node)
        )

        log.info("Setting up Model Grid")

        merged_polygon = unary_union(_subset_divides["geometry"])
        merged_gdf = gpd.GeoDataFrame(
            geometry=[merged_polygon], crs=_subset_divides.crs
        )
        output_divides = Path.cwd() / "data/NWM/flowlines_divides.geojson"
        merged_gdf.to_file(output_divides, driver="GeoJSON")

        sf.setup_grid_from_region(
            region={
                "geom": (Path.cwd() / "data/NWM/flowlines_divides.geojson").__str__()
            },
            res=50,
            rotated=True,
            crs=_subset_divides.crs,  # NAD83 / Conus Albers HARDCODED TODO figure out making this cleaner
        )

        log.info("Setting up Elevation")

        datasets_dep = [{"elevtn": "10m_lidar", "zmin": 0.001}]
        _ = sf.setup_dep(datasets_dep=datasets_dep)

        # outflow_polygon = _subset_divides[_subset_divides["id"] == "wb-2175886"]
        _outflow_nexus = _subset_nexus[_subset_nexus["id"] == "nex-2175887"]

        sf.setup_mask_active(include_mask=merged_gdf, reset_mask=True)
        sf.setup_mask_bounds(
            btype="waterlevel", include_mask=_outflow_nexus, reset_bounds=True
        )

        sf.setup_river_inflow(rivers=_subset_flowlines, keep_rivers_geom=True)

        file_path = Path.cwd() / "data/NWM/conus_net.parquet"

        zarr_path = Path.cwd() / "data/NWM/"

        teehr_params = {
            "NWM_VERSION": "nwm30",
            "VARIABLE_NAME": "streamflow",
            "START_DATE": datetime(2019, 5, 20),
            "END_DATE": datetime(2019, 5, 29),
            "OUTPUT_DIR": Path.cwd() / "data/NWM/nwm30_retrospective",
        }

        log.info("Reading source inflow")
        flood_root = formatting_sfincs.get_event_data(
            file_path, zarr_path, _subset_flowlines, teehr_params
        )

        sf.setup_config(
            **{
                "tref": "20190520 000000",
                "tstart": "20190520 000000",
                "tstop": "20190527 000000",
            }
        )
        source_points = ["wb-2175873", "wb-2176992"]
        time = pd.date_range(
            start=utils.parse_datetime(sf.config["tstart"]),
            end=utils.parse_datetime(sf.config["tstop"]),
            periods=9,
        )
        dis = []
        for point in source_points:
            dis.append(flood_root[point][::24][:-1])
        dis = np.array(dis).T

        index = sf.forcing["dis"].index
        dispd = pd.DataFrame(index=time, columns=index, data=dis)
        sf.setup_discharge_forcing(timeseries=dispd)

        sf.setup_structures(
            structures=(Path.cwd() / "data/NWM/nld_subset_levees.geojson").__str__(),
            stype="weir",
            dz=None,
        )

        log.info("Writing SFINCS model config")
        sf.write()
        log.info("Finished SFINCS model config")

    async def process_error(self, message: AbstractIncomingMessage):
        log.error("ERROR QUEUE TRIGGERED")
