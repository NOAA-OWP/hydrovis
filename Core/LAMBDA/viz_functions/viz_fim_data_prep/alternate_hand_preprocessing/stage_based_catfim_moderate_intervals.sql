DROP TABLE IF EXISTS ingest.stage_based_catfim_moderate_intervals;
WITH main AS (
	SELECT
		trace_feature_id as feature_id,
		rf.nws_station_id,
		generate_series(
			(adj_moderate_stage_m + 0.3048)::numeric,
			COALESCE(adj_major_stage_m, adj_moderate_stage_m + 1.524)::numeric,
			0.3048
		) as stage_m
	FROM cache.rfc_categorical_stages AS rf
	WHERE adj_moderate_stage_m IS NOT NULL
), groupings AS (
	SELECT DISTINCT nws_station_id, stage_m
	FROM main
	ORDER BY nws_station_id, stage_m
), group_labeled AS (
	SELECT nws_station_id, stage_m, row_number() OVER (PARTITION BY nws_station_id ORDER BY stage_m) as interval_ft
	FROM groupings
)

SELECT 
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.feature_id,
    main.stage_m, 
    ROUND(CAST(main.stage_m * 35.315 as numeric), 2) AS forecast_stage_ft,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    main.nws_station_id,
	interval_ft,
    'Inserted FROM Ras2FIM Cache' AS prc_method,
    ST_Transform(gc.geom, 3857) AS geom
INTO ingest.stage_based_catfim_moderate_intervals
FROM ras2fim.geocurves AS gc
JOIN main ON gc.feature_id = main.feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON main.feature_id = crosswalk.feature_id
LEFT JOIN group_labeled l
	ON l.nws_station_id = main.nws_station_id
	AND l.stage_m = main.stage_m
WHERE crosswalk.huc8 IS NOT NULL AND
    crosswalk.lake_id = -999 AND
    ((main.stage_m <= gc.stage_m AND main.stage_m > gc.previous_stage_m)
	 OR main.stage_m > mgc.max_rc_stage_m);
----------------------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS ingest.stage_based_catfim_moderate_intervals_job_num;
SELECT *
INTO ingest.stage_based_catfim_moderate_intervals_job_num
FROM ingest.stage_based_catfim_moderate_intervals
WHERE interval_ft > lower_interval AND interval_ft <= upper_interval;

----------------------------------------------------------------------------------------------------------
SELECT UpdateGeometrySRID('ingest', 'stage_based_catfim_moderate_intervals', 'geom', 3857);
SELECT UpdateGeometrySRID('ingest', 'stage_based_catfim_moderate_intervals_job_num', 'geom', 3857);