-- Setting up an Postgresql RDS instance for eGDB
-- This doc includes the steps to create users, database, and schemas required 
-- to enable an enterprise geodatabase

-- Connect to the database as the RDS superuser to the master database (typically the postgres database) to run the following group of commands

-- -- Create SDE user
	CREATE ROLE sde LOGIN PASSWORD '<replace with pwd>' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION VALID UNTIL 'infinity';
	GRANT rds_superuser TO sde;
	GRANT sde TO <replace with rds superuser>;
	COMMENT ON ROLE sde IS 'Owner of the sde schema';
	
-- --- Create  dataowner user/other users
	CREATE ROLE <replace with username> LOGIN PASSWORD '<replace with pwd>' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION VALID UNTIL 'infinity';
	GRANT <replace with username> TO <replace with rds superuser>;
	COMMENT ON ROLE <replace with username> IS 'Owner of <replace with username> schema';
	
-- -- Create database
	CREATE DATABASE <replace with db Name> WITH OWNER = sde ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8' CONNECTION LIMIT = -1;
	ALTER DATABASE <replace with db Name> SET search_path = "$user", public, sde;
	GRANT ALL ON DATABASE <replace with DB Name> TO public;
	GRANT ALL ON DATABASE <replace with DB Name> TO sde;

-- Connect to the new database as the RDS superuser
-- -- Create DB extensions
	CREATE EXTENSION postgis;
	CREATE EXTENSION pgcrypto;
	CREATE EXTENSION "uuid-ossp";
	
-- -- Create the SDE schema
	CREATE SCHEMA sde AUTHORIZATION sde;
	GRANT ALL ON SCHEMA sde TO sde;
	GRANT ALL ON SCHEMA sde TO public;
	GRANT ALL ON SCHEMA sde TO <replace with rds superuser>;

-- -- Create the dataowner/other users schemas
	CREATE SCHEMA <replace with username> AUTHORIZATION <replace with username>;
	GRANT ALL ON SCHEMA <replace with username> TO <replace with username>;
	GRANT USAGE ON SCHEMA <replace with username> TO public;
	GRANT ALL ON SCHEMA <replace with username> TO <replace with rds superuser>;
	GRANT ALL ON SCHEMA <replace with username> TO sde;