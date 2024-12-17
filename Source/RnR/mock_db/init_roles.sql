CREATE ROLE viz_proc_admin_rw_user WITH LOGIN PASSWORD 'pass123';
ALTER ROLE viz_proc_admin_rw_user CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE vizprocessing TO viz_proc_admin_rw_user;