DROP TABLE IF EXISTS publish.srf_48hr_high_water_arrival_time_prvi;

WITH arrival_time AS
	(SELECT forecasts.feature_id,
			CASE
							WHEN thresholds.high_water_threshold = '-9999'::double precision  THEN NULL
							ELSE MIN(forecasts.forecast_hour)
			END AS t_high_water_threshold,
			CASE
							WHEN MAX(forecasts.forecast_hour) >= 48 THEN '> 48 hours'::text
							ELSE (MAX(forecasts.forecast_hour)+1)::text
			END AS t_normal,
			CASE
							WHEN MAX(forecasts.forecast_hour) >= 48 THEN 'Outside SRF Forecast Window'::text
							ELSE ((MAX(forecasts.forecast_hour)+1) - MIN(forecasts.forecast_hour))::text
			END AS duration,
			forecasts.nwm_vers,
			forecasts.reference_time,
			thresholds.high_water_threshold,
			ROUND((MAX(forecasts.streamflow) * 35.315::double precision)::numeric,
				2) AS max_flow
		FROM ingest.nwm_channel_rt_srf_prvi forecasts
		JOIN derived.recurrence_flows_prvi thresholds ON forecasts.feature_id = thresholds.feature_id
		JOIN derived.channels_prvi geo ON forecasts.feature_id = geo.feature_id
		WHERE (thresholds.high_water_threshold > 0::double precision
									OR thresholds.high_water_threshold = '-9999'::integer::double precision)
			AND (forecasts.streamflow * 35.315::double precision) >= thresholds.high_water_threshold
		GROUP BY forecasts.feature_id, forecasts.nwm_vers, forecasts.reference_time, thresholds.high_water_threshold)

SELECT channels.feature_id,
	channels.feature_id::TEXT AS feature_id_str,
	name,
	channels.strm_order,
	huc6,
	'PRVI' as state,
	arrival_time.nwm_vers,
	arrival_time.reference_time,
	arrival_time.t_high_water_threshold,
	arrival_time.t_normal,
	arrival_time.duration,
	arrival_time.high_water_threshold,
	arrival_time.max_flow,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UtC') AS update_time,
	channels.geom
INTO publish.srf_48hr_high_water_arrival_time_prvi
FROM derived.channels_prvi channels
JOIN arrival_time ON channels.feature_id = arrival_time.feature_id;