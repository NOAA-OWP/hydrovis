DROP TABLE IF EXISTS publish.ana_coastal_atlgulf;

SELECT  
	*
INTO publish.ana_coastal_atlgulf
FROM ingest.ana_coastal_atlgulf as inun
