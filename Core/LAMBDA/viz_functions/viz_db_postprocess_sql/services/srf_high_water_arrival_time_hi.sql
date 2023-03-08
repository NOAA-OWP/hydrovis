DROP TABLE IF EXISTS publish.srf_high_water_arrival_time_hi;

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
        WHEN THRESHOLDS.HIGH_WATER_THRESHOLD = '-9999'::integer::double precision THEN 'Insufficient Data'::text
        WHEN MAX(FORECASTS.FORECAST_HOUR) >= 48 THEN 'Outside SRF Forecast Window'::text
        ELSE ((max(forecasts.forecast_hour)+1) - MIN(FORECASTS.FORECAST_HOUR))::text
			END AS DURATION,
			THRESHOLDS.HIGH_WATER_THRESHOLD AS HIGH_WATER_THRESHOLD,
			ROUND((MAX(FORECASTS.STREAMFLOW) * 35.315::double precision)::numeric,
				2) AS MAX_FLOW
		FROM INGEST.NWM_CHANNEL_RT_SRF_HI FORECASTS
		JOIN DERIVED.RECURRENCE_FLOWS_HI THRESHOLDS ON FORECASTS.FEATURE_ID = THRESHOLDS.FEATURE_ID
		JOIN DERIVED.CHANNELS_HI GEO ON FORECASTS.FEATURE_ID = GEO.FEATURE_ID
		WHERE (THRESHOLDS.HIGH_WATER_THRESHOLD > 0::double precision
									OR THRESHOLDS.HIGH_WATER_THRESHOLD = '-9999'::integer::double precision)
			AND (FORECASTS.STREAMFLOW * 35.315::double precision) >= THRESHOLDS.HIGH_WATER_THRESHOLD
		GROUP BY FORECASTS.FEATURE_ID, forecasts.reference_time, forecasts.nwm_vers,
			THRESHOLDS.HIGH_WATER_THRESHOLD)

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
INTO publish.srf_high_water_arrival_time_hi
FROM derived.channels_hi channels
JOIN arrival_time ON channels.feature_id = arrival_time.feature_id;