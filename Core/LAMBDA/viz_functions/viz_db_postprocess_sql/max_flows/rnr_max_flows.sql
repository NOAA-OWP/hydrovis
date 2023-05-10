DROP TABLE IF EXISTS cache.max_flows_rnr;

SELECT DISTINCT ON (feature_id) *
INTO cache.max_flows_rnr
FROM (
	SELECT
		a.station_id as feature_id,
		a.reference_time,
		ROUND(b.max_streamflow::numeric, 2) AS maxflow_5day_cms,
		ROUND((b.max_streamflow * 35.315)::numeric, 2) AS maxflow_5day_cfs,
		a.time as time_of_max
	FROM ingest.rnr_wrf_hydro_outputs a
	JOIN (SELECT station_id, MAX(streamflow) AS max_streamflow FROM ingest.rnr_wrf_hydro_outputs GROUP BY station_id) b
		ON b.station_id = a.station_id AND b.max_streamflow = a.streamflow
	ORDER BY a.station_id, a.time
) as max_flows_with_potential_timing_duplicates