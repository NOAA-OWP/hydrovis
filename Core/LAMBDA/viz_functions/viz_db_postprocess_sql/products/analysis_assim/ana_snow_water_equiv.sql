DROP TABLE IF EXISTS publish.ana_snow_water_equiv;
CREATE TABLE publish.ana_snow_water_equiv (
    reference_time TEXT,
    valid_time TEXT,
    update_time TEXT
);
INSERT INTO publish.ana_snow_water_equiv
VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);