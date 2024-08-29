class NWPSAPIError(Exception):
    """Exception raised for errors in the NWPS API response.

    Parameters
    ----------
    status_code : int
    - HTTP status code of the failed request.
    
    endpoint : str
    - The API endpoint that was called.

    Attributes
    ----------
    status_code : int
    - HTTP status code of the failed request.
    
    endpoint : str
    - The API endpoint that was called.
    
    message : str
    - Explanation of the error.
    """

    def __init__(self, status_code: int, endpoint: str) -> None:
        self.status_code = status_code
        self.endpoint = endpoint
        self.message = (
            f"Request failed. Status Code: {status_code}. Endpoint: {endpoint}"
        )
        super().__init__(self.message)

    def __str__(self):
        return f"NWPSAPIError: {self.message}"


class NoForecastError(Exception):
    """Exception raised when there is no forecast from the RFC

    Parameters
    ----------
    identifier : str
    - The location identifier of the RFC

    Attributes
    ----------
    message : str
    - Explanation of the error.
    """

    def __init__(self, identifier: str) -> None:
        self.message = f"No Forecast detected for {identifier}"
        super().__init__(self.message)

    def __str__(self):
        return f"NoForecastError: {self.message}"


class ManyToOneError(Exception):
    """Exception raised when there are many divide IDs associated with a single COMID after subsetting

    Attributes
    ----------
    message : str
    - Explanation of the error.
    """

    def __init__(self) -> None:
        self.message = "Many divide ids found for one COMID. This location will have inaccurate routing if continuing"
        super().__init__(self.message)

    def __str__(self):
        return f"ManyToOneError: {self.message}"
