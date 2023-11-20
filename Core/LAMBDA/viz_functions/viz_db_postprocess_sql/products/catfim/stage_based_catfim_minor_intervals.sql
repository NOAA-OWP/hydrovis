DROP TABLE IF EXISTS publish.stage_based_catfim_minor_intervals;

WITH all_intervals AS (
    SELECT * FROM publish.stage_based_catfim_minor_intervals_1
    UNION
    SELECT * FROM publish.stage_based_catfim_minor_intervals_2
    UNION
    SELECT * FROM publish.stage_based_catfim_minor_intervals_3
), max_interval_per_station AS (
	SELECT nws_station_id, max(interval_ft) AS max_interval_ft
	FROM all_intervals
	GROUP BY nws_station_id
)

SELECT all_intervals.*, max_interval_ft
INTO publish.stage_based_catfim_minor_intervals
FROM all_intervals
LEFT JOIN max_interval_per_station max_itvl ON max_itvl.nws_station_id = all_intervals.nws_station_id;