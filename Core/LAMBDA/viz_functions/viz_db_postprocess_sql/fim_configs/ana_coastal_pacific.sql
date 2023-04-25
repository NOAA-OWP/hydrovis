DROP TABLE IF EXISTS publish.ana_coastal_pacific;

SELECT  
	*
INTO publish.ana_coastal_pacific
FROM ingest.ana_coastal_pacific as inun
