DROP TABLE IF EXISTS publish.mrf_gfs_max_high_flow_magnitude;
WITH high_flow_mag AS (
     SELECT maxflows.feature_id,
        maxflows.maxflow_3day_cfs,
        maxflows.maxflow_5day_cfs,
        maxflows.maxflow_10day_cfs,
            CASE
                WHEN maxflows.maxflow_3day_cfs >= thresholds.rf_50_0_17c THEN '2'::text
				WHEN maxflows.maxflow_3day_cfs >= thresholds.rf_25_0_17c THEN '4'::text
				WHEN maxflows.maxflow_3day_cfs >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.maxflow_3day_cfs >= thresholds.rf_5_0_17c THEN '20'::text
                WHEN maxflows.maxflow_3day_cfs >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.maxflow_3day_cfs >= thresholds.high_water_threshold THEN '>50'::text
                ELSE NULL::text
            END AS recur_cat_3day,
            CASE
                WHEN maxflows.maxflow_5day_cfs >= thresholds.rf_50_0_17c THEN '2'::text
				WHEN maxflows.maxflow_5day_cfs >= thresholds.rf_25_0_17c THEN '4'::text
				WHEN maxflows.maxflow_5day_cfs >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.maxflow_5day_cfs >= thresholds.rf_5_0_17c THEN '20'::text
                WHEN maxflows.maxflow_5day_cfs >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.maxflow_5day_cfs >= thresholds.high_water_threshold THEN '>50'::text
                ELSE NULL::text
            END AS recur_cat_5day,
            CASE
                WHEN maxflows.maxflow_10day_cfs >= thresholds.rf_50_0_17c THEN '2'::text
				WHEN maxflows.maxflow_10day_cfs >= thresholds.rf_25_0_17c THEN '4'::text
				WHEN maxflows.maxflow_10day_cfs >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.maxflow_10day_cfs >= thresholds.rf_5_0_17c THEN '20'::text
                WHEN maxflows.maxflow_10day_cfs >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.maxflow_10day_cfs >= thresholds.high_water_threshold THEN '>50'::text
                ELSE NULL::text
            END AS recur_cat_10day,
        thresholds.high_water_threshold AS high_water_threshold,
        thresholds.rf_2_0_17c AS flow_2yr,
        thresholds.rf_5_0_17c AS flow_5yr,
        thresholds.rf_10_0_17c AS flow_10yr,
		thresholds.rf_25_0_17c AS flow_25yr,
		thresholds.rf_50_0_17c AS flow_50yr
       FROM cache.mrf_gfs_max_flows maxflows
         JOIN derived.recurrence_flows_conus thresholds ON maxflows.feature_id = thresholds.feature_id
      WHERE (thresholds.high_water_threshold > 0::double precision) AND maxflows.maxflow_10day_cfs >= thresholds.high_water_threshold
    )

SELECT channels.feature_id,
channels.feature_id::TEXT AS feature_id_str,
channels.strm_order,
channels.name,
channels.huc6,
channels.nwm_vers,
to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
high_flow_mag.maxflow_3day_cfs,
high_flow_mag.maxflow_5day_cfs,
high_flow_mag.maxflow_10day_cfs,
high_flow_mag.recur_cat_3day,
high_flow_mag.recur_cat_5day,
high_flow_mag.recur_cat_10day,
high_flow_mag.high_water_threshold,
high_flow_mag.flow_2yr,
high_flow_mag.flow_5yr,
high_flow_mag.flow_10yr,
high_flow_mag.flow_25yr,
high_flow_mag.flow_50yr,
to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
channels.geom
INTO publish.mrf_gfs_max_high_flow_magnitude
FROM derived.channels_conus channels
 JOIN high_flow_mag ON channels.feature_id = high_flow_mag.feature_id;