-- Synthetic Rating Curve Skill layers
DROP TABLE IF EXISTS publish.mrf_gfs_max_inundation_5day_src_skill;

SELECT
    LPAD(urc.location_id::text, 8, '0') as usgs_site_code, 
    ht.feature_id,
    ht.feature_id::text as feature_id_str,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    maxflow_5day_cfs,
    MIN(ht.elevation_ft) + ((maxflow_5day_cfs - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) as synth_interp_elevation_ft,
    MIN(urc.elevation_ft) + ((maxflow_5day_cfs - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as usgs_interp_elevation_ft,
    MIN(ht.elevation_ft) + ((maxflow_5day_cfs - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) -
    MIN(urc.elevation_ft) + ((maxflow_5day_cfs - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as diff_ft,
    MIN(navd88_datum) as navd88_datum,
    MIN(stage) as usgs_stage,
    ST_TRANSFORM(MIN(gage.geo_point), 3857) as geom
INTO publish.mrf_gfs_max_inundation_5day_src_skill
FROM cache.max_flows_mrf_gfs AS mrf
JOIN derived.recurrence_flows_conus thresholds ON mrf.feature_id = thresholds.feature_id AND mrf.maxflow_5day_cfs >= thresholds.high_water_threshold
JOIN derived.hydrotable_staggered AS ht ON ht.feature_id = mrf.feature_id AND mrf.maxflow_5day_cfs >= ht.discharge_cfs AND mrf.maxflow_5day_cfs <= ht.next_discharge_cfs
JOIN derived.usgs_rating_curves_staggered AS urc ON urc.location_id::text = ht.location_id AND mrf.maxflow_5day_cfs >= urc.discharge_cfs AND mrf.maxflow_5day_cfs <= urc.next_discharge_cfs
JOIN external.usgs_gage AS gage ON LPAD(gage.usgs_gage_id::text, 8, '0') = LPAD(ht.location_id::text, 8, '0')
GROUP BY urc.location_id, ht.feature_id, maxflow_5day_cfs;