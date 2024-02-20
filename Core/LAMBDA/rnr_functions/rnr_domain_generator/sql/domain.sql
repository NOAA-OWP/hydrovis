----------------------------------------------------------------
----------------------------------------------------------------
---------------- MAKE COPY OF RFC_MAX_FOREACST -----------------
----------------------------------------------------------------
----------------------------------------------------------------
-- This copy is necessary to ensure that the data (e.g. max_status)
-- stays the same between when it's executed here and then again
-- from rfc_based_5day_max_streamflow.sql
DROP TABLE IF EXISTS rnr.rfc_max_forecast_copy;
SELECT * INTO rnr.rfc_max_forecast_copy FROM publish.rfc_max_forecast;

----------------------------------------------------------------
----------------------------------------------------------------
------------------ GET ALL RELEVANT FORECASTS ------------------
----------------------------------------------------------------
----------------------------------------------------------------
DROP TABLE IF EXISTS rnr.domain_forecasts;

WITH

flood_forecasts AS (
	SELECT DISTINCT ON (
		fcst.lid, 
		fcst.pe, 
		fcst.d, 
		fcst.ts, 
		fcst.e, 
		fcst.p, 
		fcst.product_time, 
		fcst.start_time, 
		fcst.valid_time
	)
		fcst.lid,
		fcst.product_time,
		fcst.valid_time,
		fcst.pe,
		fcst.ts,
		fcst.value,
		fcst.units
	FROM wrds_rfcfcst.last_forecast_view fcst
	JOIN rnr.rfc_max_forecast_copy service
 		ON service.nws_lid = fcst.lid AND service.pe = fcst.pe 
 		AND service.ts = fcst.ts  AND service.issued_time::timestamp with time zone = fcst.product_time
		AND service.initial_flood_value_timestep::timestamp with time zone <= (SELECT DISTINCT reference_time::timestamp with time zone + INTERVAL '5 days' FROM ingest.nwm_channel_rt_ana)
	ORDER BY 
		fcst.lid, 
		fcst.pe, 
		fcst.d, 
		fcst.ts, 
		fcst.e, 
		fcst.p, 
		fcst.product_time DESC, 
		fcst.start_time, 
		fcst.valid_time, 
		fcst.generation_time DESC
),

native_flow_forecasts AS (
	SELECT 
		*
	FROM flood_forecasts
	WHERE pe LIKE 'Q%'
),

native_stage_forecasts AS (
	SELECT 
		*
	FROM flood_forecasts
	WHERE pe LIKE 'H%'
),

flow_fcsts_from_usgs_rating_curve AS (
	SELECT 
		f.lid,
		f.product_time,
		f.valid_time,
		curve.flow + ((curve.next_higher_point_flow - curve.flow) / (curve.next_higher_point_stage - curve.stage) * (f.value - curve.stage)) as flow_from_curve
	FROM native_stage_forecasts f
	JOIN rnr.staggered_curves_usgs curve
		ON curve.nws_station_id = f.lid
		AND (curve.stage = f.value 
			OR (curve.stage < f.value 
				AND curve.next_higher_point_stage > f.value))
),

flow_fcsts_from_nrldb_rating_curve AS (
	SELECT 
		f.lid,
		f.product_time,
		f.valid_time,
		curve.flow + ((curve.next_higher_point_flow - curve.flow) / (curve.next_higher_point_stage - curve.stage) * (f.value - curve.stage)) as flow_from_curve
	FROM native_stage_forecasts f
	JOIN rnr.staggered_curves_nrldb curve
		ON curve.nws_station_id = f.lid
		AND (curve.stage = f.value 
			OR (curve.stage < f.value 
				AND curve.next_higher_point_stage > f.value))
	WHERE lid NOT IN (SELECT DISTINCT lid FROM flow_fcsts_from_usgs_rating_curve)
),

domain_forecasts AS (
	SELECT
		lid,
		product_time,
		valid_time,
		ROUND(flow_from_curve::numeric) as flow_cfs,
		ROUND((flow_from_curve * 0.028316847)::numeric) as flow_cms,
		'USGS' as rating_curve_source
	FROM flow_fcsts_from_usgs_rating_curve

	UNION

	SELECT
		lid,
		product_time,
		valid_time,
		ROUND(flow_from_curve::numeric) as flow_cfs,
		ROUND((flow_from_curve * 0.028316847)::numeric) as flow_cms,
		'NRLDB' as rating_curve_source
	FROM flow_fcsts_from_nrldb_rating_curve

	UNION

	SELECT
		lid,
		product_time,
		valid_time,
		ROUND(value::numeric) as flow_cfs,
		ROUND((value * 0.028316847)::numeric) as flow_cms,
		'None' as rating_curve_source
	FROM native_flow_forecasts
)

SELECT * INTO rnr.domain_forecasts FROM domain_forecasts;

-------------------------------------------------------
-------------------------------------------------------
------------- CREATE RNR DOMAIN ROUTLINK  -------------
-------------------------------------------------------
-------------------------------------------------------

DROP TABLE IF EXISTS rnr.domain_routelink;

WITH RECURSIVE 

flood_lids AS (
	SELECT DISTINCT lid FROM rnr.domain_forecasts
),

flood_xwalk AS (
	SELECT
        flood.lid, 
        xwalk.nwm_feature_id
    FROM flood_lids flood
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
ORDER BY reference_time DESC LIMIT 1;