from pathlib import Path
from typing import Any, Dict

import pandas as pd

from src.rnr.app.api.services.replace_and_route import ReplaceAndRoute

rnr = ReplaceAndRoute()


class mock_cache:
    """a class to mock a redis cache"""

    def __init__(self):
        self.data = {}

    def set(self, key, value) -> None:
        self.data[key] = value

    def get(self, key) -> str:
        return self.data[key]

    def exists(self, key) -> bool:
        return key in self.data.keys()


def test_read_message(
    sample_rfc_body: str, sample_rfc_forecast: Dict[str, Any]
) -> None:
    """Testing to see if the message body is correctly being read"""
    json_body = rnr.read_message(sample_rfc_body)
    assert json_body == sample_rfc_forecast


def test_mapped_feature_id(feature_id: int = 2930769, lid: str = "CAGM7") -> None:
    gpkg_file = Path(__file__).parent.absolute() / "test_data/2930769/subset.gpkg"
    mapped_feature_id = rnr.map_feature_id(feature_id, lid, mock_cache(), gpkg_file)
    assert mapped_feature_id == "1074884", "mapping function giving the wrong divide id"


def test_create_troute_domains(tmp_path, sample_rfc_forecast):
    mapped_feature_id = 1074884
    output_forcing_path = tmp_path / "rfc_channel_forcings/"
    domain_files_json = rnr.create_troute_domains(
        mapped_feature_id, sample_rfc_forecast, output_forcing_path
    )
    assert domain_files_json["status"] == "OK"
    domain_file = domain_files_json["domain_files"][0]
    dt = domain_file["formatted_time"]
    df = pd.read_csv(domain_file["file_location"])
    assert (
        df["feature_id"].values[0] == mapped_feature_id
    ), "mapped feature_id is not correctly defined"
    assert (
        df[dt].values[0] == domain_file["secondary_forecast"]
    ), "secondary forecast not correctly written"
    assert dt == "202408211800", "datetime incorrect"
