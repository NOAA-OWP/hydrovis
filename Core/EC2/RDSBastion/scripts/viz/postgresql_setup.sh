#!/bin/bash

echo "---- SETTING UP VIZ DB ----"

DBNAME="${DBNAME}"
DBHOST="${DBHOST}"
DBPORT=${DBPORT}
DBUSERNAME="${DBUSERNAME}"
DBPASSWORD="${DBPASSWORD}"
DEPLOYMENT_BUCKET="${DEPLOYMENT_BUCKET}"
DBUSERS="${DBUSERS}"
HOME="${HOME}"
FIM_VERSION="${FIM_VERSION}"

### install postgresql ###
sudo yum install -y postgresql12

### Constants ###
DBPASS="$${HOME}/.pgpass"
HML_S3_PREFIX="ingest/database"
POSTGIS_SCRIPT="postgis_setup.sql"
SETUP_SCRIPT="viz_setup.sql"
SERVICES_CSV="viz/db_pipeline/services.csv"
CONUS_CH_CSV="viz/authoritative_data/derived_data/nwm_v21_projected/nwm_v21_web_mercator_channels.csv"
HI_CH_CSV="viz/authoritative_data/derived_data/nwm_v21_projected/nwm_v21_web_mercator_channels_hi.csv"
PRVI_CH_CSV="viz/authoritative_data/derived_data/nwm_v21_projected/nwm_v21_web_mercator_channels_prvi.csv"
CONUS_RF_CSV="viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v21_recurrence_flows.csv"
HI_RF_CSV="viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v20_recurrence_flows_hawaii.csv"
PRVI_RF_CSV="viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v21_recurrence_flows_prvi.csv"
FIM_DIR="viz/fim/catchments"
DOWNLOAD_DIRECTORY="$${HOME}/postgres_data"
POSTGIS_FILE="$${DOWNLOAD_DIRECTORY}/$${POSTGIS_SCRIPT}"
SETUP_FILE="/deploy_files/$${SETUP_SCRIPT}"
DROP_DATABASE=0
REMOVE_BASE_FILE=0
REMOVE_SETUP_FILE=0
REMOVE_DIRECTORY=0

export PGPASSWORD=$${DBPASSWORD}

### Create/validate DBpass file ###
function create_pgpass()
{
  local FOUND=0
  local DBPASSLINE="$${DBHOST}:*:*:$${DBUSERNAME}:$${DBPASSWORD}"
  ### Check to see if file is present, and if so, validate it ###
  if [ -f "$${DBPASS}" ]
  then
    while IFS= read -r LINE
    do
      if [ "$${LINE}" = "$${DBPASSLINE}" ]
      then
        FOUND=1
        break 
      fi
    done < "$${DBPASS}"
    if [ $${FOUND} -eq 0 ]
    then
      echo "Appending line to $${DBPASS}"
      echo "$${DBPASSLINE}" >> "$${DBPASS}"
    else
      echo "Matching entry found in $${DBPASS}. No need to modify."
    fi
  else
    echo "Creating new $${DBPASS}..."
    echo "$${DBPASSLINE}" > "$${DBPASS}"
  fi

  chmod 600 "$${DBPASS}"
}

# Create DBPASS
create_pgpass

# Download database contents
echo "Downloading s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${POSTGIS_SCRIPT}..."
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${POSTGIS_SCRIPT} $${DOWNLOAD_DIRECTORY}/
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${SERVICES_CSV} "$${HOME}/services.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${CONUS_CH_CSV} "$${HOME}/nwm_v21_web_mercator_channels.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${HI_CH_CSV} "$${HOME}/nwm_v21_web_mercator_channels_hi.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${PRVI_CH_CSV} "$${HOME}/nwm_v21_web_mercator_channels_prvi.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${CONUS_RF_CSV} "$${HOME}/nwm_v21_recurrence_flows.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${HI_RF_CSV} "$${HOME}/nwm_v20_recurrence_flows_hawaii.csv"
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${PRVI_RF_CSV} "$${HOME}/nwm_v21_recurrence_flows_prvi.csv"
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/fim_catchments_$${FIM_VERSION}_fr_hi.csv" "$${HOME}/fim_catchments_$${FIM_VERSION}_fr_hi.csv"
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/fim_catchments_$${FIM_VERSION}_fr_prvi.csv" "$${HOME}/fim_catchments_$${FIM_VERSION}_fr_prvi.csv"
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/fim_catchments_$${FIM_VERSION}_ms_hi.csv" "$${HOME}/fim_catchments_$${FIM_VERSION}_ms_hi.csv"
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/fim_catchments_$${FIM_VERSION}_ms_prvi.csv" "$${HOME}/fim_catchments_$${FIM_VERSION}_ms_prvi.csv"

# Setting up DB
echo "Setting up postgis.."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -f "$${POSTGIS_FILE}"

# Update users
echo "Setting up DB..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -f "$${SETUP_FILE}"

rm -f $${HOME}/*

# Update users
echo "Setting up CONUS FIM Catchments..."
for i in $(seq -f "%02g" 1 18); 
do
  aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_fr_conus.csv" "$${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_fr_conus.csv"
  psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "\copy fim.fr_catchments_conus from $${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_fr_conus.csv delimiter ',' csv header;" 
  rm "$${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_fr_conus.csv"
  
  aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/$${FIM_DIR}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_ms_conus.csv" "$${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_ms_conus.csv"
  psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "\copy fim.ms_catchments_conus from $${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_ms_conus.csv delimiter ',' csv header;" 
  rm "$${HOME}/huc2_$${i}_fim_catchments_$${FIM_VERSION}_ms_conus.csv"
done

psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "SELECT UpdateGeometrySRID('fim', 'fr_catchments_conus', 'geom', 3857);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "CREATE INDEX fr_catchments_conus_geom_idx ON fim.fr_catchments_conus USING GIST (geom);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "CREATE INDEX fr_catchments_conus_idx ON fim.fr_catchments_conus USING btree (hydro_id);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "ALTER TABLE fim.fr_catchments_conus OWNER TO viz_proc_admin_rw_user;" 

psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "SELECT UpdateGeometrySRID('fim', 'ms_catchments_conus', 'geom', 3857);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "CREATE INDEX ms_catchments_conus_geom_idx ON fim.ms_catchments_conus USING GIST (geom);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "CREATE INDEX ms_catchments_conus_idx ON fim.ms_catchments_conus USING btree (hydro_id);" 
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" -c "ALTER TABLE fim.ms_catchments_conus OWNER TO viz_proc_admin_rw_user;"

# Updating permissions
echo "Granting database level permissions..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${DBNAME}" \
    -tAc "REVOKE CONNECT ON DATABASE $${DBNAME} FROM PUBLIC;
            GRANT CONNECT ON DATABASE $${DBNAME} to $${DBUSERS};
            COMMENT ON DATABASE $${DBNAME} IS 
            'database for visualizatoin services';"

DROP_DATABASE=0

