DROP TABLE IF EXISTS publish.rfc_max_forecast;

WITH

latest_forecast AS (
	SELECT DISTINCT ON (
		lid, 
		pe, 
		d, 
		ts, 
		e, 
		p, 
		product_time, 
		start_time, 
		valid_time
	)
		lid,
		distributor AS distributor_name,
		producer_name,
		generation_time,
		product_time,
		valid_time,
		pe,
		d,
		ts,
		e,
		p,
		pe_priority,
		value,
		units
	FROM wrds_rfcfcst.last_forecast_view
	ORDER BY 
		last_forecast_view.lid, 
		last_forecast_view.pe, 
		last_forecast_view.d, 
		last_forecast_view.ts, 
		last_forecast_view.e, 
		last_forecast_view.p, 
		last_forecast_view.product_time DESC, 
		last_forecast_view.start_time, 
		last_forecast_view.valid_time, 
		last_forecast_view.generation_time DESC
),

considerable_forecast_metadata AS (
	SELECT DISTINCT ON (lid, units)
		lid, pe, ts, product_time, units
	FROM latest_forecast
	WHERE (pe LIKE 'H%' OR pe LIKE 'Q%')
		AND pe_priority = 1
		AND product_time >= NOW() - INTERVAL '48 hours'
		AND valid_time >= NOW()
		AND value > -999
	ORDER BY lid, units, ts::forecast_ts
),

relevant_forecasts AS (
	SELECT 
		main.lid, 
		main.pe,
		main.ts,
		main.generation_time,
		main.product_time,
		main.valid_time,
	CASE 
		WHEN main.units = 'KCFS' 
		THEN value * 1000
		ELSE value
	END as value,
	CASE
		WHEN main.units = 'KCFS'
		THEN 'CFS'
		ELSE main.units
	END AS units
	FROM latest_forecast main
	JOIN considerable_forecast_metadata meta
		ON meta.lid = main.lid AND meta.pe = main.pe AND meta.ts = main.ts AND meta.product_time = main.product_time
	WHERE valid_time >= NOW()
	ORDER BY
		lid, 
		pe,
		generation_time,
		product_time,
		valid_time
),

relevant_thresholds AS (
	SELECT
		lid,
		CASE
			WHEN units = 'KCFS'
			THEN 'CFS'
			ELSE units
		END as units,
		COALESCE(st.action, ft.action) AS action,
		COALESCE(st.minor, ft.minor) AS minor,
		COALESCE(st.moderate, ft.moderate) AS moderate,
		COALESCE(st.major, ft.major) AS major,
		COALESCE(st.record, ft.record) AS record
	FROM considerable_forecast_metadata main
	LEFT JOIN rnr.stage_thresholds st
		ON units = 'FT' AND st.nws_station_id = main.lid
	LEFT JOIN rnr.flow_thresholds ft
		ON units LIKE '%CFS' AND ft.nws_station_id = main.lid
),

forecast_max_value AS (
	SELECT DISTINCT ON (lid, pe, product_time)
		lid,
		pe,
		ts,
		product_time,
		valid_time as max_timestep,
		value as max_value,
		units,
		generation_time
	FROM relevant_forecasts
	ORDER BY 
		lid, 
		pe, 
		product_time, 
		value DESC
),

forecast_max_status AS (
	SELECT 
		fmv.lid,
		pe,
		ts,
		product_time,
		max_timestep,
		max_value,
		fmv.units,
		CASE
			WHEN major IS NOT NULL AND fmv.max_value >= major
			THEN 'major'
			WHEN moderate IS NOT NULL AND fmv.max_value >= moderate
			THEN 'moderate'
			WHEN minor IS NOT NULL AND fmv.max_value >= minor
			THEN 'minor'
			WHEN action IS NOT NULL AND fmv.max_value >= action
			THEN 'action'
			ELSE 'no_flooding'
		END as max_status,
		generation_time
	FROM forecast_max_value AS fmv
	LEFT JOIN relevant_thresholds
		ON relevant_thresholds.lid = fmv.lid
		AND relevant_thresholds.units = fmv.units
),

flood_data_base AS (
    SELECT
		lid,
		pe,
		ts,
		product_time,
		generation_time,
		max_timestep,
		max_value,
		max_status,
		units
    FROM forecast_max_status fms
    LEFT JOIN derived.ahps_restricted_sites restricted
        ON restricted.nws_lid = fms.lid
    WHERE restricted.nws_lid IS NULL 
        AND fms.max_status != 'no_flooding'
),

flood_forecasts AS (
	SELECT relevant_forecasts.*
	FROM relevant_forecasts
	JOIN flood_data_base flood
		ON flood.lid = relevant_forecasts.lid
		AND flood.pe = relevant_forecasts.pe
		AND flood.product_time = relevant_forecasts.product_time
),

forecast_initial_values AS (
	SELECT DISTINCT ON (lid, pe, product_time)
		lid,
		pe,
		product_time,
		value,
		units,
		valid_time as timestep
	FROM flood_forecasts
	ORDER BY
		lid,
		pe,
		product_time,
		valid_time
),

forecast_initial_status AS (
	SELECT 
		fiv.lid,
		pe,
		product_time,
		timestep,
		value,
		fiv.units,
		CASE
			WHEN major IS NOT NULL AND fiv.value >= major
			THEN 'major'
			WHEN moderate IS NOT NULL AND fiv.value >= moderate
			THEN 'moderate'
			WHEN minor IS NOT NULL AND fiv.value >= minor
			THEN 'minor'
			WHEN action IS NOT NULL AND fiv.value >= action
			THEN 'action'
			ELSE 'no_flooding'
		END as status
		FROM forecast_initial_values AS fiv
		LEFT JOIN relevant_thresholds
			ON relevant_thresholds.lid = fiv.lid
),

forecast_min_value AS (
	SELECT DISTINCT ON (lid, pe, product_time)
		lid,
		pe,
		product_time,
		value,
		units,
		valid_time as timestep
	FROM flood_forecasts
	ORDER BY
		lid,
		pe,
		product_time,
		value
),

forecast_min_status AS (
	SELECT 
		fmv.lid,
		pe,
		product_time,
		timestep,
		value,
		fmv.units,
		CASE
			WHEN major IS NOT NULL AND fmv.value >= major
			THEN 'major'
			WHEN moderate IS NOT NULL AND fmv.value >= moderate
			THEN 'moderate'
			WHEN minor IS NOT NULL AND fmv.value >= minor
			THEN 'minor'
			WHEN action IS NOT NULL AND fmv.value >= action
			THEN 'action'
			ELSE 'no_flooding'
		END as status
		FROM forecast_min_value AS fmv
		LEFT JOIN relevant_thresholds
			ON relevant_thresholds.lid = fmv.lid
),

forecast_point_xwalk AS (
	SELECT 
		station.nws_station_id, 
		station.name as nws_name,
		station.hsa as issuer,
		station.rfc as producer,
		xwalk.gage_id as usgs_site_code,
		gage.name as usgs_name,
		xwalk.nwm_feature_id as feature_id,
		ST_TRANSFORM(station.geo_point, 3857) AS geom
	FROM flood_data_base base
	LEFT JOIN external.nws_station station
		ON station.nws_station_id = base.lid
	LEFT JOIN (
		SELECT DISTINCT ON (nws_station_id) * 
		FROM external.full_crosswalk_view 
		ORDER BY 
			nws_station_id,
			nws_usgs_crosswalk_dataset_id DESC NULLS LAST,
			location_nwm_crosswalk_dataset_id DESC NULLS LAST
	) AS xwalk ON xwalk.nws_station_id = base.lid
	LEFT JOIN external.usgs_gage gage
		ON gage.usgs_gage_id = xwalk.gage_id
),

service_data AS (
	SELECT DISTINCT
		base.lid::text as nws_lid,
		base.pe,  -- NOT USED IN SERVICE, BUT NEEDED FOR RNR
		base.ts,  -- NOT USED IN SERVICE, BUT NEEDED FOR RNR
		to_char(base.product_time, 'YYYY-MM-DD HH24:MI:SS UTC') AS issued_time,
		to_char(base.generation_time, 'YYYY-MM-DD HH24:MI:SS UTC') AS generation_time,
		CASE
			WHEN initial.value = 0 THEN 'increasing'
			WHEN ((base.max_value - initial.value) / initial.value) > .05 THEN 'increasing'
			WHEN ((min.value - initial.value) / initial.value) < -.05 THEN 'decreasing'
			WHEN base.max_status::flood_status > initial.status::flood_status THEN 'increasing'
			WHEN base.max_status::flood_status < initial.status::flood_status THEN 'decreasing'
			ELSE 'constant'
		END AS forecast_trend,
		cats.record IS NOT NULL AND base.max_value > cats.record AS is_record_forecast,
		to_char(initial.timestep, 'YYYY-MM-DD HH24:MI:SS UTC') AS initial_value_timestep,
		initial.value as initial_value,
		initial.status as initial_status,
		to_char(min.timestep, 'YYYY-MM-DD HH24:MI:SS UTC') as min_value_timestep,
		min.value as min_value,
		min.status as min_status,
		to_char(base.max_timestep, 'YYYY-MM-DD HH24:MI:SS UTC') as max_value_timestep,
		base.max_value,
		base.max_status,
		xwalk.usgs_site_code,
		xwalk.feature_id,
		xwalk.nws_name,
		xwalk.usgs_name,
		xwalk.producer::text,
		xwalk.issuer::text,
		xwalk.geom,
		cats.action as action_threshold,
		cats.minor as minor_threshold,
		cats.moderate as moderate_threshold,
		cats.major as major_threshold,
		cats.record as record_threshold,
		base.units,
		'https://water.weather.gov/resources/hydrographs/' || LOWER(base.lid) || '_hg.png' AS hydrograph_link,
		'https://water.weather.gov/ahps2/rfc/' || base.lid || '.shortrange.hefs.png' as hefs_link,
		to_char(NOW(), 'YYYY-MM-DD HH24:MI:SS UTC') as update_time
	FROM flood_data_base base
	LEFT JOIN forecast_initial_status initial
		ON initial.lid = base.lid AND initial.pe = base.pe
	LEFT JOIN forecast_min_status min
		ON min.lid = base.lid AND min.pe = base.pe
	LEFT JOIN forecast_point_xwalk xwalk
		ON xwalk.nws_station_id = base.lid
	LEFT JOIN relevant_thresholds cats
		ON cats.lid = base.lid AND cats.units = base.units
	ORDER BY nws_lid
)

SELECT *
INTO publish.rfc_max_forecast
FROM service_data;