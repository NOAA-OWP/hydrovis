DROP TABLE IF EXISTS publish.mrf_nbm_rapid_onset_flooding;
-- Calculate rapid onset reaches
WITH rapid_onset AS (
	-- Calculate the info for the start of a rapid flood event - >=100% flow in one hour.
	WITH floodstart AS (
		-- Add a rank value by feature_id, so we can look up info for the flood start later with 'rnk = 1'
		WITH pct_change_by_hour AS
			(
			WITH forecasts_full AS
				(
				WITH series AS -- Calculate a full 240 hour series for every feature_id, so that unadjacent hours aren't compared
					(SELECT channels.feature_id, generate_series(3,240,3) AS forecast_hour
					 FROM derived.channels_conus channels JOIN cache.mrf_nbm_max_flows as mf on channels.feature_id = mf.feature_id
					 WHERE channels.strm_order <= 4
					)
				SELECT series.feature_id, series.forecast_hour, CASE WHEN streamflow is NOT NULL THEN (streamflow * 35.315) ELSE 0.001 END AS streamflow -- Set streamflow to 0.01 in cases where it is missing, so we don't get a divide by zero error
				FROM series
				LEFT OUTER JOIN ingest.nwm_channel_rt_mrf_nbm AS forecasts ON series.feature_id = forecasts.feature_id AND series.forecast_hour = forecasts.forecast_hour -- Left outer join to the forecasts table (so that all hours are always present)
				ORDER BY forecasts.feature_id, series.forecast_hour
				)	
			SELECT feature_id, forecast_hour, streamflow AS flow,
			( -- Use the lag funtion to calucate percent change for each reach / forecast hour timestep
				(streamflow) - (lag(streamflow, 1) OVER (PARTITION BY feature_id ORDER BY forecast_hour)))/ --Numerator: current streamflow - last hour streamflow
				(lag(streamflow, 1) OVER (PARTITION BY feature_id ORDER by forecast_hour) -- Denominator: last hour streamflow
			) AS pct_chg
			FROM forecasts_full
			)
		SELECT *, rank() OVER (PARTITION BY feature_id ORDER BY forecast_hour) as rnk
		FROM pct_change_by_hour
		WHERE pct_chg >= 1)
	-- Select the forecast related fields for the attribute table
	SELECT
		forecasts.feature_id,
		forecasts.nwm_vers,
		forecasts.reference_time,
		min(forecasts.forecast_hour) AS flood_start_hour,
		max(forecasts.forecast_hour) AS flood_end_hour,
		max(forecasts.forecast_hour) - min(forecasts.forecast_hour) AS flood_length,
		min(floodstart.flow) AS flood_flow,
		min(floodstart.pct_chg) AS flood_percent_increase,
		max(high_water_threshold) AS high_water_threshold
	FROM ingest.nwm_channel_rt_mrf_nbm AS forecasts
	JOIN floodstart ON forecasts.feature_id = floodstart.feature_id
	JOIN derived.recurrence_flows_conus AS thresholds ON forecasts.feature_id = thresholds.feature_id
	WHERE -- This is where the main forecast filter conditions go
		(thresholds.high_water_threshold > 0 OR thresholds.high_water_threshold = '-9995') AND -- Don't show reaches with invalid high_water_threshold values
		((forecasts.streamflow * 35.315) >= thresholds.high_water_threshold) AND -- Only show reaches that hit high_water_threshold in the forecast window
		((forecasts.forecast_hour - floodstart.forecast_hour) <= 6) AND -- At least 100% increase and high_water_threshold within 6 hours of rapid onset
		floodstart.rnk = 1 -- This ensures that we're only looking the start of the flood based on the rank function used above.
	GROUP BY forecasts.feature_id)

-- Put it all together with geometry
SELECT channels.feature_id,
	channels.feature_id::TEXT AS feature_id_str,
	channels.strm_order,
	channels.name,
	channels.huc6,
    rapid_onset.nwm_vers,
    rapid_onset.reference_time,
	flood_start_hour, 
	flood_end_hour, 
	flood_length, 
	flood_flow, 
	flood_percent_increase, 
	high_water_threshold,
	ST_LENGTH(channels.geom)*0.000621371 AS reach_Length_miles, to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	geom
INTO publish.mrf_nbm_rapid_onset_flooding
FROM derived.channels_conus channels
JOIN rapid_onset ON channels.feature_id = rapid_onset.feature_id
where channels.strm_order <= 4;