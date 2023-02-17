DROP TABLE IF EXISTS publish.ana_streamflow_alaska_para;

SELECT
    ana.feature_id,
    channels.feature_id as channels_feature_id,
    ana.feature_id::text as feature_id_str,
    ana.maxflow_1hour_cfs as streamflow,
	ana.nwm_vers,
	ana.reference_time,
	ana.reference_time AS valid_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.ana_streamflow_alaska_para
FROM cache.max_flows_ana_alaska_para as ana
left join derived.channels_alaska as channels ON channels.feature_id = ana.feature_id::bigint;
