----------------------------------------------------------------
----------------------------------------------------------------
-- GET ALL FLOW FORECASTS (NATIVE AND RATING-CURVE CONVERTED) --
----------------------------------------------------------------
----------------------------------------------------------------

DROP TABLE IF EXISTS rnr.temporal_domain_flow_forecasts;

WITH 

ref_time AS (
	SELECT reference_time
	FROM ingest.nwm_channel_rt_ana
	ORDER BY reference_time DESC LIMIT 1
),

temporal_domain_forecasts AS (
	SELECT 
		lid, 
		pe,
		pe_priority,
		product_time,
		valid_time,
	CASE 
		WHEN units = 'KCFS' 
		THEN value * 1000
		ELSE value
	END as value,
	CASE
		WHEN units = 'KCFS'
		THEN 'CFS'
		ELSE units
	END AS units
FROM wrds_rfcfcst.last_generated_forecast_view
WHERE product_time >= (SELECT reference_time::timestamp with time zone - INTERVAL '24 hours' FROM ref_time)
	AND (pe LIKE 'H%' OR pe LIKE 'Q%')
	AND pe != 'QI'
	AND value > 0
	AND valid_time >= (SELECT reference_time::timestamp with time zone FROM ref_time)
	AND valid_time <= (SELECT reference_time::timestamp with time zone + INTERVAL '120 hours' FROM ref_time)
),

native_flood_forecasts AS (
	SELECT 
		*
	FROM temporal_domain_forecasts
	WHERE pe LIKE 'Q%'
),

native_stage_flood_fcsts AS (
	SELECT 
		*
	FROM temporal_domain_forecasts
	WHERE pe LIKE 'H%'
	AND lid NOT IN (SELECT lid FROM native_flood_forecasts)
),

flow_fcsts_from_rating_curve AS (
	SELECT 
		f.lid,
		f.product_time,
		f.valid_time,
		curve.flow + ((curve.next_higher_point_flow - curve.flow) / (curve.next_higher_point_stage - curve.stage) * (f.value - curve.stage)) as flow_from_curve,
		f.units, -- CFS
		f.value as orig_stage,
		curve.flow as lower_point_flow,
		curve.next_higher_point_flow as higher_point_flow,
		curve.stage as lower_point_stage,
		curve.next_higher_point_stage as higher_point_stage
	FROM native_stage_flood_fcsts f
	JOIN (SELECT DISTINCT ON (nws_station_id) * FROM rnr.nwm_crosswalk WHERE gage_id IS NOT NULL) as xwalk
		ON xwalk.nws_station_id = f.lid
	JOIN external.rating rating
		ON rating.location_id = xwalk.gage_id
	JOIN rnr.staggered_curves curve
		ON curve.rating_id = rating.rating_id
		AND (curve.stage = f.value 
			OR (curve.stage < f.value 
				AND curve.next_higher_point_stage > f.value))
),

all_flow_forecasts AS (
	SELECT
		lid,
		product_time,
		valid_time,
		flow_from_curve as flow_cfs,
		flow_from_curve * 0.028316847 as flow_cms
	FROM flow_fcsts_from_rating_curve

	UNION

	SELECT
		lid,
		product_time,
		valid_time,
		value as flow_cfs,
		value * 0.028316847 as flow_cms
	FROM native_flood_forecasts
	WHERE pe LIKE 'Q%'
)

SELECT 
    *
INTO rnr.temporal_domain_flow_forecasts
FROM all_flow_forecasts;

-------------------------------------------------------
-------------------------------------------------------
------------- CREATE RNR DOMAIN ROUTLINK  -------------
-------------------------------------------------------
-------------------------------------------------------

DROP TABLE IF EXISTS rnr.domain_routelink;

WITH RECURSIVE 

ref_time AS (
	SELECT reference_time
	FROM ingest.nwm_channel_rt_ana
	ORDER BY reference_time DESC LIMIT 1	
),

max_flow AS (
	SELECT 
		lid, 
		MAX(flow_cfs) as max_flow_cfs
	FROM rnr.temporal_domain_flow_forecasts
	GROUP BY lid
),

max_stage AS (
	SELECT DISTINCT ON (lid)
		lid, 
		MAX(value) as max_stage_ft
	FROM wrds_rfcfcst.last_generated_forecast_view
	WHERE product_time >= (SELECT reference_time::timestamp with time zone - INTERVAL '24 hours' FROM ref_time)
		AND (pe LIKE 'H%' OR pe LIKE 'Q%')
		AND value > 0
		AND valid_time >= (SELECT reference_time::timestamp with time zone FROM ref_time)
		AND valid_time <= (SELECT reference_time::timestamp with time zone + INTERVAL '120 hours' FROM ref_time)
	GROUP BY lid, pe, pe_priority, units
	ORDER BY lid, pe_priority
),

native_threshold AS (
	SELECT DISTINCT ON (location_id)
		location_id as nws_station_id,
		rating_source,
		action_stage,
		minor_stage,
		moderate_stage,
		major_stage,
		record_stage,
		action_flow,
		minor_flow,
		moderate_flow,
		major_flow,
		record_flow
	FROM external.threshold
	WHERE rating_source = 'NONE'
), usgs_threshold AS (
	SELECT DISTINCT ON (location_id) 
		location_id as nws_station_id,
		rating_source,
		action_stage,
		minor_stage,
		moderate_stage,
		major_stage,
		record_stage,
		action_flow_calc as action_flow,
		minor_flow_calc as minor_flow,
		moderate_flow_calc as moderate_flow,
		major_flow_calc as major_flow,
		record_flow_calc as record_flow
	FROM external.threshold
	WHERE rating_source = 'USGS Rating Depot' AND location_id NOT IN (SELECT nws_station_id FROM native_threshold)
), nrldb_threshold AS (
	SELECT DISTINCT ON (location_id)
		location_id as nws_station_id,
		rating_source,
		action_stage,
		minor_stage,
		moderate_stage,
		major_stage,
		record_stage,
		action_flow_calc as action_flow,
		minor_flow_calc as minor_flow,
		moderate_flow_calc as moderate_flow,
		major_flow_calc as major_flow,
		record_flow_calc as record_flow
	FROM external.threshold
	WHERE rating_source = 'NRLDB' AND location_id NOT IN (SELECT nws_station_id FROM native_threshold UNION SELECT nws_station_id FROM usgs_threshold)
), threshold AS (
	SELECT * FROM native_threshold
	UNION
	SELECT * FROM usgs_threshold
	UNION
	SELECT * FROM nrldb_threshold
),

max_status_flow AS (
	SELECT 
		lid,
		CASE
			WHEN th.major_flow IS NOT NULL AND mf.max_flow_cfs >= th.major_flow
			THEN 'major'
			WHEN th.moderate_flow IS NOT NULL AND mf.max_flow_cfs >= th.moderate_flow
			THEN 'moderate'
			WHEN th.minor_flow IS NOT NULL AND mf.max_flow_cfs >= th.minor_flow
			THEN 'minor'
			WHEN th.action_flow IS NOT NULL AND mf.max_flow_cfs >= th.action_flow
			THEN 'action'
			WHEN th.major_flow IS NULL AND th.moderate_flow IS NULL AND th.minor_flow IS NULL AND th.action_flow IS NULL
			THEN CASE 
					WHEN th.record_flow IS NOT NULL AND mf.max_flow_cfs >= th.record_flow
					THEN 'record'
					ELSE 'thresholds undefined'
				 END
			ELSE 'no_flooding'
		END as status
	FROM max_flow AS mf
	LEFT JOIN threshold AS th
		ON th.nws_station_id = mf.lid
),

max_status_stage AS (
	SELECT 
		lid,
		CASE
			WHEN th.major_stage IS NOT NULL AND mf.max_stage_ft >= th.major_stage
			THEN 'major'
			WHEN th.moderate_stage IS NOT NULL AND mf.max_stage_ft >= th.moderate_stage
			THEN 'moderate'
			WHEN th.minor_stage IS NOT NULL AND mf.max_stage_ft >= th.minor_stage
			THEN 'minor'
			WHEN th.action_stage IS NOT NULL AND mf.max_stage_ft >= th.action_stage
			THEN 'action'
			WHEN th.major_stage IS NULL AND th.moderate_stage IS NULL AND th.minor_stage IS NULL AND th.action_stage IS NULL
			THEN CASE 
					WHEN th.record_stage IS NOT NULL AND mf.max_stage_ft >= th.record_stage
					THEN 'record'
					ELSE 'thresholds undefined'
				 END
			ELSE 'no_flooding'
		END as status
	FROM max_stage AS mf
	LEFT JOIN threshold AS th
		ON th.nws_station_id = mf.lid
),

flood_flow_lid AS (
	SELECT lid
    FROM max_status_flow
	WHERE status in ('action', 'minor', 'moderate', 'major', 'record')
),

flood_stage_lid AS (
	SELECT lid
	FROM max_status_stage
	WHERE status in ('action', 'minor', 'moderate', 'major', 'record')
),

flood_lid AS (
	SELECT
		lid
	FROM flood_flow_lid

	UNION

	SELECT
		lid
	FROM flood_stage_lid
	WHERE lid NOT IN (SELECT lid FROM flood_flow_lid)
		AND lid IN (SELECT lid FROM max_flow)
),

flood_xwalk AS (
    SELECT 
        flood.lid, 
        xwalk.nwm_feature_id
    FROM flood_lid flood
    JOIN rnr.nwm_crosswalk AS xwalk
		ON xwalk.nws_station_id = flood.lid
	WHERE xwalk.nws_station_id IS NOT NULL AND xwalk.nwm_feature_id IS NOT NULL
),

root_trace_feature AS (
	SELECT rl.link, rl.to
	FROM flood_xwalk xwalk
	JOIN rnr.nwm_routelink rl
	    ON rl.link = xwalk.nwm_feature_id
),

downstream_trace AS (
    SELECT 
		"link",
		"to"
	FROM root_trace_feature
	UNION
	SELECT 
		iter.link,
		iter.to
	FROM rnr.nwm_routelink iter
	JOIN downstream_trace root
		ON iter.link = root.to
)

SELECT rl.*
INTO rnr.domain_routelink
FROM rnr.nwm_routelink rl
JOIN downstream_trace tr
	ON tr.link = rl.link
ORDER BY order_index;

-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------

DROP TABLE IF EXISTS rnr.domain_forecasts;

SELECT DISTINCT ON (fcst.*)
	fcst.*
INTO rnr.domain_forecasts
FROM rnr.temporal_domain_flow_forecasts fcst
JOIN rnr.nwm_crosswalk xwalk
	ON xwalk.nws_station_id = fcst.lid
JOIN rnr.domain_routelink rl
	ON rl.link = xwalk.nwm_feature_id;

-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------
-------------------------------------------------------

DROP TABLE IF EXISTS rnr.domain_crosswalk;

WITH domain_lids AS (
	SELECT DISTINCT
		lid
	FROM rnr.domain_forecasts
),

base_xwalk AS (
    SELECT DISTINCT ON (xwalk.nws_station_id)
        xwalk.nws_station_id, xwalk.nwm_feature_id, xwalk.gage_id
    FROM domain_lids domain
	JOIN rnr.nwm_crosswalk xwalk
		ON xwalk.nws_station_id = domain.lid
	WHERE xwalk.nwm_feature_id IS NOT NULL
),

gen_hydro_id AS (
	SELECT
		nws_station_id,
		ROW_NUMBER() OVER ( ORDER BY base.nws_station_id) as hydro_id
	FROM base_xwalk base
	WHERE gage_id IS NULL
)

SELECT
	base.nws_station_id, 
	base.gage_id, 
	base.nwm_feature_id,
	CASE 
		WHEN base.gage_id IS NULL
		THEN LPAD(gen_hydro_id.hydro_id::text, 8, '0')
		ELSE base.gage_id
	END as hydro_id
INTO rnr.domain_crosswalk
FROM base_xwalk base
LEFT JOIN gen_hydro_id
	ON gen_hydro_id.nws_station_id = base.nws_station_id
ORDER BY base.nws_station_id;

-------------------------------------------------------------
-------------------------------------------------------------
------------ RETURN LATEST ANA REFERENCE TIME ---------------
-------------------------------------------------------------
-------------------------------------------------------------
SELECT reference_time
FROM ingest.nwm_channel_rt_ana
ORDER BY reference_time DESC LIMIT 1