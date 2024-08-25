from typing import Any, Dict, Optional

import httpx


def _get(
    endpoint: str,
    params: Dict[str, Any],
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
    client = httpx.Client(timeout=60.0)  # Use a default 10s timeout everywhere.
    try:
        if params is not None:
            response = client.get(endpoint, params=params, timeout=None)
        response.raise_for_status()
        return response.json()
    except httpx.HTTPStatusError as exc:
        raise exc


async def async_get(
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
    HTTPStatusError
        If the request fails or returns a non-200 status code.
    """
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(endpoint, params=params, timeout=None)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as exc:
            raise exc


def subset(
    feature_id: str,
    base_url: str,
) -> Dict[str, Any]:
    endpoint = f"{base_url}/subset/"
    params = {
        "comid": feature_id,
        "lyrs": [
            "divides",
            "nexus",
            "flowpaths",
            "lakes",
            "flowpath_attributes",
            "network",
            "layer_styles",
        ],
    }
    return _get(endpoint, params)


async def async_subset(
    feature_id: str,
    base_url: str,
) -> Dict[str, Any]:
    endpoint = f"{base_url}/subset/"
    params = {
        "feature_id": feature_id,
        "lyrs": [
            "divides",
            "nexus",
            "flowpaths",
            "lakes",
            "flowpath_attributes",
            "network",
            "layer_styles",
        ],
    }
    return await async_get(endpoint, params)


async def async_downstream(
    feature_id: str,
    ds_feature_id: str,
    base_url: str,
) -> Dict[str, Any]:
    endpoint = f"{base_url}/downstream/"
    params = {
        "feature_id": feature_id,
        "downstream_feature_id": ds_feature_id,
        "lyrs": [
            "divides",
            "nexus",
            "flowpaths",
            "lakes",
            "flowpath_attributes",
            "network",
            "layer_styles",
        ],
    }
    return await async_get(endpoint, params)
