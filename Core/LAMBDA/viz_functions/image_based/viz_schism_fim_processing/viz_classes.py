import datetime
import boto3
import os
import json
import urllib.parse
import inspect
from botocore.exceptions import ClientError

###################################################################################################################################################
###################################################################################################################################################
class database: #TODO: Should we be creating a connection/engine upon initialization, or within each method like we are now?
    def __init__(self, db_type):
        self.type = db_type.upper()
        self._engine = None
        self._connection = None
    
    @property
    def engine(self):
        if not self._engine:
            self._engine = self.get_db_engine()
        return self._engine

    @property
    def connection(self):
        if not self._connection:
            self._connection = self.get_db_connection()
        return self._connection
    
    ###################################
    def get_db_credentials(self):
        db_host = os.environ[f'{self.type}_DB_HOST']
        db_name = os.environ[f'{self.type}_DB_DATABASE']
        db_user = os.environ[f'{self.type}_DB_USERNAME']
        db_password = os.getenv(f'{self.type}_DB_PASSWORD')
        return db_host, db_name, db_user, db_password

    ###################################
    def get_db_engine(self):
        from sqlalchemy import create_engine
        db_host, db_name, db_user, db_password = self.get_db_credentials()
        db_engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}')
        print(f"***> Established db engine to: {db_host} from {inspect.stack()[1].function}()")
        return db_engine

    ###################################
    def get_db_connection(self, asynchronous=False):
        import psycopg2
        db_host, db_name, db_user, db_password = self.get_db_credentials()
        connection = psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}", async_=asynchronous)
        print(f"***> Established db connection to: {db_host} from {inspect.stack()[1].function}()")
        return connection

    ###################################
    def get_db_values(self, table, columns):
        import pandas as pd
        db_engine = self.engine
        if not type(columns) == list:
            raise Exception("columns argument must be a list of column names")
        columns = ",".join(columns)
        print(f"---> Retrieving values for {columns}")
        df = pd.read_sql(f'SELECT {columns} FROM {table}', db_engine)
        db_engine.dispose()
        return df
    
    ###################################
    def load_df_into_db(self, table_name, df):
        import pandas as pd
        schema = table_name.split(".")[0]
        table = table_name.split(".")[-1]
        db_engine = self.engine
        print(table_name)
        print(f"---> Dropping {table_name} if it exists")
        db_engine.execute(f'DROP TABLE IF EXISTS {table_name};')  # Drop the stage table if it exists
        print("---> Getting sql to create table")
        create_table_statement = pd.io.sql.get_schema(df, table_name)
        replace_values = {'"geom" TEXT': '"geom" GEOMETRY', "REAL": "DOUBLE PRECISION"}  # Correct data types
        for a, b in replace_values.items():
            create_table_statement = create_table_statement.replace(a, b)
        create_table_statement = create_table_statement.replace(f'"{table_name}"', table_name)
        print(f"---> Creating {table_name}")
        db_engine.execute(create_table_statement)  # Create the new empty stage table
        print(f"---> Adding data to {table_name}")
        df.to_sql(con=db_engine, schema=schema, name=table, index=False, if_exists='append')
        db_engine.dispose()

    ###################################
    def run_sql_file_in_db(self, sql_file):
        sql = open(sql_file, 'r').read()
        with self.connection as db_connection:
            try:
                cur = db_connection.cursor()
                print(f"---> Running {sql_file}")
                cur.execute(sql)
                db_connection.commit()
            except Exception as e:
                raise e
                
    ###################################                
    def run_sql_in_db(self, sql, return_geodataframe=False):
        if sql.endswith(".sql"):
            sql = open(sql, 'r').read()
            
        db_engine = self.engine
        if not return_geodataframe:
            import pandas as pd
            df = pd.read_sql(sql, db_engine)
        else:
            import geopandas as gdp
            df = gdp.GeoDataFrame.from_postgis(sql, db_engine)
        
        db_engine.dispose()
        return df
    
    ###################################
    def move_data_to_another_db(self, dest_db_type, origin_table, dest_table, stage=True, add_oid=True, add_geom_index=True):
        import pandas as pd
        origin_engine = self.engine
        dest_db = self.__class__(dest_db_type)
        dest_engine = dest_db.engine
        if stage:
            dest_final_table = dest_table
            dest_final_table_name = dest_final_table.split(".")[1]
            dest_table = f"{dest_table}_stage"
        print(f"---> Reading {origin_table} from the {self.type} db")
        df = pd.read_sql(f'SELECT * FROM {origin_table};', origin_engine)  # Read from the newly created table
        print(f"---> Loading {origin_table} into {dest_table} in the {dest_db.type} db")
        dest_db.load_df_into_db(dest_table, df)
        if add_oid:
            print(f"---> Adding an OID to the {dest_table}")
            dest_engine.execute(f'ALTER TABLE {dest_table} ADD COLUMN OID SERIAL PRIMARY KEY;')
        if add_geom_index:
            print(f"---> Adding an spatial index to the {dest_table}")
            dest_engine.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom);')  # Add a spatial index
        if stage:
            print(f"---> Renaming {dest_table} to {dest_final_table}")
            dest_engine.execute(f'DROP TABLE IF EXISTS {dest_final_table};')  # Drop the published table if it exists
            dest_engine.execute(f'ALTER TABLE {dest_table} RENAME TO {dest_final_table_name};')  # Rename the staged table
        origin_engine.dispose()
        dest_engine.dispose()
    
    ###################################
    def cache_data(self, table, reference_time, retention_days=30):
        retention_cutoff = reference_time - datetime.timedelta(retention_days)
        ref_prefix = f"ref_{reference_time.strftime('%Y%m%d_%H%M_')}"
        retention_prefix = f"ref_{retention_cutoff.strftime('%Y%m%d_%H%M_')}"
        new_archive_table = f"archive.{ref_prefix}{table}"
        cutoff_archive_table = f"archive.{retention_prefix}{table}"
        db_engine = self.engine
        db_engine.execute(f'DROP TABLE IF EXISTS {new_archive_table};')
        db_engine.execute(f'DROP TABLE IF EXISTS {cutoff_archive_table};')
        db_engine.execute(f'SELECT * INTO {new_archive_table} FROM publish.{table};')
        db_engine.dispose()
        print(f"---> Wrote cache data into {new_archive_table} and dropped corresponding table from {retention_days} days ago, if it existed.")

###################################################################################################################################################
###################################################################################################################################################
class s3_file:
    def __init__(self, bucket, key):
        self.bucket = bucket
        self.key = key
        self.uri = 's3://' + bucket + '/' + key

    ###################################
    @classmethod
    def from_lambda_event(cls, event):
        print("Parsing lambda event to get S3 key and bucket.")
        if "Records" in event:
            message = json.loads(event["Records"][0]['Sns']['Message'])
            data_bucket = message["Records"][0]['s3']['bucket']['name']
            data_key = urllib.parse.unquote_plus(message["Records"][0]['s3']['object']['key'], encoding='utf-8')
        else:
            data_bucket = event['data_bucket']
            data_key = event['data_key']
        return cls(data_bucket, data_key)

    ###################################
    @classmethod
    def get_most_recent_from_configuration(cls, configuration_name, bucket):
        s3 = boto3.client('s3')
        # Set the S3 prefix based on the confiuration
        def get_s3_prefix(configuration_name, date):
            if configuration_name == 'replace_route':
                prefix = f"max_flows/replace_route/{date}/"
            elif configuration_name == 'ahps':
                prefix = f"max_stage/ahps/{date}/"
            else:
                prefix = f"common/data/model/com/nwm/prod/nwm.{date}/{configuration_name}/"
                
            return prefix
        # Get all S3 files that match the bucket / prefix
        def list_s3_files(bucket, prefix):
            files = []
            paginator = s3.get_paginator('list_objects_v2')
            for result in paginator.paginate(Bucket=bucket, Prefix=prefix):
                for key in result['Contents']:
                    # Skip folders
                    if not key['Key'].endswith('/'):
                        files.append(key['Key'])
            if len(files) == 0:
                raise Exception("No Files Found.")
            return files
        # Start with looking at files today, but try yesterday if that doesn't work (in case this runs close to midnight)
        today = datetime.datetime.today().strftime('%Y%m%d')
        yesterday = (datetime.datetime.today() - datetime.timedelta(1)).strftime('%Y%m%d')
        try:
            files = list_s3_files(bucket, get_s3_prefix(configuration_name, today))
        except Exception as e:
            print(f"Failed to get files for today ({e}). Trying again with yesterday's files")
            files = list_s3_files(bucket, get_s3_prefix(configuration_name, yesterday))
        # It seems this list is always sorted by default, but adding some sorting logic here may be necessary
        file = cls(bucket=bucket, key=files[-1:].pop())
        return file

    ###################################
    def check_existence(self):
        s3_resource = boto3.resource('s3')
        try:
            s3_resource.Object(self.bucket, self.key).load()
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == "404":
                return False
            else:
                raise

###################################################################################################################################################
###################################################################################################################################################
def get_elasticsearch_logger():
    import logging
    logger = logging.getLogger('elasticsearch')
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        # Prevent logging from propagating to the root logger
        logger.propagate = 0
        console = logging.StreamHandler()
        logger.addHandler(console)
        formatter = logging.Formatter('[ELASTICSEARCH %(levelname)s]:  %(asctime)s - %(message)s')
        console.setFormatter(formatter)
    return logger