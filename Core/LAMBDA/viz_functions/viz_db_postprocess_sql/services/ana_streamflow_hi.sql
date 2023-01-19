DROP TABLE IF EXISTS publish.ana_streamflow_hi;

SELECT
    ana.feature_id,
    ana.feature_id::text as feature_id_str,
    ana.maxflow_1hour_cfs as streamflow,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS valid_time,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    channels.nwm_vers,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.ana_streamflow_hi
FROM cache.max_flows_ana_hi as ana
left join derived.channels_hi as channels ON channels.feature_id = ana.feature_id;