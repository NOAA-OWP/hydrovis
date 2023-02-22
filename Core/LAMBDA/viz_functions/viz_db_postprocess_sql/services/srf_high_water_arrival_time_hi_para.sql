DROP TABLE IF EXISTS publish.srf_high_water_arrival_time_hi_para;

WITH arrival_time AS
	(SELECT forecasts.feature_id,
			forecasts.nwm_vers,
			forecasts.reference_time,
			CASE
							WHEN thresholds.high_water_threshold = '-9999'::double precision THEN NULL
							ELSE MIN(forecasts.forecast_hour)
			END AS t_high_water_threshold,
			CASE
							WHEN thresholds.high_water_threshold = '-9999'::integer::double precision THEN 'Insufficient Data'::text
							WHEN MAX(forecasts.forecast_hour) >= 48 THEN '> 48 hours'::text
							ELSE (max(forecasts.forecast_hour)+1)::text
			END AS t_normal,
			CASE
							WHEN thresholds.high_water_threshold = '-9999'::integer::double precision THEN 'Insufficient Data'::text
							WHEN MAX(forecasts.forecast_hour) >= 48 THEN 'Outside SRF Forecast Window'::text
							ELSE ((max(forecasts.forecast_hour)+1) - MIN(forecasts.forecast_hour))::text
			END AS duration,
			thresholds.high_water_threshold,
			ROUND((MAX(forecasts.streamflow) * 35.315::double precision)::numeric,
				2) AS max_flow
		FROM ingest.nwm_channel_rt_srf_hi_para forecasts
		JOIN derived.recurrence_flows_hi thresholds ON forecasts.feature_id = thresholds.feature_id
		JOIN derived.channels_hi geo ON forecasts.feature_id = geo.feature_id
		WHERE (thresholds.high_water_threshold > 0::double precision
									OR thresholds.high_water_threshold = '-9999'::integer::double precision)
			AND (forecasts.streamflow * 35.315::double precision) >= thresholds.high_water_threshold
		GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers,
			thresholds.high_water_threshold)

SELECT channels.feature_id,
	channels.feature_id::TEXT AS feature_id_str,
	channels.name,
	channels.strm_order,
	channels.huc6,
	arrival_time.nwm_vers,
	arrival_time.reference_time,
	arrival_time.t_high_water_threshold,
	arrival_time.t_normal,
	arrival_time.duration,
	arrival_time.high_water_threshold,
	arrival_time.max_flow,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	channels.geom
INTO publish.srf_high_water_arrival_time_hi_para
FROM derived.channels_hi channels
JOIN arrival_time ON channels.feature_id = arrival_time.feature_id;