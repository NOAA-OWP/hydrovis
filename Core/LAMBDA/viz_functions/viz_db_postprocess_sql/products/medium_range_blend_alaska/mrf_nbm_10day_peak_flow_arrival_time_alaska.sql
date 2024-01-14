DROP TABLE IF EXISTS publish.mrf_nbm_10day_peak_flow_arrival_time_alaska;

WITH arrival_time AS(
    SELECT 
           forecasts.feature_id, 
           max(forecasts.forecast_hour)+1 AS below_bank_return_hour
    FROM ingest.nwm_channel_rt_mrf_nbm_ak AS forecasts
    GROUP BY forecasts.feature_id
)

SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    min(forecasts.forecast_hour) AS peak_flow_arrival_hour,
    to_char(forecasts.reference_time::timestamp without time zone + INTERVAL '1 hour' * min(forecasts.forecast_hour), 'YYYY-MM-DD HH24:MI:SS UTC') AS peak_flow_arrival_time,
    forecasts.nwm_vers,
    forecasts.reference_time,
    max_flows.discharge_cfs AS max_flow_cfs,
    arrival_time.below_bank_return_hour,
    to_char(forecasts.reference_time::timestamp without time zone + INTERVAL '1 hour' * arrival_time.below_bank_return_hour, 'YYYY-MM-DD HH24:MI:SS UTC') AS below_bank_return_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    'AK' as state,
    -9999.0 as high_water_threshold,
    channels.geom
   
INTO publish.mrf_nbm_10day_peak_flow_arrival_time_alaska
FROM ingest.nwm_channel_rt_mrf_nbm_ak AS forecasts

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.mrf_nbm_max_flows_10day_ak AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND round((forecasts.streamflow*35.315)::numeric, 2) = max_flows.discharge_cfs

-- Join in channels data to get reach metadata and geometry
JOIN derived.channels_alaska as channels ON forecasts.feature_id = channels.feature_id::bigint

-- Join in arrival_time 
JOIN arrival_time ON forecasts.feature_id = arrival_time.feature_id

GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers, forecasts.streamflow, max_flows.discharge_cfs, arrival_time.below_bank_return_hour, channels.geom, channels.strm_order, channels.name, channels.huc6;