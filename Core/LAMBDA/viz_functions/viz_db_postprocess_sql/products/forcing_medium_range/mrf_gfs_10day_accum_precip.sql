DROP TABLE IF EXISTS publish.mrf_gfs_10day_accum_precip;
CREATE TABLE publish.mrf_gfs_10day_accum_precip (
    reference_time TEXT,
    update_time TEXT
);
INSERT INTO publish.mrf_gfs_10day_accum_precip
VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'),
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);