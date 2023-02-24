DROP TABLE IF EXISTS publish.ana_streamflow_prvi_para;

SELECT
    ana.feature_id,
    ana.feature_id::text as feature_id_str,
    ana.maxflow_1hour_cfs as streamflow,
	ana.nwm_vers,
	ana.reference_time,
	ana.reference_time AS valid_time,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.ana_streamflow_prvi_para
FROM cache.max_flows_ana_prvi_para as ana
left join derived.channels_prvi as channels ON channels.feature_id = ana.feature_id;