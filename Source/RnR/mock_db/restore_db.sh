#!/bin/bash
set -e

# Wait for the database to be ready
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  echo "Waiting for database to be ready..."
  sleep 2
done

# Restore the dump
pg_restore -c -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v "/docker-entrypoint-initdb.d/z_rnr_schema_dump_20240612.dump" || true