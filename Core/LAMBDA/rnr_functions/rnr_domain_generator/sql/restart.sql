WITH 

domain_waterbodies AS (
	SELECT DISTINCT "NHDWaterbodyComID" as waterbody
	FROM rnr.domain_routelink rl
	WHERE "NHDWaterbodyComID" != -9999
),

restart_waterbody AS (
	SELECT
		row_number() OVER (ORDER BY lp.order_index) as row_num,
		waterbody,
		COALESCE(reservoir.water_sfc_elev, -999900.0) as resht,
		COALESCE(reservoir.outflow, -999900.0) as qlakeo
	FROM rnr.nwm_lakeparm lp
	JOIN domain_waterbodies wb
		ON wb.waterbody = lp.lake_id
	LEFT JOIN ingest.nwm_reservoir_ana reservoir
		ON reservoir.feature_id = waterbody
	ORDER BY lp.order_index
),

ordered_links AS (
	SELECT
		row_number() OVER (ORDER BY rl.order_index) as row_num,
		COALESCE(channel.streamflow, -999900.0) as qlink
	FROM rnr.domain_routelink rl
	LEFT JOIN ingest.nwm_channel_rt_ana channel
		ON channel.feature_id = rl.link
	ORDER BY rl.order_index
)

SELECT
    ordered_links.row_num,
    restart_waterbody.row_num as rn,
    qlink as qlink1,
    qlink as qlink2,
	resht,
	qlakeo
FROM ordered_links
LEFT JOIN restart_waterbody
	ON restart_waterbody.row_num = ordered_links.row_num;