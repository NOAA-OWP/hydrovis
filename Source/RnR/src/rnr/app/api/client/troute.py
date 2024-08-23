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
    

def run_troute(
    lid: str,
    feature_id: str,
    start_time: str,
    num_forecast_days: int,
    base_url: str
) -> Dict[str, Any]:
    endpoint = f"{base_url}/v4/flow_routing/"
    params = {
        "lid": lid,
        "feature_id": feature_id,
        "start_time": start_time,
        "num_forecast_days": num_forecast_days
    }
    return _get(endpoint, params)