DROP TABLE IF EXISTS PUBLISH.srf_MAX_HIGH_FLOW_MAGNITUDE;
WITH high_flow_mag AS (
     SELECT maxflows.feature_id,
        maxflows.maxflow_18hour_cfs AS max_flow,
            CASE
                WHEN maxflows.maxflow_18hour_cfs >= thresholds.rf_50_0_17c THEN '2'::text
				        WHEN maxflows.maxflow_18hour_cfs >= thresholds.rf_25_0_17c THEN '4'::text
				        WHEN maxflows.maxflow_18hour_cfs >= thresholds.rf_10_0_17c THEN '10'::text
                WHEN maxflows.maxflow_18hour_cfs >= thresholds.rf_5_0_17c THEN '20'::text
                WHEN maxflows.maxflow_18hour_cfs >= thresholds.rf_2_0_17c THEN '50'::text
                WHEN maxflows.maxflow_18hour_cfs >= thresholds.high_water_threshold THEN '>50'::text
                ELSE NULL::text
            END AS recur_cat,
        thresholds.high_water_threshold AS high_water_threshold,
        thresholds.rf_2_0_17c AS flow_2yr,
        thresholds.rf_5_0_17c AS flow_5yr,
        thresholds.rf_10_0_17c AS flow_10yr,
		    thresholds.rf_25_0_17c AS flow_25yr,
		    thresholds.rf_50_0_17c AS flow_50yr
       FROM cache.max_flows_srf maxflows
         JOIN derived.recurrence_flows_conus thresholds ON maxflows.feature_id = thresholds.feature_id
      WHERE thresholds.high_water_threshold > 0::double precision AND maxflows.maxflow_18hour_cfs >= thresholds.high_water_threshold
    )
SELECT channels.feature_id,
channels.feature_id::TEXT AS feature_id_str,
channels.strm_order,
channels.name,
channels.huc6,
channels.nwm_vers,
to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
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
INTO PUBLISH.srf_MAX_HIGH_FLOW_MAGNITUDE
FROM derived.channels_conus channels
 JOIN high_flow_mag ON channels.feature_id = high_flow_mag.feature_id