DROP TABLE IF EXISTS publish.mrf_nbm_10day_max_coastal_inundation_depth;
CREATE TABLE publish.mrf_nbm_10day_max_coastal_inundation_depth (
    reference_time TEXT,
    valid_time TEXT,
    update_time TEXT
);
INSERT INTO publish.mrf_nbm_10day_max_coastal_inundation_depth
VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);