DROP TABLE IF EXISTS publish.mrf_nbm_5day_max_high_flow_magnitude_public;

SELECT
    feature_id_str,
    strm_order,
    name,
    huc6,
    state,
    nwm_vers,
    reference_time,
    maxflow_5day_cfs,
    recur_cat_5day,
    high_water_threshold,
    flow_2yr,
    flow_5yr,
    flow_10yr,
    flow_25yr,
    flow_50yr,
    update_time,
    geom
INTO publish.mrf_nbm_5day_max_high_flow_magnitude_public
FROM publish.mrf_nbm_10day_max_high_flow_magnitude AS main
JOIN derived.channels_conus AS channels ON main.feature_id = channels.feature_id
WHERE public_fim_domain = True;

INSERT INTO publish.mrf_nbm_5day_max_high_flow_magnitude_public (
    reference_time, 
    update_time
) VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);