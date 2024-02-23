DROP TABLE IF EXISTS ingest.stage_based_catfim_major_intervals;

SELECT 
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.feature_id,
    ROUND(CAST((rf.adj_major_stage_m + (ft_from_major * 0.3048)) as numeric), 2) AS stage_m,
    ROUND(CAST((rf.adj_major_stage_m / 35.315) + ft_from_major as numeric), 2) AS forecast_stage_ft,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    rf.nws_station_id,
	ft_from_major as interval_ft,
    'Inserted FROM Ras2FIM Cache' AS prc_method,
    ST_Transform(gc.geom, 3857) AS geom
INTO ingest.stage_based_catfim_major_intervals
FROM ras2fim.geocurves AS gc
JOIN cache.rfc_categorical_stages AS rf ON gc.feature_id = rf.trace_feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
WHERE rf.adj_major_stage_m IS NOT NULL AND 
	crosswalk.huc8 IS NOT NULL AND
    crosswalk.lake_id = -999 AND
    ((ROUND(CAST((rf.adj_major_stage_m + (ft_from_major * 0.3048)) as numeric), 2) <= gc.stage_m
		AND ROUND(CAST((rf.adj_major_stage_m + (ft_from_major * 0.3048)) as numeric), 2) > gc.previous_stage_m)
	 OR ROUND(CAST((rf.adj_major_stage_m + (ft_from_major * 0.3048)) as numeric), 2) > mgc.max_rc_stage_m);
----------------------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS ingest.stage_based_catfim_major_intervals_job_num;
SELECT *
INTO ingest.stage_based_catfim_major_intervals_job_num
FROM ingest.stage_based_catfim_major_intervals
WHERE interval_ft > lower_interval AND interval_ft <= upper_interval;

----------------------------------------------------------------------------------------------------------
SELECT UpdateGeometrySRID('ingest', 'stage_based_catfim_major_intervals', 'geom', 3857);
SELECT UpdateGeometrySRID('ingest', 'stage_based_catfim_major_intervals_job_num', 'geom', 3857);