DROP TABLE IF EXISTS publish.srf_peak_flow_arrival_time_prvi_para;

WITH arrival_time AS (
     SELECT 
            forecasts.feature_id,
            max(forecasts.forecast_hour)+1 AS t_normal
     FROM ingest.nwm_channel_rt_srf_prvi_para AS forecasts
     JOIN derived.recurrence_flows_prvi AS thresholds ON forecasts.feature_id = thresholds.feature_id
     WHERE (forecasts.streamflow * 35.315::double precision) >= thresholds.high_water_threshold
     GROUP BY forecasts.feature_id
    )
SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    channels.name,
    (channels.strm_order)::integer,
    channels.huc6,
    forecasts.nwm_vers,
    forecasts.reference_time,
    min(forecast_hour) AS peak_flow_arrival_hour,
    arrival_time.t_normal AS below_bank_return_time,
    round((max_flows.maxflow_48hour_cms*35.315)::numeric, 2) AS max_flow_cfs,
    rf.high_water_threshold,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
    channels.geom
        
INTO publish.srf_peak_flow_arrival_time_prvi_para
FROM ingest.nwm_channel_rt_srf_prvi_para AS forecasts 

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.max_flows_srf_prvi_para AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND forecasts.streamflow = max_flows.maxflow_48hour_cms

-- Join in channels data to get reach metadata 
JOIN derived.channels_prvi as channels ON forecasts.feature_id = channels.feature_id

-- Join in recurrence flows to get high water threshold
JOIN derived.recurrence_flows_prvi as rf ON forecasts.feature_id = rf.feature_id

-- Join in arrival_time query results
JOIN arrival_time ON forecasts.feature_id = arrival_time.feature_id

WHERE round((forecasts.streamflow*35.315)::numeric, 2) >= rf.high_water_threshold
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers, channels.name, channels.strm_order, channels.huc6, channels.nwm_vers, rf.high_water_threshold, arrival_time.t_normal, max_flows.maxflow_48hour_cms, channels.geom