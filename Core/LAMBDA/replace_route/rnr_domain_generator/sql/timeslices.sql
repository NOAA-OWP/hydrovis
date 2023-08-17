WITH time_steps AS (
	SELECT * FROM generate_series(
		CURRENT_DATE::timestamp with time zone,
		CURRENT_DATE::timestamp with time zone + INTERVAL '5 days', 
		'15 minutes')
), timeslice_base AS (
	SELECT 
		xwalk.nws_station_id,
        xwalk.nwm_feature_id,
		xwalk.hydro_id,
		generate_series as time
	FROM time_steps
	JOIN rnr.domain_crosswalk AS xwalk ON TRUE
	ORDER BY xwalk.nwm_feature_id, time
),

basic_output AS (
	SELECT 
		base.hydro_id,
		base.nws_station_id,
		base.time,
		COALESCE(ana.maxflow_1hour_cms, fcst.flow_cms) as flow_cms
	FROM timeslice_base base
	LEFT JOIN rnr.domain_forecasts fcst
		ON fcst.valid_time = base.time
		AND fcst.lid = base.nws_station_id
	LEFT JOIN cache.max_flows_ana ana
		ON ana.feature_id = base.nwm_feature_id
		AND ana.reference_time::timestamp with time zone = base.time
	ORDER BY nwm_feature_id, time
)

SELECT
	EXTRACT(epoch FROM time) as "queryTime",
	100 as discharge_quality,
	flow_cms as discharge,
	time,
	LPAD(hydro_id, 15) as "stationId"
FROM basic_output
ORDER BY nws_station_id, time