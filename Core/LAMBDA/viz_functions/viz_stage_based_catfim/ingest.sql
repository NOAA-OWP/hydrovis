DROP TABLE IF EXISTS ingest.stage_based_catfim_sites;

WITH

action_stage AS (
	SELECT location_id, rating_source, action_stage as stage, 'action' as stage_category FROM external.threshold WHERE action_stage IS NOT null AND rating_source = 'NONE'
),

minor_stage AS (
	SELECT location_id, rating_source, minor_stage as stage, 'minor' as stage_category FROM external.threshold WHERE minor_stage IS NOT null AND rating_source = 'NONE'
),

moderate_stage AS (
	SELECT location_id, rating_source, moderate_stage as stage, 'moderate' as stage_category FROM external.threshold WHERE moderate_stage IS NOT null AND rating_source = 'NONE'
),

major_stage AS (
	SELECT location_id, rating_source, major_stage as stage, 'major' as stage_category FROM external.threshold WHERE major_stage IS NOT null AND rating_source = 'NONE'
),

record_stage AS (
	SELECT location_id, rating_source, record_stage as stage, 'record' as stage_category FROM external.threshold WHERE record_stage IS NOT null AND rating_source = 'NONE'
),

/* COMBINED STAGES */
all_categorical_stages AS (
	SELECT * FROM action_stage
	UNION
	SELECT * FROM minor_stage
	UNION
	SELECT * FROM moderate_stage
	UNION
	SELECT * FROM major_stage
	UNION
	SELECT * FROM record_stage
),

sites_with_status AS (
	SELECT DISTINCT ON (station.nws_station_id)
		station.nws_station_id,
		xwalk.gage_id, 
		xwalk.nwm_feature_id, 
		xwalk.goes_id, 
		station.name,
		station.state,
		station.wfo,
		station.rfc,
		station.hsa,
		station.huc,
		station.vertical_datum_name as nws_vcs,
		station.zero_datum as nws_datum,
        station.latitude as nws_lat,
        station.longitude as nws_lon,
        station.horizontal_datum_name as nws_crs,
		station.county_fips_code,
		gage.coord_accuracy_code,
		gage.coord_meth_code,
		gage.alt_accuracy_code,
		gage.alt_meth_code,
		gage.site_type,
		gage.altitude as usgs_datum,
        gage.alt_datum_code as usgs_vcs,
        gage.latitude as usgs_lat,
        gage.longitude as usgs_lon,
        gage.dec_coord_datum_code as usgs_crs,
        elev.dem_adj_elevation,
		action.stage as action_stage,
		minor.stage as minor_stage,
		moderate.stage as moderate_stage,
		major.stage as major_stage,
		record.stage as record_stage,
		-- -- IF UNCOMMENTING THIS SECTION, ALSO COMMENT LINE 187
		-- CASE
		-- 	WHEN station.rfc_defined_fcst_point IS FALSE
		-- 	THEN 'site is not an official RFC-defined forecast point in the WRDS database; '
		-- 	ELSE ''
		-- END
		-- ||
        CASE
            WHEN ABS(elev.dem_adj_elevation - (gage.altitude * 0.3048)) > 10
            THEN 'large discrepancy in elevation estimates from gage and HAND; '
            ELSE ''
		END
		||
		CASE
            WHEN gage.altitude IS NULL AND station.zero_datum IS NULL
            THEN 'missing datum; '
            ELSE ''
		END
		||
        CASE
            WHEN elev.dem_adj_elevation IS NOT NULL
            THEN ''
            ELSE 'missing dem_adj_elevation; '
		END
		||
		CASE
			WHEN coord_accuracy_code IN ('H','1','5','S','R','B','C','D','E')
			THEN ''
			ELSE 'invalid coordinate accuracy code; '
		END
		||
		CASE 
			WHEN coord_meth_code IN ('C','D','W','X','Y','Z','N','M','L','G','R','F','S')
			THEN ''
			ELSE 'invalid coordinate method code; '
		END
		||
		CASE
			WHEN alt_accuracy_code <= 1.0
			THEN ''
			ELSE 'invalid altitude accuracy code; '
		END
		||
		CASE 
			WHEN alt_meth_code IN ('A','D','F','I','J','L','N','R','W','X','Y','Z')
			THEN ''
			ELSE 'invalid altitude method code; '
		END
		||
		CASE
			WHEN site_type = 'ST'
			THEN ''
			ELSE 'invalid site type; '
		END 
		||
		CASE
			WHEN action.stage IS NULL and minor.stage IS NULL and moderate.stage IS NULL and major.stage IS NULL and record.stage IS NULL
			THEN 'all threshold stages undefined; '
			WHEN action.stage IS NOT NULL and minor.stage IS NOT NULL and moderate.stage IS NOT NULL and major.stage IS NOT NULL and record.stage IS NOT NULL
			THEN 'all threshold stages defined; '
			ELSE
			CASE
				WHEN action.stage IS NULL
				THEN 'action stage undefined; '
				ELSE ''
			END
			||
			CASE
				WHEN minor.stage IS NULL
				THEN 'minor stage undefined; '
				ELSE ''
			END
			||
				CASE
				WHEN moderate.stage IS NULL
				THEN 'moderate stage undefined; '
				ELSE ''
			END
			||
				CASE
				WHEN major.stage IS NULL
				THEN 'major stage undefined; '
				ELSE ''
			END
			||
				CASE
				WHEN record.stage IS NULL
				THEN 'record stage undefined; '
				ELSE ''
			END
		END as status
	FROM external.nws_station AS station
	LEFT JOIN external.full_crosswalk_view AS xwalk
		ON station.nws_station_id = xwalk.nws_station_id
		AND xwalk.location_nwm_crosswalk_dataset_id = '1.2'
		AND xwalk.nws_usgs_crosswalk_dataset_id = '2.0'
	LEFT JOIN external.usgs_gage AS gage
		ON xwalk.gage_id = gage.usgs_gage_id
	LEFT JOIN all_categorical_stages AS action
		ON action.location_id = station.nws_station_id
		AND action.stage_category = 'action'
	LEFT JOIN all_categorical_stages AS minor
		ON minor.location_id = station.nws_station_id
		AND minor.stage_category = 'minor'
	LEFT JOIN all_categorical_stages AS moderate
		ON moderate.location_id = station.nws_station_id
		AND moderate.stage_category = 'moderate'
	LEFT JOIN all_categorical_stages AS major
		ON major.location_id = station.nws_station_id
		AND major.stage_category = 'major'
	LEFT JOIN all_categorical_stages AS record
		ON record.location_id = station.nws_station_id
		AND record.stage_category = 'record'
    LEFT JOIN (SELECT DISTINCT ON (nws_lid) * FROM derived.usgs_elev_table ORDER BY nws_lid, levpa_id DESC) AS elev
        ON elev.nws_lid = station.nws_station_id
	WHERE rfc_defined_fcst_point IS TRUE
)

-- Create stage_based_catfim_sites table in ingest schema - it can be pulled directly from here
-- into publish.stag_based_catfim_sites during product summaries step in the pipeline
SELECT
	site.nws_station_id,
	site.nwm_feature_id,
	site.gage_id,
	site.goes_id,
	site.name AS station_name,
	site.county_fips_code,
	county.name as county_name,
	site.state,
	site.wfo,
	site.rfc,
	site.hsa,
	site.huc,
	site.coord_accuracy_code,
	site.coord_meth_code,
	site.alt_accuracy_code,
	site.alt_meth_code,
	site.site_type,
    site.nws_vcs,
    site.nws_datum,
    site.nws_lat,
    site.nws_lon,
    site.nws_crs,
    site.usgs_vcs,
    site.usgs_datum,
    site.usgs_lat,
    site.usgs_lon,
    site.usgs_crs,
    site.dem_adj_elevation,
	site.dem_adj_elevation * 3.28084 AS dem_adj_elevation_ft,
	site.action_stage,
	site.minor_stage,
	site.moderate_stage,
	site.major_stage,
	site.record_stage,
	site.status,
	site.status NOT LIKE '%invalid%' 
        AND site.status NOT LIKE '%all threshold stages undefined%' 
        AND site.status NOT LIKE '%missing%'
        AND site.status NOT LIKE '%discrepancy%'
		AND site.status NOT LIKE '%not an official%' AS mapped
INTO ingest.stage_based_catfim_sites
FROM sites_with_status site
LEFT JOIN external.fips_county AS county
	ON county.fips_county_code = site.county_fips_code