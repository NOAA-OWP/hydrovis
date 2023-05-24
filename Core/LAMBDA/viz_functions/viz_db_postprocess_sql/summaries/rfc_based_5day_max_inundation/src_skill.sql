-- Synthetic Rating Curve Skill layer
DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation_src_skill;

-- Synthetic Rating Curve Skill layer
SELECT
    LPAD(urc.location_id::text, 8, '0') as usgs_site_code, 
    ht.feature_id,
    ht.feature_id::text as feature_id_str,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    rnr.streamflow as maxflow_5day_cfs,
    MIN(ht.elevation_ft) + ((rnr.streamflow - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) as synth_interp_elevation_ft,
    MIN(urc.elevation_ft) + ((rnr.streamflow - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as usgs_interp_elevation_ft,
    MIN(ht.elevation_ft) + ((rnr.streamflow - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) -
    MIN(urc.elevation_ft) + ((rnr.streamflow - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as diff_ft,
    MIN(navd88_datum) as navd88_datum,
    MIN(stage) as usgs_stage,
    ST_TRANSFORM(MIN(gage.geo_point), 3857) as geom
INTO publish.rfc_based_5day_max_inundation_src_skill
FROM publish.rfc_based_5day_max_streamflow AS rnr
JOIN derived.hydrotable_staggered AS ht ON ht.feature_id = rnr.feature_id AND rnr.streamflow >= ht.discharge_cfs AND rnr.streamflow <= ht.next_discharge_cfs
JOIN derived.usgs_rating_curves_staggered AS urc ON urc.location_id::text = ht.location_id AND rnr.streamflow >= urc.discharge_cfs AND rnr.streamflow <= urc.next_discharge_cfs
JOIN external.usgs_gage AS gage ON LPAD(gage.usgs_gage_id::text, 8, '0') = LPAD(ht.location_id::text, 8, '0')
WHERE rnr.is_waterbody = 'no' AND rnr.is_downstream_of_waterbody = 'no'
GROUP BY urc.location_id, ht.feature_id, rnr.streamflow;
