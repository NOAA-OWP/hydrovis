DROP TABLE IF EXISTS PUBLISH.ANA_HIGH_FLOW_MAGNITUDE;
WITH HIGH_FLOW_MAG AS
	(SELECT MAXFLOWS.FEATURE_ID,
			MAXFLOWS.MAXFLOW_1HOUR_CFS AS MAX_FLOW,
			CASE
                WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.rf_50_0_17c THEN '2'::text
				WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.rf_25_0_17c THEN '4'::text
				WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.rf_5_0_17c THEN '20'::text
	 			WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.MAXFLOW_1HOUR_CFS >= thresholds.high_water_threshold THEN '>50'::text
							ELSE NULL::text
			END AS RECUR_CAT,
        thresholds.high_water_threshold AS high_water_threshold,
		thresholds.rf_2_0_17c AS flow_2yr,   
		thresholds.rf_5_0_17c AS flow_5yr,
        thresholds.rf_10_0_17c AS flow_10yr,
		thresholds.rf_25_0_17c AS flow_25yr,
		thresholds.rf_50_0_17c AS flow_50yr
		FROM CACHE.MAX_FLOWS_ANA MAXFLOWS
		JOIN DERIVED.RECURRENCE_FLOWS_CONUS THRESHOLDS ON MAXFLOWS.FEATURE_ID = THRESHOLDS.FEATURE_ID
		WHERE (THRESHOLDS.HIGH_WATER_THRESHOLD > 0::double precision)
			AND MAXFLOWS.MAXFLOW_1HOUR_CFS >= THRESHOLDS.HIGH_WATER_THRESHOLD)
SELECT CHANNELS.FEATURE_ID,
	CHANNELS.FEATURE_ID::TEXT AS FEATURE_ID_STR,
	CHANNELS.STRM_ORDER,
	CHANNELS.NAME,
	CHANNELS.HUC6,
	CHANNELS.NWM_VERS,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS valid_time,
	HIGH_FLOW_MAG.MAX_FLOW,
	HIGH_FLOW_MAG.RECUR_CAT,
	high_flow_mag.high_water_threshold,
	high_flow_mag.flow_2yr,
	high_flow_mag.flow_5yr,
	high_flow_mag.flow_10yr,
	high_flow_mag.flow_25yr,
	high_flow_mag.flow_50yr,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	CHANNELS.GEOM
INTO PUBLISH.ANA_HIGH_FLOW_MAGNITUDE
FROM DERIVED.CHANNELS_CONUS CHANNELS
JOIN HIGH_FLOW_MAG ON CHANNELS.FEATURE_ID = HIGH_FLOW_MAG.FEATURE_ID;