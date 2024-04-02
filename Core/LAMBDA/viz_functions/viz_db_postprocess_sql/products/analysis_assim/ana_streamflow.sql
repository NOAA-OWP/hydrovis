DROP TABLE IF EXISTS publish.ana_streamflow;

SELECT
    ana.feature_id,
    ana.feature_id::text as feature_id_str,
    ana.discharge_cfs as streamflow,
	ana.nwm_vers,
	ana.reference_time,
	ana.reference_time AS valid_time,
    channels.strm_order::integer,
    channels.name,
    channels.huc6,
    channels.state,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.ana_streamflow
FROM cache.max_flows_ana as ana
left join derived.channels_conus as channels ON channels.feature_id = ana.feature_id;
