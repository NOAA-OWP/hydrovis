DROP TABLE IF EXISTS publish.srf_15hr_peak_flow_arrival_time_alaska;

WITH arrival_time AS (
     SELECT 
         forecasts.feature_id,
         max(forecasts.forecast_hour)+1 AS t_normal
     FROM ingest.nwm_channel_rt_srf_alaska AS forecasts
     GROUP BY forecasts.feature_id
    )
SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    forecasts.nwm_vers,
    forecasts.reference_time,
    min(forecast_hour) AS peak_flow_arrival_hour,
    arrival_time.t_normal AS below_bank_return_time,
    round((max_flows.maxflow_15hour_cms*35.315)::numeric, 2) AS max_flow_cfs,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    'AK' AS state,
    -9999.0 as high_water_threshold,
    channels.geom
INTO publish.srf_15hr_peak_flow_arrival_time_alaska
FROM ingest.nwm_channel_rt_srf_alaska AS forecasts 

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.max_flows_srf_alaska AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND forecasts.streamflow = max_flows.maxflow_15hour_cms

-- Join in channels data to get reach metadata and geometry
JOIN derived.channels_alaska as channels ON forecasts.feature_id = channels.feature_id::bigint

-- Join in arrival_time query results
JOIN arrival_time ON forecasts.feature_id = arrival_time.feature_id

GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers, arrival_time.t_normal, max_flows.maxflow_15hour_cms, channels.geom, channels.strm_order, channels.name, channels.huc6;