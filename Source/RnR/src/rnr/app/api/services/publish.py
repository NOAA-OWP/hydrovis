import json
from typing import Dict

import redis
from pydantic import ValidationError
from sqlalchemy.orm import Session

from src.rnr.app.api.services.nwps import NWPSService
from src.rnr.app.api.services.rfc import RFCReaderService
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.logging_module import setup_logger
from src.rnr.app.core.exceptions import NoForecastError, NWPSAPIError
from src.rnr.app.core.rabbit_connection import rabbit_connection
from src.rnr.app.core.settings import Settings
from src.rnr.app.schemas import (
    GaugeData,
    GaugeForecast,
    ProcessedData,
    RFCDatabaseEntry,
)

log = setup_logger('default', 'consumer.log')

_settings = get_settings()

r_cache = redis.Redis(host=_settings.redis_url, port=6379, decode_responses=True)


class MessagePublisherService:
    """
    Service class for handling message publishing to RabbitMQ queues.

    This class provides methods for managing RabbitMQ connections, processing RFC entries,
    and publishing messages to appropriate queues.

    Methods
    -------
    process_rfc_entry(rfc_entry: RFCDatabaseEntry, channel: pika.BlockingConnection.channel, settings: Settings) -> Dict[str, str]
        Process an RFC entry and publish related messages.
    process_and_publish_messages(gauge_data: GaugeData, gauge_forecast: GaugeForecast, rfc_entry: RFCDatabaseEntry, channel: pika.BlockingConnection.channel, settings: Settings) -> None
        Process gauge data and forecast, and publish messages to appropriate queues.
    """

    @staticmethod
    async def process_rfc_entry(
        rfc_entry: RFCDatabaseEntry,
        db: Session,
        settings: Settings,
    ) -> Dict[str, str]:
        """
        Process an RFC entry and publish related messages.

        Parameters
        ----------
        rfc_entry : RFCDatabaseEntry
            The RFC table entry.
        channel : pika.BlockingConnection.channel
            The RabbitMQ channel.
        settings : Settings
            The application settings.

        Returns
        -------
        Dict[str, str]
            A dictionary containing the status of the processing operation.
        """
        try:
            gauge_data = await NWPSService.get_gauge_data(rfc_entry.nws_lid, settings)
            if gauge_data.downstreamLid is None:
                message=f"No downstream LID for {rfc_entry.nws_lid}" 
                log.error(message)
                await rabbit_connection.send_message(
                    message=json.dumps(message), routing_key=settings.error_queue
                )
                return {
                    "status": "api_error",
                    "lid": rfc_entry.nws_lid,
                    "error_type": "RFC Not Found",
                    "error_message": message,
                    "status_code": 404,
                }
            try:
                rfc_ds_entry = RFCReaderService.get_rfc_data(
                    db, identifier=gauge_data.downstreamLid
                ).entries[0]
            except ValidationError:
                message = {
                    "message": f"Pydantic data validation error for downtream LID from LID: {gauge_data.lid}. Downstream LID not found"
                }
                log.error(message["message"])
                await rabbit_connection.send_message(
                    message=json.dumps(message), routing_key=settings.error_queue
                )
        except NWPSAPIError as e:
            message = {
                "message": f"NWPSAPIError for reading {rfc_entry.nws_lid}: {str(e)}"
            }
            log.error(message["message"])
            await rabbit_connection.send_message(
                message=json.dumps(message), routing_key=settings.error_queue
            )
            return {
                "status": "api_error",
                "lid": rfc_entry.nws_lid,
                "error_type": "NWPSAPIError",
                "error_message": str(e),
                "status_code": getattr(e, "status_code", None),
            }

        try:
            gauge_forecast = await NWPSService.get_gauge_product_forecast(
                rfc_entry.nws_lid, settings
            )
        except NoForecastError as e:
            message = f"NoForecastError for {rfc_entry.nws_lid}: {str(e)}"
            log.error(message)
            return {
                "status": "no_forecast",
                "lid": rfc_entry.nws_lid,
                "error_type": "NoForecastError",
                "error_message": str(e),
                "status_code": getattr(e, "status_code", None),
            }

        except NWPSAPIError as e:
            message = {"message": f"NWPSAPIError for {rfc_entry.nws_lid}: {str(e)}"}
            log.error(message)
            await rabbit_connection.send_message(
                message=json.dumps(message), routing_key=settings.error_queue
            )
            return {
                "status": "api_error",
                "lid": rfc_entry.nws_lid,
                "error_type": "NWPSAPIError",
                "error_message": str(e),
                "status_code": getattr(e, "status_code", None),
            }

        formatted_time = gauge_forecast.times[0].strftime("%Y%m%d%H%M")
        cache_key = rfc_entry.nws_lid + "_" + formatted_time
        cache_value = hash(json.dumps(gauge_forecast.secondary_forecast))
        if not r_cache.exists(cache_key) or str(r_cache.get(cache_key)) != str(
            cache_value
        ):
            try:
                await MessagePublisherService.process_and_publish_messages(
                    gauge_data=gauge_data,
                    gauge_forecast=gauge_forecast,
                    rfc_entry=rfc_entry,
                    rfc_ds_entry=rfc_ds_entry,
                    settings=settings,
                )
            except ValidationError as e:
                message = {
                    "message": f"Pydantic data validation error for LID: {GaugeData.lid}"
                }
                log.error(message["message"])
                await rabbit_connection.send_message(
                    message=json.dumps(message), routing_key=settings.error_queue
                )
                return {
                    "status": "validation_error",
                    "lid": rfc_entry.nws_lid,
                    "error_type": "NWPSAPIError",
                    "error_message": str(e),
                    "status_code": getattr(e, "status_code", None),
                }
            except UnboundLocalError:
                message = {
                    "message": f"No RFC DS Entry for: {gauge_data.lid}"
                }
                log.error(message["message"])
                await rabbit_connection.send_message(
                    message=json.dumps(message), routing_key=settings.error_queue
                )
                return {
                    "status": "validation_error",
                    "lid": gauge_data.lid,
                    "error_type": "UnboundLocalError",
                    "error_message": message,
                    "status_code": 500,
                }
        else:
            return {"status": "cached", "lid": rfc_entry.nws_lid}

        return {"status": "success", "lid": rfc_entry.nws_lid}

    @staticmethod
    async def process_and_publish_messages(
        gauge_data: GaugeData,
        gauge_forecast: GaugeForecast,
        rfc_entry: RFCDatabaseEntry,
        rfc_ds_entry: RFCDatabaseEntry,
        settings: Settings,
    ) -> None:
        """
        Process gauge data and forecast, and publish messages to appropriate queues.

        Parameters
        ----------
        gauge_data : GaugeData
            The gauge metadata.
        gauge_forecast : GaugeForecast
            The gauge forecast data.
        rfc_entry : RFCDatabaseEntry
            The RFC database entry.
        channel : pika.BlockingConnection.channel
            The RabbitMQ channel.
        settings : Settings
            The application settings.
        """
        # is_flood_observed = gauge_data.status.observed.floodCategory != "no_flooding"
        is_flood_forecasted = gauge_data.status.forecast.floodCategory != "no_flooding"
        processed_data = ProcessedData(
            lid=gauge_data.lid,
            upstream_lid=gauge_data.upstreamLid,
            downstream_lid=gauge_data.downstreamLid,
            usgs_id=gauge_data.usgsId,
            feature_id=rfc_entry.feature_id,
            downstream_feature_id=rfc_ds_entry.feature_id,
            reach_id=gauge_data.reachId,
            name=gauge_data.name,
            rfc=gauge_data.rfc,
            wfo=gauge_data.wfo,
            state=gauge_data.state,
            county=gauge_data.county,
            timeZone=gauge_data.timeZone,
            latitude=gauge_data.latitude,
            longitude=gauge_data.longitude,
            latest_observation=gauge_forecast.latest_observation,
            latest_obs_units=gauge_forecast.latest_obs_units,
            status=gauge_data.status,
            times=gauge_forecast.times,
            primary_name=gauge_forecast.primary_name,
            primary_forecast=gauge_forecast.primary_forecast,
            primary_unit=gauge_forecast.primary_unit,
            secondary_name=gauge_forecast.secondary_name,
            secondary_forecast=gauge_forecast.secondary_forecast,
            secondary_unit=gauge_forecast.secondary_unit,
        )

        message = json.dumps(processed_data.model_dump_json())
        log.info(f"Sending message for LID: {gauge_data.lid}")
        if is_flood_forecasted:
            await rabbit_connection.send_message(
                message=message, routing_key=settings.priority_queue
            )
        else:
            await rabbit_connection.send_message(
                message=message, routing_key=settings.base_queue
            )
