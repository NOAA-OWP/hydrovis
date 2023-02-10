DROP TABLE IF EXISTS publish.mrf_nbm_peak_flow_arrival_time_para;

WITH arrival_time AS(
    SELECT 
           forecasts.feature_id, 
           max(forecasts.forecast_hour)+1 AS t_normal
    FROM ingest.nwm_channel_rt_mrf_nbm_para AS forecasts
    JOIN derived.recurrence_flows_conus thresholds ON forecasts.feature_id = thresholds.feature_id
    WHERE (forecasts.streamflow * 35.315::double precision) >= thresholds.high_water_threshold
    GROUP BY forecasts.feature_id
)

SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    channels.name,
    (channels.strm_order)::integer,
    min(forecasts.forecast_hour) AS peak_flow_arrival_hour,
    channels.huc6,
    forecasts.nwm_vers,
    forecasts.reference_time,
    max_flows.maxflow_10day_cfs AS max_flow_cfs,
    rf.high_water_threshold,
    arrival_time.t_normal AS below_bank_return_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
   
INTO publish.mrf_nbm_peak_flow_arrival_time_para
FROM ingest.nwm_channel_rt_mrf_nbm_para AS forecasts

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.mrf_nbm_max_flows_para AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND round((forecasts.streamflow*35.315)::numeric, 2) = max_flows.maxflow_10day_cfs

-- Join in channels data to get reach metadata and geometry
JOIN derived.channels_conus as channels ON forecasts.feature_id = channels.feature_id

-- Join in recurrence flows to get high water threshold
JOIN derived.recurrence_flows_conus as rf ON forecasts.feature_id = rf.feature_id

-- Join in arrival_time 
JOIN arrival_time ON forecasts.feature_id = arrival_time.feature_id

WHERE round((forecasts.streamflow*35.315)::numeric, 2) >= rf.high_water_threshold
GROUP BY forecasts.feature_id, forecasts.streamflow, channels.name, channels.strm_order, channels.huc6, channels.nwm_vers, rf.high_water_threshold, max_flows.maxflow_10day_cfs, arrival_time.t_normal, channels.geom;