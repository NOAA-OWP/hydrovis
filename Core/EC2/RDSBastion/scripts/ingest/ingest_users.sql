-- ROLES

CREATE ROLE nwm_viz_ro;
ALTER ROLE nwm_viz_ro WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 45 ENCRYPTED PASSWORD '${NWM_VIZ_RO}';
COMMENT ON ROLE rfc_fcst IS 'Read-write group role for the Viz databases';

CREATE ROLE rfc_fcst;
ALTER ROLE rfc_fcst WITH INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOBYPASSRLS ENCRYPTED PASSWORD '${RFC_FCST}';
COMMENT ON ROLE rfc_fcst IS 'Read-write group role for the RFC Forecast databases';

CREATE ROLE rfc_fcst_ro_user;
ALTER ROLE rfc_fcst_ro_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 45 ENCRYPTED PASSWORD '${RFC_FCST_RO_USER}';
COMMENT ON ROLE rfc_fcst_ro_user IS 'Read-only user role for the RFC Forecast databases';

CREATE ROLE rfc_fcst_user;
ALTER ROLE rfc_fcst_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS ENCRYPTED PASSWORD '${RFC_FCST_USER}';
COMMENT ON ROLE rfc_fcst_user IS 'Read-write user role for the RFC Forecast databases';

CREATE ROLE location_ro_user;
ALTER ROLE location_ro_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 45 ENCRYPTED PASSWORD '${LOCATION_RO_USER}';
COMMENT ON ROLE location_ro_user IS 'Read-only user role for the Location databases';

CREATE ROLE wrds_svc_rw_user;
ALTER ROLE wrds_svc_rw_user WITH INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOBYPASSRLS;
COMMENT ON ROLE wrds_svc_rw_user IS 'Read-write user role for the Location databases';

-- GROUPS

CREATE ROLE rfc_fcst_ro;
ALTER ROLE rfc_fcst_ro WITH INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOBYPASSRLS;
COMMENT ON ROLE rfc_fcst_ro IS 'Read-only group role for the RFC Forecast databases';

CREATE ROLE location_ro_user_grp;
ALTER ROLE location_ro_user_grp WITH INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOBYPASSRLS;
COMMENT ON ROLE location_ro_user_grp IS 'Read-only group role for the Location databases';

CREATE ROLE nwm_ro_user_grp;
ALTER ROLE nwm_ro_user_grp WITH INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOBYPASSRLS;
COMMENT ON ROLE nwm_ro_user_grp IS 'Read-only group role for the Location databases';

-- GROUP ASSIGNMENT

GRANT rfc_fcst_ro TO rfc_fcst_ro_user ;
GRANT rfc_fcst TO rfc_fcst_user ;
GRANT rfc_fcst_ro TO nwm_viz_ro ;
GRANT location_ro_user_grp TO location_ro_user ;

