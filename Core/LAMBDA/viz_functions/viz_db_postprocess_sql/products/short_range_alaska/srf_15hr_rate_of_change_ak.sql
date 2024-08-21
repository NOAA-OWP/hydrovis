DROP TABLE IF EXISTS publish.srf_15hr_rate_of_change_ak;

WITH roi AS (
    SELECT max_srf.feature_id, thresholds.high_water_threshold
    FROM cache.max_flows_srf_ak AS max_srf
    JOIN derived.recurrence_flows_ak thresholds ON max_srf.feature_id = thresholds.feature_id 
        AND max_srf.discharge_cfs >= thresholds.high_water_threshold
)
SELECT
    channels.feature_id,
    channels.feature_id::text as feature_id_str,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    'AK' as state,
    channels.geom,
    srf.forecast_hour,
    srf.nwm_vers,
    srf.reference_time,
    ana.discharge_cfs as current_flow,
    round((srf.streamflow * 35.315)::numeric, 2) as forecast_flow,
    roi.high_water_threshold,
    round(((srf.streamflow * 35.315) - ana.discharge_cfs)::numeric, 2) as change_cfs,
    round((((srf.streamflow * 35.315) - ana.discharge_cfs)*100/ana.discharge_cfs)::numeric, 2) as change_perc,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.srf_15hr_rate_of_change_ak
FROM ingest.nwm_channel_rt_srf_ak as srf
JOIN roi ON roi.feature_id = srf.feature_id
JOIN cache.max_flows_ana_past_hour_ak AS ana ON ana.feature_id = srf.feature_id
JOIN derived.channels_alaska as channels ON channels.feature_id = srf.feature_id
WHERE srf.forecast_hour IN (3,6,9,12,15)
ORDER BY forecast_hour, srf.feature_id;
