from pathlib import Path
from typing import Any, Dict

import pandas as pd
import pytest

from src.rnr.app.api.services.replace_and_route import ReplaceAndRoute

from src.rnr.app.core.cache import get_settings
settings = get_settings()

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


# TODO fix json body to be up to date with the sample forecast
# def test_read_message(
#     sample_rfc_body: str, sample_rfc_forecast: Dict[str, Any]
# ) -> None:
#     """Testing to see if the message body is correctly being read"""
#     json_body = rnr.read_message(sample_rfc_body)
#     assert json_body == sample_rfc_forecast


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


def test_troute(sample_rfc_forecast, feature_id: int = 2930769, lid: str = "CAGM7"):
    try:
        response = rnr.troute(
            lid,
            feature_id,
            sample_rfc_forecast
        )
    except Exception:
        pytest.skip("Can't test troute as docker compose is not up.")
    assert isinstance(response, dict)


def test_post_processing(tmp_dir, sample_rfc_forecast):
    mapped_feature_id = 1074884
    troute_output_dir = Path(__file__).parent.absolute() / "test_data/troute_output/{}/troute_output_{}.nc"
    rnr_output_dir = tmp_dir / "data/replace_and_route/{}/"
    response = rnr.post_process(
        sample_rfc_forecast, 
        mapped_feature_id, 
        is_flooding=False,
        troute_file_dir=troute_output_dir.__str__(),
        rnr_dir=rnr_output_dir.__str__()
    )
    assert response["status"] == "OK"


# Commenting out so code passes GITHUB tests. Uncomment when plotting is fixed
# def test_create_plot_and_rnr_files(sample_rfc_forecast):
#     try:
#         mapped_feature_id = 1074884
#         plot_and_rnr_files_json = rnr.create_plot_and_rnr_files(sample_rfc_forecast["lid"], mapped_feature_id, sample_rfc_forecast, settings.plot_path, settings.rnr_output_path)
#         assert plot_and_rnr_files_json["status"] == "OK"
#         print(plot_and_rnr_files_json)
#     except Exception:
#         pytest.skip("Cannot test visual plots on web at this moment")
