-- Synthetic Rating Curve Skill layer
DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation_extent_src_skill;

WITH rnr_max_flows AS (
    WITH waterbody_reaches AS (SELECT feature_id
						   FROM ingest.rnr_max_flows
						   WHERE waterbody_status IS NOT null
						   GROUP BY feature_id
						  )
    SELECT rnr.feature_id,
        MAX(streamflow) * 35.31467 as maxflow_5day_cfs
    FROM ingest.rnr_max_flows as rnr
    LEFT OUTER JOIN waterbody_reaches ON rnr.feature_id = waterbody_reaches.feature_id
    WHERE waterbody_reaches.feature_id IS NULL
    GROUP BY rnr.feature_id)
SELECT
    LPAD(urc.location_id::text, 8, '0') as usgs_site_code, 
    ht.feature_id,
    ht.feature_id::text as feature_id_str,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS ref_time,
    maxflow_5day_cfs,
    MIN(ht.elevation_ft) + ((maxflow_5day_cfs - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) as synth_interp_elevation_ft,
    MIN(urc.elevation_ft) + ((maxflow_5day_cfs - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as usgs_interp_elevation_ft,
    MIN(ht.elevation_ft) + ((maxflow_5day_cfs - MIN(ht.discharge_cfs)) * ((MAX(ht.next_elevation_ft) - MIN(ht.elevation_ft)) / (MAX(ht.next_discharge_cfs) - MIN(ht.discharge_cfs)))) -
    MIN(urc.elevation_ft) + ((maxflow_5day_cfs - MIN(urc.discharge_cfs)) * ((MAX(urc.next_elevation_ft) - MIN(urc.elevation_ft)) / (MAX(urc.next_discharge_cfs) - MIN(urc.discharge_cfs)))) as diff_ft,
    MIN(navd88_datum) as navd88_datum,
    MIN(stage) as usgs_stage,
    ST_TRANSFORM(MIN(gage.geo_point), 3857) as geom
INTO publish.rfc_based_5day_max_inundation_extent_src_skill
FROM rnr_max_flows AS rnr
JOIN derived.hydrotable_staggered AS ht ON ht.feature_id = rnr.feature_id AND rnr.maxflow_5day_cfs >= ht.discharge_cfs AND rnr.maxflow_5day_cfs <= ht.next_discharge_cfs
JOIN derived.usgs_rating_curves_staggered AS urc ON urc.location_id::text = ht.location_id AND rnr.maxflow_5day_cfs >= urc.discharge_cfs AND rnr.maxflow_5day_cfs <= urc.next_discharge_cfs
JOIN external.usgs_gage AS gage ON LPAD(gage.usgs_gage_id::text, 8, '0') = LPAD(ht.location_id::text, 8, '0')
GROUP BY urc.location_id, ht.feature_id, rnr.maxflow_5day_cfs;