DROP TABLE IF EXISTS publish.srf_peak_flow_arrival_time_hi;

WITH arrival_time AS (
     SELECT 
            forecasts.feature_id,
            max(forecasts.forecast_hour)+1 AS t_normal
     FROM ingest.nwm_channel_rt_srf_hi AS forecasts
     JOIN derived.recurrence_flows_hi AS thresholds ON forecasts.feature_id = thresholds.feature_id
     WHERE (THRESHOLDS.HIGH_WATER_THRESHOLD > 0 OR THRESHOLDS.HIGH_WATER_THRESHOLD = '-9999') AND forecasts.streamflow * 35.315::double precision >= thresholds.high_water_threshold
     GROUP BY forecasts.feature_id
    )
SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    channels.name,
    (channels.strm_order)::integer,
    channels.huc6,
    channels.nwm_vers,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    CASE WHEN rf.HIGH_WATER_THRESHOLD = -9999 THEN NULL ELSE min(forecast_hour) END AS peak_flow_arrival_hour,
    CASE WHEN rf.HIGH_WATER_THRESHOLD = -9999 THEN NULL ELSE arrival_time.t_normal END AS below_bank_return_time,
    round((max_flows.maxflow_48hour_cms*35.315)::numeric, 2) AS max_flow_cfs,
    rf.high_water_threshold,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
    channels.geom
        
INTO publish.srf_peak_flow_arrival_time_hi
FROM ingest.nwm_channel_rt_srf_hi AS forecasts

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.max_flows_srf_hi AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND forecasts.streamflow = max_flows.maxflow_48hour_cms

-- Join in channels data to get reach metadata 
JOIN derived.channels_hi as channels ON forecasts.feature_id = channels.feature_id

-- Join in recurrence flows to get high water threshold
JOIN derived.recurrence_flows_hi as rf ON forecasts.feature_id = rf.feature_id

-- Join in arrival_time query results
JOIN arrival_time ON forecasts.feature_id = arrival_time.feature_id

WHERE (rf.HIGH_WATER_THRESHOLD > 0 OR rf.HIGH_WATER_THRESHOLD = '-9999') AND forecasts.streamflow * 35.315::double precision >= rf.high_water_threshold
GROUP BY forecasts.feature_id, channels.name, channels.strm_order, channels.huc6, channels.nwm_vers, rf.high_water_threshold, arrival_time.t_normal, max_flows.maxflow_48hour_cms, channels.geom
