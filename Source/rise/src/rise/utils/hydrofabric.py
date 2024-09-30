"""A file to contain all hydrofabric related functions"""

from pathlib import Path

import geopandas as gpd
import networkx as nx
from pyogrio.errors import DataLayerError


def get_hydrofabric_vpu_graph(
    nexus: gpd.GeoDataFrame, flowlines: gpd.GeoDataFrame
) -> nx.DiGraph:
    """Creates a networkx graph object to

    Parameters:
    -----------
    nexus: gpd.GeoDataFrame
        Node points within the v20.1 hydrofabric
    flowlines: gpd.GeoDataFrame
        Edges within the v20.1 hydrofabric

    Returns:
    --------
    nx.DiGraph
        The networkx directed graph
    """
    G = nx.DiGraph()
    nexus_to_toid = dict(zip(nexus["id"], nexus["toid"]))
    for _, node in nexus.iterrows():
        G.add_node(
            node["id"], type=node["type"], geometry=node["geometry"], toid=node["toid"]
        )

    for _, edge in flowlines.iterrows():
        G.add_edge(
            edge["id"],
            edge["toid"],
            mainstem=edge["mainstem"],
            order=edge["order"],
            hydroseq=edge["hydroseq"],
            lengthkm=edge["lengthkm"],
            areasqkm=edge["areasqkm"],
            tot_drainage_areasqkm=edge["tot_drainage_areasqkm"],
            has_divide=edge["has_divide"],
            divide_id=edge["divide_id"],
            geometry=edge["geometry"],
        )

        if edge["toid"] in nexus_to_toid:
            G.add_edge(edge["toid"], nexus_to_toid[edge["toid"]])
    return G


def get_layer(file_path: Path, layer: str) -> gpd.GeoDataFrame:
    """Gets a specific layer from v20.1 of the enterprise hydrofabric

    Parameters
    ----------
    file_path : Path
        The file path to the v20.1 enterprise hydrofabric
    layer: str
        The layer we want to extract from the file

    Returns
    -------
    gpd.GeoDataFrame
        The layer from the v20.1 enterprise hydrofabric

    Raises
    ------
    DataLayerError
        The layer does not exist within the gpkg
    FileNotFoundError
        The file does not exist
    """
    if file_path.exists():
        try:
            _gdf = gpd.read_file(file_path, layer=layer)
            return _gdf
        except DataLayerError:
            raise DataLayerError(f"Layer {layer} does not exist in file {file_path}")
    else:
        raise FileNotFoundError(f"File {file_path} does not exist")
