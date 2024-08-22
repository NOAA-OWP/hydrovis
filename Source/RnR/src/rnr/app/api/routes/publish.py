import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from src.rnr.app.api.client.pika import (close_connection, start_connection,
                                         start_work_queues)
from src.rnr.app.api.database import get_db
from src.rnr.app.api.services.publish import MessagePublisherService
from src.rnr.app.api.services.rfc import RFCReaderService
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import AsyncRateLimiter
from src.rnr.app.schemas import PublishMessagesResponse, ResultItem, Summary

router = APIRouter()


@router.post("/start/{lid}", response_model=PublishMessagesResponse)
async def publish_single_message(
    lid: str,
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> PublishMessagesResponse:
    """
    Publish messages based on RFC data and NWPS forecasts.

    This endpoint is designed to be triggered by an event scheduler.
    It processes RFC entries, fetches gauge data and forecasts,
    and publishes messages to a message queue.

    Parameters
    ----------
    identifier: str
        The LID that we want to process
    settings: Settings
        The BaseSettings config object
    db : Session
        The database session from the config URL.

    Returns
    -------
    PublishMessagesResponse
        A response object containing:
        - status: HTTP status code
        - summary: Summary of processing results
        - results: Detailed results for each RFC entry
    """
    connection = start_connection(settings.pika_url)
    channel = start_work_queues(connection, settings)
    # Since we are using an identifier, there will be one entry here
    rfc_entry = RFCReaderService.get_rfc_data(db, identifier=lid).entries[
        0
    ]  # An RFCDatabaseEntries obj is always returned

    tasks = [MessagePublisherService.process_rfc_entry(rfc_entry, channel, settings)]
    results = await asyncio.gather(*tasks)

    close_connection(connection)

    summary = Summary(
        total=len(results),
        success=sum(1 for r in results if r.get("status") == "success"),
        no_forecast=sum(1 for r in results if r.get("status") == "no_forecast"),
        api_error=sum(1 for r in results if r.get("status") == "api_error"),
        validation_error=sum(
            1 for r in results if r.get("status") == "validation_error"
        ),
    )

    return PublishMessagesResponse(
        status=200, summary=summary, results=[ResultItem(**r) for r in results]
    )


@router.post("/start", response_model=PublishMessagesResponse)
async def publish_messages(
    settings: Annotated[Settings, Depends(get_settings)], db: Session = Depends(get_db)
) -> PublishMessagesResponse:
    """
    Publish messages based on RFC data and NWPS forecasts.

    This endpoint is designed to be triggered by an event scheduler.
    It processes RFC entries, fetches gauge data and forecasts,
    and publishes messages to a message queue.

    Parameters
    ----------
    settings: Settings
        The BaseSettings config object
    db : Session
        The database session from the config URL.

    Returns
    -------
    PublishMessagesResponse
        A response object containing:
        - status: HTTP status code
        - summary: Summary of processing results
        - results: Detailed results for each RFC entry
    """
    connection = start_connection(settings.pika_url)
    channel = start_work_queues(connection, settings)
    rfc_entries = RFCReaderService.get_rfc_data(
        db
    ).entries  # An RFCDatabaseEntries obj is always returned

    limiter = AsyncRateLimiter(
        rate_limit=15, time_period=1
    )  # Setting a Rate Limit for Async Requests at 15 stations per second

    async def limited_process(entry):
        async with limiter:
            return await MessagePublisherService.process_rfc_entry(
                entry, channel, settings
            )

    tasks = [limited_process(rfc_entry) for rfc_entry in rfc_entries]
    results = await asyncio.gather(*tasks)

    close_connection(connection)
    summary = Summary(
        total=len(results),
        success=sum(1 for r in results if r.get("status") == "success"),
        no_forecast=sum(1 for r in results if r.get("status") == "no_forecast"),
        api_error=sum(1 for r in results if r.get("status") == "api_error"),
        validation_error=sum(
            1 for r in results if r.get("status") == "validation_error"
        ),
    )

    return PublishMessagesResponse(
        status=200, summary=summary, results=[ResultItem(**r) for r in results]
    )
