from datetime import datetime
from typing import Dict, List, Tuple, Union

import pytest

from src.rnr.app.schemas import RFC, WFO, ProcessedData, Status, StatusData


@pytest.fixture
def gauge_data() -> Dict[str, Union[float, str]]:
    """Reading a single gage from New Jersey

    Returns
    -------
    Dict[str, Union[float, str]]
        The parameters with bounding box data
    """
    params = {
        "bbox.xmin": -74.68816690895136,
        "bbox.ymin": 40.56164600908951,
        "bbox.xmax": -74.67016709104864,
        "bbox.ymax": 40.57946599091049,
    }
    return params


@pytest.fixture
def reach_id() -> str:
    """Reading the sample reach

    Returns
    -------
    str
        The sample reach
    """
    return "23021904"


@pytest.fixture
def identifier() -> str:
    """Reading the sample identifier

    Returns
    -------
    str
        The sample LID
    """
    return "ANAW1"


@pytest.fixture
def product() -> str:
    """Reading the sample NWPS product

    Returns
    -------
    str
        The sample NWPS product
    """
    return "forecast"


@pytest.fixture
def pedts() -> str:
    """Reading the sample pedts

    Returns
    -------
    str
        The sample pedts
    """
    return "HGIRG"


@pytest.fixture
def kcfs_data() -> List[float]:
    """Reading sample kfcs data

    Returns
    -------
    List[float]
        The sample kfcs data
    """
    return [20.0, 40.0, 60.0]


@pytest.fixture
def routelink_cols() -> List[Tuple[str, str]]:
    """Returning what the nwm mock db has for the routelink

    Returns
    -------
    List[Tuple[str, str]]
        The Columns and datatypes for the routelink
    """
    return [
        ("link", "integer"),
        ("from", "integer"),
        ("lon", "real"),
        ("lat", "real"),
        ("alt", "real"),
        ("order", "integer"),
        ("Qi", "real"),
        ("MusK", "real"),
        ("MusX", "real"),
        ("Length", "real"),
        ("n", "real"),
        ("So", "real"),
        ("ChSlp", "real"),
        ("BtmWdth", "real"),
        ("NHDWaterbodyComID", "integer"),
        ("time", "timestamp without time zone"),
        ("gages", "text"),
        ("Kchan", "smallint"),
        ("ascendingIndex", "integer"),
        ("nCC", "real"),
        ("TopWdthCC", "real"),
        ("TopWdth", "real"),
        ("order_index", "integer"),
        ("to", "integer"),
    ]


@pytest.fixture
def timestamp() -> str:
    """A timestamp with a UTC time code attached

    Returns
    -------
    str
        A sample timestamp
    """
    return "2024-06-12 01:50:00 UTC"


@pytest.fixture
def processed_data() -> ProcessedData:
    """A timestamp with a UTC time code attached

    Returns
    -------
    str
        Sample ProcessedData
    """
    return ProcessedData(
        lid="MOCK1",
        usgs_id="12345678",
        feature_id=98765,
        reach_id="MOCKREACH1",
        name="Mock Gauge",
        rfc=RFC(abbreviation="MOCK", name="Mock River Forecast Center"),
        wfo=WFO(abbreviation="MWFO", name="Mock Weather Forecast Office"),
        county="Mock County",
        timeZone="America/New_York",
        latitude=40.7128,
        longitude=-74.0060,
        status=Status(
            observed=StatusData(
                primary=10.5,
                primaryUnit="ft",
                secondary=1000,
                secondaryUnit="cfs",
                floodCategory="Normal",
                validTime=datetime(2023, 7, 1, 12, 0, 0),
            ),
            forecast=StatusData(
                primary=11.0,
                primaryUnit="ft",
                secondary=1100,
                secondaryUnit="cfs",
                floodCategory="Normal",
                validTime=datetime(2023, 7, 1, 13, 0, 0),
            ),
        ),
        times=[
            datetime(2023, 7, 1, 12, 0),
            datetime(2023, 7, 1, 13, 0),
            datetime(2023, 7, 1, 14, 0),
            datetime(2023, 7, 1, 15, 0),
            datetime(2023, 7, 1, 16, 0),
        ],
        primary_name="stage",
        primary_forecast=[10.5 + i * 0.1 for i in range(5)],
        primary_unit="ft",
        secondary_name="flow",
        secondary_forecast=[1000 + i * 50 for i in range(5)],
        secondary_unit="cfs",
    )


@pytest.fixture
def test_queue() -> str:
    """Returning the name of the test queue for rabbit mq

    Returns
    -------
    str:
        The testing queue name
    """
    return "testing"


@pytest.fixture
def rfc_table_identifier() -> str:
    """Using a str that is within the mock db

    Returns
    -------
    str:
        A str nws_lid within the mock db
    """
    return "AEXL1"


@pytest.fixture
def no_rfc_forecast_identifier() -> str:
    """Using a str that is within the mock db that does NOT have a forecast

    Returns
    -------
    str:
        A str nws_lid within the mock db
    """
    return "LONT2"


@pytest.fixture
def no_gauge_identifier() -> str:
    """Using a str that is within the mock db that does NOT exist in the API as a gauge

    Returns
    -------
    str:
        A str nws_lid within the mock db
    """
    return "TMFT1"


@pytest.fixture
def sample_rfc_forecast() -> Dict[str, str]:
    """A sample RFC forecast

    Returns
    -------
    Dict[str, str]:
      the sample RFC forecast
    """
    return {
        "times": [
            "2024-08-27T18:00:00",
            "2024-08-28T00:00:00",
            "2024-08-28T06:00:00",
            "2024-08-28T12:00:00",
            "2024-08-28T18:00:00",
            "2024-08-29T00:00:00",
            "2024-08-29T06:00:00",
            "2024-08-29T12:00:00",
            "2024-08-29T18:00:00",
            "2024-08-30T00:00:00",
            "2024-08-30T06:00:00",
            "2024-08-30T12:00:00",
            "2024-08-30T18:00:00",
            "2024-08-31T00:00:00",
            "2024-08-31T06:00:00",
            "2024-08-31T12:00:00",
            "2024-08-31T18:00:00",
            "2024-09-01T00:00:00",
            "2024-09-01T06:00:00",
            "2024-09-01T12:00:00",
            "2024-09-01T18:00:00",
            "2024-09-02T00:00:00",
            "2024-09-02T06:00:00",
            "2024-09-02T12:00:00",
            "2024-09-02T18:00:00",
            "2024-09-03T00:00:00",
            "2024-09-03T06:00:00",
            "2024-09-03T12:00:00",
            "2024-09-03T18:00:00",
            "2024-09-04T00:00:00",
            "2024-09-04T06:00:00",
            "2024-09-04T12:00:00",
            "2024-09-04T18:00:00",
            "2024-09-05T00:00:00",
            "2024-09-05T06:00:00",
            "2024-09-05T12:00:00",
            "2024-09-05T18:00:00",
            "2024-09-06T00:00:00",
            "2024-09-06T06:00:00",
            "2024-09-06T12:00:00",
            "2024-09-06T18:00:00",
            "2024-09-07T00:00:00",
            "2024-09-07T06:00:00",
            "2024-09-07T12:00:00",
            "2024-09-07T18:00:00",
            "2024-09-08T00:00:00",
            "2024-09-08T06:00:00",
            "2024-09-08T12:00:00",
            "2024-09-08T18:00:00",
            "2024-09-09T00:00:00",
            "2024-09-09T06:00:00",
            "2024-09-09T12:00:00",
            "2024-09-09T18:00:00",
            "2024-09-10T00:00:00",
            "2024-09-10T06:00:00",
            "2024-09-10T12:00:00",
        ],
        "primary_name": "Tailwater",
        "primary_forecast": [
            16.2,
            16.3,
            16.3,
            16.3,
            16.3,
            16.2,
            16.2,
            16.1,
            16.1,
            16.0,
            16.0,
            16.0,
            15.9,
            15.8,
            15.7,
            15.7,
            15.6,
            15.5,
            15.5,
            15.4,
            15.4,
            15.3,
            15.3,
            15.3,
            15.2,
            15.2,
            15.2,
            15.2,
            15.1,
            15.1,
            15.1,
            15.1,
            15.1,
            15.1,
            15.1,
            15.1,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            15.0,
            14.9,
            14.9,
            14.9,
            14.9,
            14.9,
            14.9,
        ],
        "primary_unit": "ft",
        "secondary_name": "Flow",
        "secondary_forecast": [
            2021.8228466688001,
            2055.8030625792,
            2055.8030625792,
            2055.8030625792,
            2055.8030625792,
            2021.8228466688001,
            2021.8228466688001,
            1987.8426307584,
            1987.8426307584,
            1953.862414848,
            1953.862414848,
            1953.862414848,
            1919.8821989376002,
            1885.9019830272,
            1851.9217671168003,
            1851.9217671168003,
            1817.9415512064002,
            1783.961335296,
            1783.961335296,
            1752.8128040448,
            1752.8128040448,
            1721.6642727936,
            1721.6642727936,
            1721.6642727936,
            1690.5157415424,
            1690.5157415424,
            1690.5157415424,
            1690.5157415424,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1659.3672102912,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1628.21867904,
            1591.4067784704,
            1591.4067784704,
            1591.4067784704,
            1591.4067784704,
            1591.4067784704,
            1591.4067784704,
        ],
        "secondary_unit": "m3 s-1",
        "status": {
            "observed": {
                "primary": 16.19,
                "primaryUnit": "ft",
                "secondary": 71.2,
                "secondaryUnit": "kcfs",
                "floodCategory": "no_flooding",
                "validTime": "2024-08-27T15:00:00Z",
            },
            "forecast": {
                "primary": 16.3,
                "primaryUnit": "ft",
                "secondary": 72.6,
                "secondaryUnit": "kcfs",
                "floodCategory": "no_flooding",
                "validTime": "2024-08-28T00:00:00Z",
            },
        },
        "lid": "CAGM7",
        "upstream_lid": "MOZI2",
        "downstream_lid": "GRFI2",
        "usgs_id": "05513675",
        "feature_id": 2930769,
        "downstream_feature_id": 880478,
        "latest_observation": [2016.1594773504],
        "latest_obs_units": "m3 s-1",
        "reach_id": "2930769",
        "name": "Mississippi River at Winfield Lock and Dam 25",
        "rfc": {"abbreviation": "NCRFC", "name": "North Central River Forecast Center"},
        "wfo": {"abbreviation": "LSX", "name": "St. Charles"},
        "state": {"abbreviation": "MO", "name": "Missouri"},
        "county": "Lincoln",
        "timeZone": "CST6CDT",
        "latitude": 39.000833333333,
        "longitude": -90.6875,
    }


# @pytest.fixture
# def sample_rfc_str() -> str:
#     """A sample message str

#     Returns
#     -------
#     str:
#       the sample RFC str
#     """
#     return '{"times":["2024-08-21T18:00:00","2024-08-22T00:00:00","2024-08-22T06:00:00","2024-08-22T12:00:00","2024-08-22T18:00:00","2024-08-23T00:00:00","2024-08-23T06:00:00","2024-08-23T12:00:00","2024-08-23T18:00:00","2024-08-24T00:00:00","2024-08-24T06:00:00","2024-08-24T12:00:00","2024-08-24T18:00:00","2024-08-25T00:00:00","2024-08-25T06:00:00","2024-08-25T12:00:00","2024-08-25T18:00:00","2024-08-26T00:00:00","2024-08-26T06:00:00","2024-08-26T12:00:00","2024-08-26T18:00:00","2024-08-27T00:00:00","2024-08-27T06:00:00","2024-08-27T12:00:00","2024-08-27T18:00:00","2024-08-28T00:00:00","2024-08-28T06:00:00","2024-08-28T12:00:00","2024-08-28T18:00:00","2024-08-29T00:00:00","2024-08-29T06:00:00","2024-08-29T12:00:00","2024-08-29T18:00:00","2024-08-30T00:00:00","2024-08-30T06:00:00","2024-08-30T12:00:00","2024-08-30T18:00:00","2024-08-31T00:00:00","2024-08-31T06:00:00","2024-08-31T12:00:00","2024-08-31T18:00:00","2024-09-01T00:00:00","2024-09-01T06:00:00","2024-09-01T12:00:00","2024-09-01T18:00:00","2024-09-02T00:00:00","2024-09-02T06:00:00","2024-09-02T12:00:00","2024-09-02T18:00:00","2024-09-03T00:00:00","2024-09-03T06:00:00","2024-09-03T12:00:00","2024-09-03T18:00:00","2024-09-04T00:00:00","2024-09-04T06:00:00","2024-09-04T12:00:00"],"primary_name":"Tailwater","primary_forecast":[18.0,18.0,17.9,17.8,17.7,17.6,17.5,17.4,17.3,17.2,17.2,17.1,17.1,17.0,17.0,17.0,16.9,16.9,16.8,16.8,16.7,16.7,16.6,16.6,16.5,16.5,16.5,16.4,16.4,16.4,16.4,16.4,16.4,16.3,16.3,16.3,16.3,16.3,16.2,16.2,16.2,16.1,16.1,16.0,16.0,15.9,15.9,15.8,15.8,15.7,15.6,15.6,15.5,15.4,15.3,15.3],"primary_unit":"ft","secondary_name":"Flow","secondary_forecast":[2690.10042624,2690.10042624,2650.4568410112,2610.8132557824,2571.1696705536,2531.5260853248,2491.882500096,2452.2389148672,2412.5953296384,2372.9517444096,2372.9517444096,2333.3081591808,2333.3081591808,2293.664573952,2293.664573952,2293.664573952,2259.6843580416003,2259.6843580416003,2225.7041421312,2225.7041421312,2191.7239262208,2191.7239262208,2157.7437103104003,2157.7437103104003,2123.7634944,2123.7634944,2123.7634944,2089.7832784896,2089.7832784896,2089.7832784896,2089.7832784896,2089.7832784896,2089.7832784896,2055.8030625792,2055.8030625792,2055.8030625792,2055.8030625792,2055.8030625792,2021.8228466688001,2021.8228466688001,2021.8228466688001,1987.8426307584,1987.8426307584,1953.862414848,1953.862414848,1919.8821989376002,1919.8821989376002,1885.9019830272,1885.9019830272,1851.9217671168003,1817.9415512064002,1817.9415512064002,1783.961335296,1752.8128040448,1721.6642727936,1721.6642727936],"secondary_unit":"m3 s-1","status":{"observed":{"primary":17.89,"primaryUnit":"ft","secondary":93.4,"secondaryUnit":"kcfs","floodCategory":"no_flooding","validTime":"2024-08-21T21:30:00Z"},"forecast":{"primary":18.0,"primaryUnit":"ft","secondary":95.0,"secondaryUnit":"kcfs","floodCategory":"no_flooding","validTime":"2024-08-22T00:00:00Z"}},"lid":"CAGM7","usgs_id":"05513675","feature_id":2930769,"reach_id":"2930769","name":"Mississippi River at Winfield Lock and Dam 25","rfc":{"abbreviation":"NCRFC","name":"North Central River Forecast Center"},"wfo":{"abbreviation":"LSX","name":"St. Charles"},"county":"Lincoln","timeZone":"CST6CDT","latitude":39.000833333333,"longitude":-90.6875}'


@pytest.fixture
def sample_rfc_body() -> str:
    """A sample message body

    Returns
    -------
    str:
      the sample RFC body
    """
    return b'"{"times":["2024-08-27T18:00:00","2024-08-28T00:00:00","2024-08-28T06:00:00","2024-08-28T12:00:00","2024-08-28T18:00:00","2024-08-29T00:00:00","2024-08-29T06:00:00","2024-08-29T12:00:00","2024-08-29T18:00:00","2024-08-30T00:00:00","2024-08-30T06:00:00","2024-08-30T12:00:00","2024-08-30T18:00:00","2024-08-31T00:00:00","2024-08-31T06:00:00","2024-08-31T12:00:00","2024-08-31T18:00:00","2024-09-01T00:00:00","2024-09-01T06:00:00","2024-09-01T12:00:00","2024-09-01T18:00:00","2024-09-02T00:00:00","2024-09-02T06:00:00","2024-09-02T12:00:00","2024-09-02T18:00:00","2024-09-03T00:00:00","2024-09-03T06:00:00","2024-09-03T12:00:00","2024-09-03T18:00:00","2024-09-04T00:00:00","2024-09-04T06:00:00","2024-09-04T12:00:00","2024-09-04T18:00:00","2024-09-05T00:00:00","2024-09-05T06:00:00","2024-09-05T12:00:00","2024-09-05T18:00:00","2024-09-06T00:00:00","2024-09-06T06:00:00","2024-09-06T12:00:00","2024-09-06T18:00:00","2024-09-07T00:00:00","2024-09-07T06:00:00","2024-09-07T12:00:00","2024-09-07T18:00:00","2024-09-08T00:00:00","2024-09-08T06:00:00","2024-09-08T12:00:00","2024-09-08T18:00:00","2024-09-09T00:00:00","2024-09-09T06:00:00","2024-09-09T12:00:00","2024-09-09T18:00:00","2024-09-10T00:00:00","2024-09-10T06:00:00","2024-09-10T12:00:00"],"primary_name":"Tailwater","primary_forecast":[16.2,16.3,16.3,16.3,16.3,16.2,16.2,16.1,16.1,16.0,16.0,16.0,15.9,15.8,15.7,15.7,15.6,15.5,15.5,15.4,15.4,15.3,15.3,15.3,15.2,15.2,15.2,15.2,15.1,15.1,15.1,15.1,15.1,15.1,15.1,15.1,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,15.0,14.9,14.9,14.9,14.9,14.9,14.9],"primary_unit":"ft","secondary_name":"Flow","secondary_forecast":[2021.8228466688001,2055.8030625792,2055.8030625792,2055.8030625792,2055.8030625792,2021.8228466688001,2021.8228466688001,1987.8426307584,1987.8426307584,1953.862414848,1953.862414848,1953.862414848,1919.8821989376002,1885.9019830272,1851.9217671168003,1851.9217671168003,1817.9415512064002,1783.961335296,1783.961335296,1752.8128040448,1752.8128040448,1721.6642727936,1721.6642727936,1721.6642727936,1690.5157415424,1690.5157415424,1690.5157415424,1690.5157415424,1659.3672102912,1659.3672102912,1659.3672102912,1659.3672102912,1659.3672102912,1659.3672102912,1659.3672102912,1659.3672102912,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1628.21867904,1591.4067784704,1591.4067784704,1591.4067784704,1591.4067784704,1591.4067784704,1591.4067784704],"secondary_unit":"m3 s-1","status":{"observed":{"primary":16.19,"primaryUnit":"ft","secondary":71.2,"secondaryUnit":"kcfs","floodCategory":"no_flooding","validTime":"2024-08-27T15:00:00Z"},"forecast":{"primary":16.3,"primaryUnit":"ft","secondary":72.6,"secondaryUnit":"kcfs","floodCategory":"no_flooding","validTime":"2024-08-28T00:00:00Z"}},"lid":"CAGM7","upstream_lid":"MOZI2","downstream_lid":"GRFI2","usgs_id":"05513675","feature_id":2930769,"downstream_feature_id":880478,"latest_observation":[2016.1594773504],"latest_obs_units":"m3 s-1","reach_id":"2930769","name":"Mississippi River at Winfield Lock and Dam 25","rfc":{"abbreviation":"NCRFC","name":"North Central River Forecast Center"},"wfo":{"abbreviation":"LSX","name":"St. Charles"},"state":{"abbreviation":"MO","name":"Missouri"},"county":"Lincoln","timeZone":"CST6CDT","latitude":39.000833333333,"longitude":-90.6875}"'
