DROP TABLE IF EXISTS publish.rfc_max_forecast;

WITH
	-------- Max Stage Sub Query -------
	max_stage AS
		(SELECT 
			af.nws_lid, 
			af.stage, 
			af.status,
		 	MIN(af.time) AS timestep,
		 	CASE			
				WHEN af.status = 'action' THEN 1::integer
				WHEN af.status = 'minor' THEN 2::integer
				WHEN af.status = 'moderate' THEN 3::integer
				WHEN af.status = 'major' THEN 4::integer
				ELSE 0::integer
			END AS status_value
		FROM ingest.ahps_forecasts AS af
		INNER JOIN (
			SELECT
				nws_lid,
				MAX(stage) AS max_stage
			FROM ingest.ahps_forecasts
			GROUP BY nws_lid
		) AS b ON af.nws_lid = b.nws_lid AND af.stage = b.max_stage
		 LEFT OUTER JOIN ingest.ahps_metadata AS c on af.nws_lid = c.nws_lid
		 GROUP BY af.nws_lid, af.stage, af.status, c.record_threshold),
	-------- Min Stage Sub Query -------
	min_stage AS
		(SELECT 
			af.nws_lid,  
			af.stage, 
			af.status,
		 	MIN(af.time) AS timestep,
		 	CASE			
				WHEN af.status = 'action' THEN 1::integer
				WHEN af.status = 'minor' THEN 2::integer
				WHEN af.status = 'moderate' THEN 3::integer
				WHEN af.status = 'major' THEN 4::integer
				ELSE 0::integer
			END AS status_value
		FROM ingest.ahps_forecasts AS af
		INNER JOIN (
			SELECT
				nws_lid,
				MIN(stage) AS min_stage
			FROM ingest.ahps_forecasts
			GROUP BY nws_lid
		) AS b ON af.nws_lid = b.nws_lid AND af.stage = b.min_stage
		LEFT OUTER JOIN ingest.ahps_metadata AS c on af.nws_lid = c.nws_lid
		GROUP BY af.nws_lid, af.stage, af.status, c.record_threshold),
	-------- Initial Stage Sub Query -------
	initial_stage AS
		(SELECT 
			af.nws_lid,
			af.stage,
			af.status,
		 	af.time AS timestep,
		 	CASE			
				WHEN af.status = 'action' THEN 1::integer
				WHEN af.status = 'minor' THEN 2::integer
				WHEN af.status = 'moderate' THEN 3::integer
				WHEN af.status = 'major' THEN 4::integer
				ELSE 0::integer
			END AS status_value
		FROM ingest.ahps_forecasts AS af
		INNER JOIN (
			SELECT
				nws_lid,
				MIN(time) AS min_timestep
			FROM ingest.ahps_forecasts
			GROUP BY nws_lid
		) AS b ON af.nws_lid = b.nws_lid AND af.time = b.min_timestep
		LEFT OUTER JOIN ingest.ahps_metadata AS c on af.nws_lid = c.nws_lid)

-------- Main Query (Put it all together) -------
SELECT 
	max_stage.nws_lid,
	initial_stage.stage AS initial_stage,
	initial_stage.status AS initial_status,
	to_char(initial_stage.timestep::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS initial_stage_timestep,
	min_stage.stage AS min_stage,
	min_stage.status AS min_status,
	to_char(min_stage.timestep::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS min_stage_timestep,
	max_stage.stage AS max_stage,
	max_stage.status AS max_status,
	to_char(max_stage.timestep::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS max_stage_timestep,
	CASE
		WHEN initial_stage.stage = 0 THEN 'increasing'::text
		WHEN ((max_stage.stage-initial_stage.stage)/initial_stage.stage) > .05 THEN 'increasing'::text									
		WHEN ((min_stage.stage-initial_stage.stage)/initial_stage.stage) < -.05 THEN 'decreasing'::text									
		WHEN max_stage.status_value > initial_stage.status_value THEN 'increasing'::text								
		WHEN max_stage.status_value < initial_stage.status_value THEN 'decreasing'::text
		ELSE 'constant'::text
	END AS forecast_trend,
	CASE
		WHEN max_stage.stage >= metadata.record_threshold THEN true
		ELSE false
	END AS record_forecast,
	metadata.producer, 
	metadata.issuer,
	to_char(metadata."issuedTime"::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS issued_time,
	to_char(metadata."generationTime"::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS generation_time,
	metadata.usgs_sitecode, 
	metadata.feature_id, 
	metadata.nws_name, 
	metadata.usgs_name,
	ST_TRANSFORM(ST_SetSRID(ST_MakePoint(metadata.longitude, metadata.latitude),4326),3857) as geom, 
	metadata.action_threshold, 
	metadata.minor_threshold, 
	metadata.moderate_threshold, 
	metadata.major_threshold, 
	metadata.record_threshold, 
	metadata.units,
	CONCAT('https://water.weather.gov/resources/hydrographs/', LOWER(metadata.nws_lid), '_hg.png') AS hydrograph_link,
	CONCAT('https://water.weather.gov/ahps2/rfc/', metadata.nws_lid, '.shortrange.hefs.png') AS hefs_link,
	to_char(NOW()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS UPDATE_TIME
INTO publish.rfc_max_forecast
FROM ingest.ahps_metadata as metadata
JOIN max_stage ON max_stage.nws_lid = metadata.nws_lid
JOIN min_stage ON min_stage.nws_lid = metadata.nws_lid
JOIN initial_stage ON initial_stage.nws_lid = metadata.nws_lid
WHERE metadata."issuedTime"::timestamp without time zone > ('1900-01-01 00:00:00'::timestamp without time zone - INTERVAL '26 hours') AND metadata.nws_lid NOT IN (SELECT nws_lid FROM derived.ahps_restricted_sites);