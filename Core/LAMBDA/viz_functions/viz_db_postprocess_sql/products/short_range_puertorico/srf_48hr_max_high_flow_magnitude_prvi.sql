DROP TABLE IF EXISTS publish.srf_48hr_max_high_flow_magnitude_prvi;
WITH high_flow_mag AS (
    SELECT maxflows.feature_id,
        maxflows.maxflow_48hour_cfs AS max_flow,
        maxflows.nwm_vers,
        maxflows.reference_time,
		CASE
			WHEN thresholds.high_water_threshold = '-9999'::integer::double precision THEN 'Not Available'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.rf_100_0 THEN '1'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.rf_50_0 THEN '2'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.rf_25_0 THEN '4'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.rf_10_0 THEN '10'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.rf_5_0 THEN '20'::text
			WHEN maxflows.maxflow_48hour_cfs >= thresholds.high_water_threshold THEN '>20'::text
			ELSE NULL::text
		END AS recur_cat,
        thresholds.high_water_threshold AS high_water_threshold,
		thresholds.rf_2_0 AS flow_2yr,
		thresholds.rf_5_0 AS flow_5yr,
		thresholds.rf_10_0 AS flow_10yr,
		thresholds.rf_25_0 AS flow_25yr,
		thresholds.rf_50_0 AS flow_50yr,
		thresholds.rf_100_0 AS flow_100yr
    FROM cache.max_flows_srf_prvi maxflows
    JOIN derived.recurrence_flows_prvi thresholds ON maxflows.feature_id = thresholds.feature_id
    WHERE thresholds.high_water_threshold > 0::double precision AND maxflows.maxflow_48hour_cfs >= thresholds.high_water_threshold
)
SELECT channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.strm_order,
    channels.name,
    channels.huc6,
    'PRVI' as state,
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
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.srf_48hr_max_high_flow_magnitude_prvi
FROM derived.channels_prvi channels
JOIN high_flow_mag ON channels.feature_id = high_flow_mag.feature_id