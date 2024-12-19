DROP TABLE IF EXISTS publish.mrf_gfs_10day_peak_flow_arrival_time_alaska;

SELECT
    forecasts.feature_id,
    forecasts.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order::integer,
    min(forecasts.forecast_hour) AS peak_flow_arrival_hour,
    to_char(forecasts.reference_time::timestamp without time zone + INTERVAL '1 hour' * min(forecasts.forecast_hour), 'YYYY-MM-DD HH24:MI:SS UTC') AS peak_flow_arrival_time,
    channels.huc6,
    'AK' as state,
    forecasts.nwm_vers,
    forecasts.reference_time,
    max_flows.discharge_cfs AS max_flow_cfs,
    rf.high_water_threshold,
    arrival_time.below_bank_return_hour,
    arrival_time.below_bank_return_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
   
INTO publish.mrf_gfs_10day_peak_flow_arrival_time_alaska
FROM ingest.nwm_channel_rt_mrf_gfs_ak_mem1 AS forecasts

-- Join in max flows on max streamflow to only get peak flows
JOIN cache.max_flows_mrf_gfs_10day_ak AS max_flows
    ON forecasts.feature_id = max_flows.feature_id AND round((forecasts.streamflow*35.315)::numeric, 2) = max_flows.discharge_cfs

-- Join in channels data to get reach metadata and geometry
JOIN derived.channels_ak as channels ON forecasts.feature_id = channels.feature_id::bigint

-- Join in high water arrival time for return time (the yaml config file ensures that arrival time finishes first for this, but we'll join on reference_time as well to ensure)
JOIN publish.mrf_gfs_10day_high_water_arrival_time_ak AS arrival_time ON forecasts.feature_id = arrival_time.feature_id and forecasts.reference_time = arrival_time.reference_time

WHERE round((forecasts.streamflow*35.315)::numeric, 2) >= rf.high_water_threshold
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers, forecasts.streamflow, max_flows.discharge_cfs, arrival_time.below_bank_return_hour, channels.geom, channels.strm_order, channels.name, channels.huc6;