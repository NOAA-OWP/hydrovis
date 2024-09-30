from pathlib import Path
from typing import Any, Dict, Tuple

import networkx as nx
import numpy as np
import pandas as pd
import zarr

from src.rise.utils import hydrofabric


def create_subset(
    file_path: Path, start_node: str, end_node: str
) -> Tuple[
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
]:
    """Creates a subset of the hydrofabric given a file_path and starting/ending catchments

    Parameters:
    -----------
    file_path: Path,
        The path to the VPU file
    start_node: str,
        The starting nexus point
    end_node: str
        The ending nexus point

    """
    flowlines = hydrofabric.get_layer(file_path, layer="flowpaths")
    nexus = hydrofabric.get_layer(file_path, layer="nexus")
    divides = hydrofabric.get_layer(file_path, layer="divides")
    flowpath_attributes = hydrofabric.get_layer(file_path, layer="flowpath_attributes")

    G = hydrofabric.get_hydrofabric_vpu_graph(nexus, flowlines)

    path = nx.shortest_path(G, start_node, end_node)

    mask_flowlines = flowlines["id"].isin(path) | flowlines["toid"].isin(path)
    mask_nexus = nexus["id"].isin(path)
    mask_divides = divides["id"].isin(path)

    _subset_nexus = nexus[mask_nexus]
    _subset_flowlines = flowlines[mask_flowlines]
    _subset_divides = divides[mask_divides]
    return _subset_nexus, _subset_flowlines, _subset_divides, flowpath_attributes


def get_event_data(
    file_path: Path,
    zarr_path: Path,
    _subset_flowlines: pd.DataFrame,
    teehr_params: Dict[str, Any],
) -> zarr.Group:
    """Creates zarr arrays of NWM3.0 retrospective data

    Parameters:
    -----------
    file_path: Path
        The file path to the conus river network parquet file
    zarr_path: Path
        The path to where the zarr data should be created
    _subset_flowlines: pd.DataFrame
        The subset of the hydrofabric of the flowlines layer
    teehr_params: Dict[str, Any]
        Parameters to be input to TEEHR

    Returns:
    --------
    zarr.Group
        The output array data of NWM3.0 flows
    """
    conus_df = pd.read_parquet(file_path)
    _df = conus_df[conus_df["id"].isin(_subset_flowlines["id"].values)]
    _feature_ids = _df[~np.isnan(_df["hf_id"])]
    mapping = {}
    for _hf_id, _id in zip(_feature_ids["hf_id"], _feature_ids["id"]):
        _mapped_features = mapping.get(_id, None)
        if _mapped_features is None:
            mapping[_id] = [_hf_id]
        else:
            mapping[_id].append(_hf_id)

    flow_data = pd.read_parquet(
        teehr_params["OUTPUT_DIR"] / "20190520_20190529.parquet"
    )
    flow_data[["nwm_version", "location_id"]] = flow_data["location_id"].str.split(
        "-", expand=True
    )

    root = zarr.open_group(
        path=(zarr_path / "nwm30_retrospective.zarr").__str__(), mode="w"
    )
    flood_root = root.require_group("coffeyville.zarr")
    flood_root.array(
        name="value_time",
        data=np.array(flow_data["value_time"].unique()),
        dtype="datetime64[ns]",
    )
    for k, v in mapping.items():
        v = np.array([str(int(_v)) for _v in v])
        flow = (
            flow_data[flow_data["location_id"].isin(v)]
            .groupby("value_time")["value"]
            .mean()
            .reset_index()["value"]
            .values
        )
        flood_root.array(
            name=k,
            data=flow,
        )

    return flood_root


def create_data_catalog(data_lib: str) -> None:
    """Creating a hydromt formatted data catalog from HUC6 DEM data

    Parameters:
    -----------
    data_lib: str
        The location of where the data catalog will be written
    """
    root = Path("/app/data/SFINCS/ngwpc_data/")

    yml_str = f"""
    meta:
    root: {root.__str__()}
    
    10m_lidar:
    path: HUC6_110701_dem.tif
    data_type: RasterDataset
    driver: raster
    driver_kwargs:
        chunks:
        x: 6000
        y: 6000
    meta:
        category: topography
        crs: 5070
    rename:
        10m_lidar: elevtn
    """
    data_lib = Path("/app/data/SFINCS/data_catalogs/10m_huc6_lidar.yml")
    if data_lib.exists() is False:
        with open(data_lib, mode="w") as f:
            f.write(yml_str)
