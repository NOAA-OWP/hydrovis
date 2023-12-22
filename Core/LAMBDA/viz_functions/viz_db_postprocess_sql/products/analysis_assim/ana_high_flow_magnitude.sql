DROP TABLE IF EXISTS publish.ana_high_flow_magnitude;
WITH high_flow_mag AS
	(SELECT maxflows.feature_id,
			maxflows.discharge_cfs AS max_flow,
			maxflows.reference_time,
			maxflows.nwm_vers,
			CASE
                WHEN maxflows.discharge_cfs >= thresholds.rf_50_0_17c THEN '2'::text
				WHEN maxflows.discharge_cfs >= thresholds.rf_25_0_17c THEN '4'::text
				WHEN maxflows.discharge_cfs >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.discharge_cfs >= thresholds.rf_5_0_17c THEN '20'::text
	 			WHEN maxflows.discharge_cfs >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.discharge_cfs >= thresholds.high_water_threshold THEN '>50'::text
							ELSE NULL::text
			END AS recur_cat,
        thresholds.high_water_threshold AS high_water_threshold,
		thresholds.rf_2_0_17c AS flow_2yr,   
		thresholds.rf_5_0_17c AS flow_5yr,
        thresholds.rf_10_0_17c AS flow_10yr,
		thresholds.rf_25_0_17c AS flow_25yr,
		thresholds.rf_50_0_17c AS flow_50yr
		FROM cache.max_flows_ana maxflows
		JOIN derived.recurrence_flows_CONUS thresholds ON maxflows.feature_id = thresholds.feature_id
		WHERE (thresholds.high_water_threshold > 0::double precision)
			AND maxflows.discharge_cfs >= thresholds.high_water_threshold)
SELECT channels.feature_id,
	channels.feature_id::TEXT AS feature_id_str,
	channels.strm_order,
	channels.name,
	channels.state,
	channels.huc6,
	high_flow_mag.nwm_vers,
	high_flow_mag.reference_time,
	high_flow_mag.reference_time AS valid_time,
	high_flow_mag.max_flow,
	high_flow_mag.recur_cat,
	high_flow_mag.high_water_threshold,
	high_flow_mag.flow_2yr,
	high_flow_mag.flow_5yr,
	high_flow_mag.flow_10yr,
	high_flow_mag.flow_25yr,
	high_flow_mag.flow_50yr,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	channels.geom
INTO publish.ana_high_flow_magnitude
FROM derived.channels_CONUS channels
JOIN high_flow_mag ON channels.feature_id = high_flow_mag.feature_id;