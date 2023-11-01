DROP TABLE IF EXISTS publish.ana_anomaly;
SELECT 
    channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.strm_order, 
    channels.name, 
    channels.huc6, 
    anom_7d.nwm_vers,
	anom_7d.reference_time,
	anom_7d.reference_time AS valid_time,
    anom_7d.average_flow_7day,
    anom_7d.prcntle_5 as pctl_5_7d,
    anom_7d.prcntle_10 as pctl_10_7d,
    anom_7d.prcntle_25 as pctl_25_7d,
    anom_7d.prcntle_75 as pctl_75_7d,
    anom_7d.prcntle_90 as pctl_90_7d,
    anom_7d.prcntle_95 as pctl_95_7d,
    anom_7d.anom_cat_7day,
	anom_14d.average_flow_14day,
    anom_14d.prcntle_5 as pctl_5_14d,
    anom_14d.prcntle_10 as pctl_10_14d,
    anom_14d.prcntle_25 as pctl_25_14d,
    anom_14d.prcntle_75 as pctl_75_14d,
    anom_14d.prcntle_90 as pctl_90_14d,
    anom_14d.prcntle_95 as pctl_95_14d,
    anom_14d.anom_cat_14day,
	ana.streamflow AS latest_flow,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	channels.geom
INTO publish.ana_anomaly
FROM derived.channels_conus AS channels
LEFT OUTER JOIN ingest.ana_7day_anomaly AS anom_7d ON channels.feature_id = anom_7d.feature_id
LEFT OUTER JOIN ingest.ana_14day_anomaly AS anom_14d ON channels.feature_id = anom_14d.feature_id
LEFT OUTER JOIN ingest.nwm_channel_rt_ana AS ana ON channels.feature_id = ana.feature_id
WHERE average_flow_7day IS NOT NULL OR average_flow_14day IS NOT NULL;