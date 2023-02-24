DROP TABLE IF EXISTS publish.mrf_nbm_high_water_arrival_time_para;
WITH arrival_time AS (
     SELECT forecasts.feature_id, 
        min(forecasts.forecast_hour) AS t_high_water_threshold,
        forecasts.nwm_vers,
        forecasts.reference_time,
        CASE WHEN max(forecasts.forecast_hour) >= 240 THEN '> 10 days'::text
              ELSE (max(forecasts.forecast_hour)+3)::text
              END AS t_normal,
        CASE
            WHEN max(forecasts.forecast_hour) >= 240 THEN 'Outside MRF Forecast Window'::text
            ELSE ((max(forecasts.forecast_hour)+3) - min(forecasts.forecast_hour))::text
            END AS duration,
        thresholds.high_water_threshold AS high_water_threshold,
        round((max(forecasts.streamflow) * 35.315::double precision)::numeric, 2) AS max_flow,
        to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
      FROM ingest.nwm_channel_rt_mrf_nbm_para AS forecasts
      JOIN derived.recurrence_flows_conus thresholds ON forecasts.feature_id = thresholds.feature_id
      WHERE thresholds.high_water_threshold > 0::double precision AND (forecasts.streamflow * 35.315::double precision) >= thresholds.high_water_threshold
      GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers, thresholds.high_water_threshold
    )

SELECT channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order,
    channels.huc6,
    arrival_time.nwm_vers,
    arrival_time.reference_time,
    arrival_time.t_high_water_threshold,
    arrival_time.t_normal,
    arrival_time.duration,
    arrival_time.high_water_threshold,
    arrival_time.max_flow,
    arrival_time.update_time,
    channels.geom
INTO publish.mrf_nbm_high_water_arrival_time_para
FROM derived.channels_conus channels
JOIN arrival_time ON channels.feature_id = arrival_time.feature_id;