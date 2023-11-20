DROP TABLE IF EXISTS publish.stage_based_catfim_sites;

WITH fim_xwalk as (
	SELECT 
		stage.nws_station_id, 
		stage.nwm_feature_id, 
		NOT every(xwalk.feature_id IS NULL) as is_minimally_xwalked,
		every(xwalk.lake_id != -999) as is_all_lakes
	FROM cache.rfc_categorical_stages stage
	LEFT JOIN derived.fim4_featureid_crosswalk xwalk
		ON stage.trace_feature_id = xwalk.feature_id
	GROUP BY stage.nws_station_id, stage.nwm_feature_id
)

SELECT
    base.nws_station_id,
    base.nwm_feature_id,
    base.gage_id,
    base.goes_id,
    base.station_name,
    base.county_fips_code,
    base.county_name,
    base.state,
    base.wfo,
    base.rfc,
    base.hsa,
    base.huc,
    base.coord_accuracy_code,
    base.coord_meth_code,
    base.alt_accuracy_code,
    base.alt_meth_code,
    base.site_type,
    base.nws_vcs,
    base.nws_datum,
    base.nws_lat,
    base.nws_lon,
    base.nws_crs,
    base.usgs_vcs,
    base.usgs_datum,
    base.usgs_lat,
    base.usgs_lon,
    base.usgs_crs,
    base.dem_adj_elevation,
    base.dem_adj_elevation_ft,
    base.action_stage,
    base.minor_stage,
    base.moderate_stage,
    base.major_stage,
    base.record_stage,
    base.datum_adj_ft,
    base.adj_action_stage_m,
    base.adj_action_stage_ft,
    base.adj_minor_stage_m,
    base.adj_minor_stage_ft,
    base.adj_moderate_stage_m,
    base.adj_moderate_stage_ft,
    base.adj_major_stage_m,
    base.adj_major_stage_ft,
    base.adj_record_stage_m,
    base.adj_record_stage_ft,
    (
        base.status
        ||
        CASE
        WHEN fim_xwalk.is_all_lakes
        THEN 'site trace features all on waterbodies; '
        ELSE ''
        END 
        ||
        CASE
        WHEN NOT fim_xwalk.is_minimally_xwalked
        THEN 'site trace features fully missing from FIM crosswalk; '
        ELSE ''
        END
    ) AS status,
    CASE
		WHEN NOT fim_xwalk.is_minimally_xwalked OR fim_xwalk.is_all_lakes
		THEN FALSE
        ELSE base.mapped
    END as mapped,
    ST_TRANSFORM(station.geo_point, 3857) AS geom
INTO publish.stage_based_catfim_sites
FROM ingest.stage_based_catfim_sites AS base
LEFT JOIN external.nws_station AS station
    ON station.nws_station_id = base.nws_station_id
LEFT JOIN fim_xwalk
	ON base.nwm_feature_id = fim_xwalk.nwm_feature_id
    AND base.nws_station_id = fim_xwalk.nws_station_id;