DROP TABLE IF EXISTS publish.ana_coastal_inundation_prvi;

SELECT
    inundation.*,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS valid_time
INTO publish.ana_coastal_inundation_prvi
FROM ingest.ana_coastal_inundation_prvi AS inundation;