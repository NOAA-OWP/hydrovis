from enum import IntEnum

from pydantic import BaseModel


class HTTPStatus(IntEnum):
    """Enumeration of common HTTP status codes.

    Attributes:
    -----------
    OK : int
        200 - Successful request
    BAD_REQUEST : int
        400 - The server cannot process the request due to a client error
    NOT_FOUND : int
        404 - The requested resource could not be found
    INTERNAL_SERVER_ERROR : int
        500 - The server encountered an unexpected condition
    """

    OK = 200
    BAD_REQUEST = 400
    NOT_FOUND = 404
    INTERNAL_SERVER_ERROR = 500


class PublishSingleMessage(BaseModel):
    """A schema for validating a published singular message

    Attributes:
    -----------
    status: HTTPStatus
        The HTTP status of the request
    message: str
        The message to be displayed
    lid: str
        The location we're publishing data for
    """

    status: HTTPStatus
    message: str


class ProcessedData(BaseModel):
    """The message to be sent to the consumer"""

    message: str
