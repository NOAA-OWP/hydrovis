DROP TABLE IF EXISTS publish.srf_max_high_flow_magnitude_hi;

WITH HIGH_FLOW_MAG AS
	(SELECT MAXFLOWS.FEATURE_ID,
	        maxflows.nwm_vers,
	        maxflows.reference_time,
			MAXFLOWS.maxflow_48hour_cfs AS MAX_FLOW,
			CASE
							WHEN THRESHOLDS.HIGH_WATER_THRESHOLD = '-9999'::integer::double precision THEN 'Not Available'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.RF_100_0 THEN '1'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.RF_50_0 THEN '2'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.RF_25_0 THEN '4'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.RF_10_0 THEN '10'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.RF_5_0 THEN '20'::text
							WHEN MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.HIGH_WATER_THRESHOLD THEN '>20'::text
							ELSE NULL::text
			END AS RECUR_CAT,
			THRESHOLDS.HIGH_WATER_THRESHOLD AS HIGH_WATER_THRESHOLD,
			THRESHOLDS.RF_2_0 AS FLOW_2YR,
			THRESHOLDS.RF_5_0 AS FLOW_5YR,
			THRESHOLDS.RF_10_0 AS FLOW_10YR,
			THRESHOLDS.RF_25_0 AS FLOW_25YR,
			THRESHOLDS.RF_50_0 AS FLOW_50YR,
			THRESHOLDS.RF_100_0 AS FLOW_100YR
		FROM CACHE.MAX_FLOWS_SRF_HI MAXFLOWS
		JOIN DERIVED.RECURRENCE_FLOWS_HI THRESHOLDS ON MAXFLOWS.FEATURE_ID = THRESHOLDS.FEATURE_ID
		WHERE (THRESHOLDS.HIGH_WATER_THRESHOLD > 0::double precision
									OR THRESHOLDS.HIGH_WATER_THRESHOLD = '-9999'::integer::double precision)
			AND MAXFLOWS.maxflow_48hour_cfs >= THRESHOLDS.HIGH_WATER_THRESHOLD )

SELECT channels.feature_id,
	channels.feature_id::TEXT AS feature_id_str,
	channels.strm_order,
	channels.name,
	channels.huc6,
    high_flow_mag.nwm_vers,
    high_flow_mag.reference_time,
	high_flow_mag.max_flow,
	high_flow_mag.recur_cat,
	high_flow_mag.high_water_threshold,
	high_flow_mag.flow_2yr,
	high_flow_mag.flow_5yr,
	high_flow_mag.flow_10yr,
	high_flow_mag.flow_25yr,
	high_flow_mag.flow_50yr,
	high_flow_mag.flow_100yr,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	channels.geom
INTO publish.srf_max_high_flow_magnitude_hi
FROM derived.channels_hi channels
JOIN high_flow_mag ON channels.feature_id = high_flow_mag.feature_id;