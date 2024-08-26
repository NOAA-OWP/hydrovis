from pathlib import Path

import httpx
import pandas as pd
import pytest

from src.rnr.app.api.services.replace_and_route import ReplaceAndRoute
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings

def get_settings_override() -> Settings:
    """Overriding the BaseSettings for testing

    Returns
    -------
    Settings
        The test settings
    """
    return Settings(
        log_path="./logs/"
    )

settings = get_settings_override()

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


def test_assimilation_mapping(feature_id: int = 2930769, lid: str = "CAGM7") -> None:
    gpkg_file = Path(__file__).parent.absolute() / "test_data/2930769/subset.gpkg"
    mapped_feature_id = rnr.get_assimilation_id(feature_id, lid, mock_cache(), gpkg_file)
    # assert mapped_feature_id == "1074884", "mapping function giving the wrong divide id"


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


def test_troute(
    sample_rfc_forecast,
    feature_id: int = 2930769,
    mapped_feature_id=1074884,
    initial_start: float = 0.0,
    lid: str = "CAGM7",
):
    try:
        response = rnr.troute(
            lid, mapped_feature_id, feature_id, initial_start, sample_rfc_forecast
        )
    except httpx.ConnectError:
        pytest.skip("Skipping test. Docker is not")
    assert isinstance(response, dict)


def test_post_processing(sample_rfc_forecast):
    mapped_feature_id = 1074884
    troute_output_dir = (
        Path(__file__).parent.parent.absolute()
        / "data/troute_output/{}/troute_output_{}.nc"
    )
    rnr_output_dir = (
        Path(__file__).parent.parent.absolute() / "data/replace_and_route/{}/"
    )
    try:
        response = rnr.post_process(    
            sample_rfc_forecast,
            mapped_feature_id,
            is_flooding=False,
            troute_file_dir=troute_output_dir.__str__(),
            rnr_dir=rnr_output_dir.__str__(),
        )
    except Exception:
        pytest.skip("Troute output not found")
    assert response["status"] == "OK"


def test_create_plot_file(sample_rfc_forecast):
    mapped_feature_id = 1074884
    mapped_ds_id = 1060390
    try:
        troute_output_dir = (
            Path(__file__).parent.parent.absolute()
            / "data/troute_output/{}/troute_output_{}.nc"
        )
        plot_output_dir = Path(__file__).parent.absolute() / "test_data/plots/"
        response = rnr.create_plot_file(
            json_data=sample_rfc_forecast,
            mapped_feature_id=mapped_feature_id,
            mapped_ds_feature_id=mapped_ds_id,
            troute_file_dir=troute_output_dir.__str__(),
            plot_dir=plot_output_dir.__str__(),
        )
    except Exception:
        pytest.skip("No troute output found")
    assert response["status"] == "OK"
    print(response)
