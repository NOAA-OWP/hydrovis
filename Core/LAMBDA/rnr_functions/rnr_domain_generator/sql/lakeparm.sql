WITH 

domain_waterbodies AS (
	SELECT DISTINCT "NHDWaterbodyComID" as waterbody
	FROM rnr.domain_routelink rl
	WHERE "NHDWaterbodyComID" != -9999
)

SELECT
	lp.*
FROM rnr.nwm_lakeparm lp
JOIN domain_waterbodies wb
	ON wb.waterbody = lp.lake_id
ORDER BY lp.order_index;