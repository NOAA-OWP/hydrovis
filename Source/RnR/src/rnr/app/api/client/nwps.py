from typing import Any, Dict, Optional

import httpx

from src.rnr.app.core.exceptions import NWPSAPIError


async def _get(
    endpoint: str, params: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """An asynchronous GET request using httpx.

    Parameters
    ----------
    endpoint : str
        The URL we're hitting.
    params : Optional[Dict[str, Any]], optional
        The parameters passed to the API endpoint.

    Returns
    -------
    Dict[str, Any]
        The JSON response from the API.

    Raises
    ------
    NWPSAPIError
        If the request fails or returns a non-200 status code.
    """
    async with httpx.AsyncClient() as client:
        try:
            if params is not None:
                response = await client.get(endpoint, params=params)
            else:
                response = await client.get(endpoint)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as exc:
            raise NWPSAPIError(exc.response.status_code, endpoint) from exc
        except httpx.RequestError as exc:
            raise NWPSAPIError(0, endpoint) from exc  # Using 0 for a NetworkError


async def gauges(
    x_min: float,
    y_min: float,
    x_max: float,
    y_max: float,
    base_url: str,
    srid: str = "EPSG_4326",
) -> Dict[str, Any]:
    """Reads the gauges API from api.water.noaa.gov.

    Parameters
    ----------
    x_min : float
        Bottom-left X coordinate of a bounding box geometry.
    y_min : float
        Bottom-left Y coordinate of a bounding box geometry.
    x_max : float
        Top-right X coordinate of a bounding box geometry.
    y_max : float
        Top-right Y coordinate of a bounding box geometry.
    base_url : str
        The base URL for the API.
    srid : str, optional
        Spatial reference system ID for input geometry. Default is "EPSG_4326".

    Returns
    -------
    Dict[str, Any]
        The gauges within the bounding box.
    """
    endpoint = f"{base_url}/gauges"
    params = {
        "bbox.xmin": x_min,
        "bbox.ymin": y_min,
        "bbox.xmax": x_max,
        "bbox.ymax": y_max,
        "srid": srid,
    }
    return await _get(endpoint, params)


async def gauge_data(identifier: str, base_url: str) -> Dict[str, Any]:
    """Get Stage/Flow for a specific gauge.

    Parameters
    ----------
    identifier : str
        The gauge's unique identifier, LID, or USGS ID.
    base_url : str
        The base URL for the API.

    Returns
    -------
    Dict[str, Any]
        The gauge metadata.
    """
    endpoint = f"{base_url}/gauges/{identifier}"
    return await _get(endpoint)


async def gauge_ratings(
    identifier: str,
    base_url: str,
    limit: Optional[str] = "10000",
    sort: Optional[str] = "ASC",
    only_tenths: Optional[bool] = False,
) -> Dict[str, Any]:
    """
    Get ratings based off of STAGE Data.

    Parameters
    ----------
    identifier : str
        The gauge's unique identifier, LID, or USGS ID.
    base_url : str
        The base URL for the API.
    limit : str, optional
        Limit the number of results. Default is "10000".
    sort : str, optional
        Sorts results by ascending (ASC) or descending (DSC). Default is "ASC".
    only_tenths : bool, optional
        Limits ratings to only tenths of a foot increments. Default is False.

    Returns
    -------
    Dict[str, Any]
        The gauge metadata.

    Raises
    ------
    NWPSAPIError
        If an incorrect sort option is provided.
    """
    endpoint = f"{base_url}/gauges/{identifier}/ratings"
    params = {
        "limit": limit,
        "onlyTenths": only_tenths,
    }
    if sort.upper() in [
        "ASC",
        "DSC",
    ]:
        params["sort"] = sort
    else:
        raise NWPSAPIError(404, "Incorrect sort provided")
    return await _get(endpoint, params)


async def gauge_stageflow(
    identifier: str,
    base_url: str,
) -> Dict[str, Any]:
    """Gets stageflow based on gauge.

    Parameters
    ----------
    identifier : str
        The gauge's unique identifier, LID, or USGS ID.
    base_url : str
        The base URL for the API.

    Returns
    -------
    Dict[str, Any]
        The gauge stageflow.
    """
    endpoint = f"{base_url}/gauges/{identifier}/stageflow"
    return await _get(endpoint)


async def gauge_product(identifier: str, base_url: str, product: str) -> Dict[str, Any]:
    """Gets stageflow based on gauge.

    Parameters
    ----------
    identifier : str
        The gauge's unique identifier, LID, or USGS ID.
    base_url : str
        The base URL for the API.
    product : str
        The product you're looking for.

    Returns
    -------
    Dict[str, Any]
        The gauge stageflow product.

    Raises
    ------
    NWPSAPIError
        If an incorrect product is provided.
    """
    endpoint = f"{base_url}/gauges/{identifier}/stageflow/{product}"
    if product.lower() in [
        "observed",
        "forecast",
    ]:
        return await _get(endpoint)
    else:
        raise NWPSAPIError(404, "Incorrect product provided")


async def reaches(reach_id: str, base_url: str) -> Dict[str, Any]:
    """
    Reads the gauges API from api.water.noaa.gov.

    Parameters
    ----------
    reach_id : str
        The reach's unique Reach ID.
    base_url : str
        The base URL for the API.

    Returns
    -------
    Dict[str, Any]
        The reach metadata.
    """
    endpoint = f"{base_url}/reaches/{reach_id}"
    return await _get(endpoint)


async def reach_streamflow(
    reach_id: str, base_url: str, series: Optional[str] = "analysis_assimilation"
) -> Dict[str, Any]:
    """Reads the gauges API from api.water.noaa.gov.

    Parameters
    ----------
    reach_id : str
        The reach's unique Reach ID.
    base_url : str
        The base URL for the API.
    series : str, optional
        The specific forecast requested. Default is "analysis_assimilation".

    Returns
    -------
    Dict[str, Any]
        The reach streamflow.

    Raises
    ------
    NWPSAPIError
        If an incorrect series is provided.
    """
    endpoint = f"{base_url}/reaches/{reach_id}"
    if series.lower() in [
        "analysis_assimilation",
        "short_range",
        "medium_range",
        "long_range",
        "medium_range_blend",
    ]:
        params = {
            "series": series,
        }
        return await _get(endpoint, params)
    else:
        raise NWPSAPIError(404, "Incorrect series provided")


async def stageflow(identifier: str, base_url: str, pedts: str) -> Dict[str, Any]:
    """Get Stage/Flow for a specific gauge.

    Parameters
    ----------
    identifier : str
        The gauge's unique identifier.
    base_url : str
        The base URL for the API.
    pedts : str
        The standard hydrometeorological exchange format parameter codes.

    Returns
    -------
    Dict[str, Any]
        The stageflow given the LID and product.
    """
    endpoint = f"{base_url}/products/stageflow/{identifier}/{pedts}"
    return await _get(endpoint)
