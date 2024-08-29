from typing import Any, Dict

import httpx


def _get(
    endpoint: str,
    params: Dict[str, Any],
) -> Dict[str, Any]:
    """An asynchronous GET request using httpx.

    Parameters
    ----------
    endpoint : str
    - The URL we're hitting.
    
    params : Optional[Dict[str, Any]], optional
    - The parameters passed to the API endpoint.

    Returns
    -------
    Dict[str, Any]
    - The JSON response from the API.

    Raises
    ------
    NWPSAPIError
    - If the request fails or returns a non-200 status code.
    """
    client = httpx.Client(timeout=60.0)  # Use a default 10s timeout everywhere.
    try:
        if params is not None:
            response = client.get(endpoint, params=params, timeout=None)
        response.raise_for_status()
        return response.json()
    except httpx.HTTPStatusError as exc:
        raise exc


def run_troute(
    lid: str,
    feature_id: str,
    mapped_feature_id: str,
    start_time: str,
    initial_start: float,
    num_forecast_days: int,
    base_url: str,
) -> Dict[str, Any]:
    endpoint = f"{base_url}/flow_routing/v4/"
    params = {
        "lid": lid,
        "feature_id": feature_id,
        "hy_id": mapped_feature_id,
        "initial_start": initial_start,
        "start_time": start_time,
        "num_forecast_days": num_forecast_days,
    }
    return _get(endpoint, params)
