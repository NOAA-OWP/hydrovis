SELECT
    rl.link as feature_id,
    COALESCE(ana.streamflow, -999900.0) as streamflow,
    0.0 AS nudge,
    COALESCE(ana.velocity, -999900.0) as velocity,
    0.0 AS "qSfcLatRunoff",
    COALESCE(ana."qBucket", -999900.0) as "qBucket"
FROM rnr.domain_routelink rl
LEFT JOIN ingest.nwm_channel_rt_ana_rnr ana
    ON ana.feature_id = rl.link
ORDER BY rl.order_index;