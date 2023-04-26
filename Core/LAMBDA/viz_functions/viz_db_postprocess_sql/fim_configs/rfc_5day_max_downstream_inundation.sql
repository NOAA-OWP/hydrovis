DROP TABLE IF EXISTS publish.rfc_5day_max_downstream_inundation;

WITH agg_status AS (
    SELECT 
        feature_id,
        STRING_AGG(max_flows.forecast_nws_lid || ' @ ' || max_flows.forecast_issue_time || ' (' || max_flows.forecast_max_status || ')', ', ') AS inherited_rfc_forecasts,
        INITCAP(MAX(REPLACE(max_flows.viz_max_status, '_', ' '))) AS max_status
    FROM ingest.rnr_max_flows max_flows
    GROUP BY feature_id
)
SELECT  
	inun.hydro_id,
	inun.hydro_id_str::TEXT AS hydro_id_str,
	inun.branch,
	inun.feature_id,
	inun.feature_id_str::TEXT AS feature_id_str,
	inun.streamflow_cfs,
	inun.hand_stage_ft,
	inun.max_rc_stage_ft,
	inun.max_rc_discharge_cfs,
	inun.fim_version,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	inun.huc8,
	inun.geom,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
	derived.channels_conus.strm_order, 
    derived.channels_conus.name,
	derived.channels_conus.state,
    agg_status.inherited_rfc_forecasts,
    agg_status.max_status
INTO publish.rfc_5day_max_downstream_inundation
FROM ingest.rfc_5day_max_downstream_inundation as inun 
JOIN agg_status ON inun.feature_id = agg_status.feature_id
left join derived.channels_conus ON derived.channels_conus.feature_id = inun.feature_id;