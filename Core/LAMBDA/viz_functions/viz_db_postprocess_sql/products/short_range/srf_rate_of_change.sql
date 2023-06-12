DROP TABLE IF EXISTS publish.srf_rate_of_change;

WITH roi AS (
    SELECT max_srf.feature_id, thresholds.high_water_threshold
    FROM cache.max_flows_srf AS max_srf
    JOIN derived.recurrence_flows_conus thresholds ON max_srf.feature_id = thresholds.feature_id 
        AND max_srf.maxflow_18hour_cfs >= thresholds.high_water_threshold
)
SELECT
    channels.feature_id,
    channels.feature_id::text as feature_id_str,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    channels.state,
    channels.geom,
    srf.forecast_hour,
    srf.nwm_vers,
    srf.reference_time,
    ana.maxflow_1hour_cfs as current_flow,
    round((srf.streamflow * 35.315)::numeric, 2) as forecast_flow,
    roi.high_water_threshold,
    round(((srf.streamflow * 35.315) - ana.maxflow_1hour_cfs)::numeric, 2) as change_cfs,
    round((((srf.streamflow * 35.315) - ana.maxflow_1hour_cfs)*100/ana.maxflow_1hour_cfs)::numeric, 2) as change_perc,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.srf_rate_of_change
FROM ingest.nwm_channel_rt_srf as srf
JOIN roi ON roi.feature_id = srf.feature_id
JOIN cache.max_flows_ana_past_hour AS ana ON ana.feature_id = srf.feature_id
JOIN derived.channels_conus as channels ON channels.feature_id = srf.feature_id
WHERE srf.forecast_hour IN (3,6,9,12,15,18)
ORDER BY forecast_hour, srf.feature_id;
