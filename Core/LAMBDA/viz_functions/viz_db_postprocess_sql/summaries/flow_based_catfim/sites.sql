DROP TABLE IF EXISTS publish.flow_based_catfim_sites;

WITH sites_base AS (
	SELECT DISTINCT ON (station.nws_station_id)
		station.nws_station_id,
		crosswalk.nwm_feature_id,
		crosswalk.gage_id,
		crosswalk.goes_id,
		station.name as station_name,
		station.state,
        station.county_fips_code,
		county.name AS county_name,
		station.wfo,
		station.rfc,
		station.hsa,
		station.huc,
		ST_TRANSFORM(station.geo_point, 3857) AS geom
	FROM external.nws_station AS station
	LEFT JOIN external.full_crosswalk_view AS crosswalk
		ON crosswalk.nws_station_id = station.nws_station_id
    LEFT JOIN external.fips_county AS county
		ON county.fips_county_code = station.county_fips_code
	WHERE station.rfc_defined_fcst_point is TRUE
),

fim_xwalk AS (
	SELECT 
		flow.nws_station_id, 
		flow.nwm_feature_id, 
		NOT every(xwalk.feature_id IS NULL) as is_minimally_xwalked,
		every(xwalk.lake_id != -999) as is_all_lakes
	FROM cache.rfc_categorical_flows flow
	LEFT JOIN derived.fim4_featureid_crosswalk xwalk
		ON flow.trace_feature_id = xwalk.feature_id
	GROUP BY flow.nws_station_id, flow.nwm_feature_id
)

SELECT DISTINCT
    base.nws_station_id,
    base.nwm_feature_id,
    base.gage_id,
    base.goes_id,
    base.station_name,
    base.state,
    base.county_fips_code,
    base.county_name,
    base.wfo,
    base.rfc,
    base.hsa,
    base.huc,
    base.geom,
    CASE
        WHEN restricted.nws_lid IS NOT NULL
        THEN 'restricted site: ' || restricted.restricted_reason || '; '
        ELSE ''
    END
    ||
    CASE
    WHEN base.nwm_feature_id IS NULL
    THEN 'station not crosswalked with NWM feature; '
    ELSE ''
    END 
    ||
	CASE
	WHEN fim_xwalk.is_all_lakes
	THEN 'site trace fully crosswalked with a lake; '
	ELSE ''
	END 
	||
	CASE
	WHEN NOT fim_xwalk.is_minimally_xwalked
	THEN 'site trace fully missing from FIM crosswalk; '
	ELSE ''
	END 
	||
    CASE
    WHEN base.nwm_feature_id IS NOT NULL AND action_flow_cfs IS NOT NULL AND minor_flow_cfs IS NOT NULL AND moderate_flow_cfs IS NOT NULL AND major_flow_cfs IS NOT NULL and record_flow_cfs IS NOT NULL
    THEN 'all threshold flows defined; '
    WHEN action_flow_cfs IS NULL AND minor_flow_cfs IS NULL AND moderate_flow_cfs IS NULL and major_flow_cfs IS NULL and record_flow_cfs IS NULL
    THEN 'all threshold flows undefined; '
    ELSE
        CASE
        WHEN action_flow_cfs IS NULL
        THEN 'action flow undefined; '
        ELSE ''
        END 
        ||
        CASE
        WHEN minor_flow_cfs IS NULL
        THEN 'minor flow undefined; '
        ELSE ''
        END
        ||
        CASE
        WHEN moderate_flow_cfs IS NULL
        THEN 'moderate flow undefined; '
        ELSE ''
        END
        ||
        CASE
        WHEN major_flow_cfs IS NULL
        THEN 'major flow undefined; '
        ELSE ''
        END
        ||
        CASE
        WHEN record_flow_cfs IS NULL
        THEN 'record flow undefined; '
        ELSE ''
        END
    END
    AS status,
    CASE
        WHEN base.nwm_feature_id IS NULL
        THEN 'no'
		WHEN NOT fim_xwalk.is_minimally_xwalked OR fim_xwalk.is_all_lakes
		THEN 'no'
        WHEN action_flow_cfs IS NULL AND minor_flow_cfs IS NULL AND moderate_flow_cfs IS NULL and major_flow_cfs IS NULL and record_flow_cfs IS NULL
        THEN 'no'
        WHEN restricted.nws_lid IS NOT NULL
        THEN 'no'
        ELSE 'yes'
    END as mapped
INTO publish.flow_based_catfim_sites
FROM sites_base as base
LEFT JOIN cache.rfc_categorical_flows flow
    ON flow.nws_station_id = base.nws_station_id
LEFT JOIN fim_xwalk
	ON fim_xwalk.nwm_feature_id = base.nwm_feature_id
	AND fim_xwalk.nws_station_id = base.nws_station_id
LEFT JOIN derived.ahps_restricted_sites restricted
	ON restricted.nws_lid = base.nws_station_id