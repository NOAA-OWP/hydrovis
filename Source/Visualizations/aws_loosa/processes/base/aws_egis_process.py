import datetime as dt
import filelock
import json
import os
import shutil
import tempfile
import traceback
import time
import boto3
import requests
import urllib3
import uuid
import copy
import re

import xml.dom.minidom as DOM
from inspect import getframeinfo, stack

from aws_loosa.processing_pipeline.utils.process import PipelineProcess
from aws_loosa.processing_pipeline.cli import validation

from aws_loosa.consts import egis as consts, paths,  monitoring as mon_consts, TOTAL_PROCESSES_ENV_VAR
from aws_loosa.consts.paths import HYDROVIS_S3_CONNECTION_FILE_PATH, MAPX_DIR, EMPTY_PRO_PROJECT_DIR
from aws_loosa.utils.shared_funcs import add_update_time, add_ref_time, update_field_name
from aws_loosa.utils.viz_lambda_shared_funcs import get_service_metadata

import arcgis
import arcpy

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class AWSEgisPublishingProcess(PipelineProcess):
    """
    AWSEgisPublishingProcess extends the PipelineProcess class, adding additional functionality to aid in publishing
    NWM services to the EGIS system.

    Args:
        a_log_directory (str): Directory where log will be written.
        a_log_level (str): Log level to use for logging. Either 'INFO', 'WARN', 'ERROR', or 'DEBUG'.

    Attributes:
        service_name (str): Name of the service as published on ArcGIS service.

        published_data_location (str): Path to the directory that contains the published data.
        pristine_data_location (str, optional): Path to the directory that contains the pristine data.
        workspace_location (str): Path to directory in which processing will occur.
        cache_location (str): Path to directory that will maintain cached data

        update_layer_description_timestamp (bool, deprecated, default=False): (DEPRECATED) Indicates if the description
            of the layer should be updated with the latest timestamp.
        append_timestamp_to_description (bool, optional, default=True): Indicates if the description of the layer should
            be updated with the latest timestamp.
    """
    # Service identifiers
    service_name = ''

    # Data locations and names
    published_data_location = ''
    published_referenced_data_location = ''
    pristine_data_location = ''
    authoritative_location = ''
    workspace_location = ''
    cache_location = ''
    proproject_location = ''
    flags_location = ''
    geodatabase_name = ''
    output_cache_days = int(os.environ['cache_days'])
    service_type = 'MapService'
    create_referenced_md = False
    image_service_data = ''
    

    # Service metadata
    max_service_instances = 5

    server_url = ''
    server_host = ''
    server_connection = ''

    def __init__(self, a_log_directory=None, a_log_level='INFO', a_name=''):
        """
        Constructor.
        """
        if not a_name:
            a_name = self.service_name

        # Call parent constructor
        super().__init__(a_log_directory=a_log_directory,
                         a_logstash_socket=mon_consts.LOGSTASH_SOCKET,
                         a_log_level=a_log_level,
                         a_name=a_name)
        # The following two logical statements get the "TOTAL_PROCESSES" environment variable
        # and send a message to logstash containing this information. This variable is set
        # by the "deploy/start_pipelines.py" script used for deploys, and corresponds to the
        # number of processes that are expected to be running after the deploy. This is only done
        # to enhance the kibana monitoring and allow for a dynamic dashboard that indicated a problem
        # if any expected service stopped running or responding.

        total_processes = os.environ.get(TOTAL_PROCESSES_ENV_VAR, 0)
        self._log.info(f"{total_processes} processes are expected to be running.")

        services_data = get_service_metadata()
        service_data = [item for item in services_data if item['service'] == self.service_name]
        if not service_data:
            raise(f"Metadata not found for {self.service_name}")

        service_data = service_data[0]

        if self.service_name.startswith("ana"):
            self.configuration = "analysis_assim"
        elif self.service_name.startswith("srf"):
            self.configuration = "short_range"
        elif self.service_name.startswith("mrf"):
            self.configuration = "medium_range_mem1"

        self.server_name = service_data["egis_server"]
        self.folder_name = service_data["egis_folder"]
        self.enable_feature_service = service_data["feature_service"]
        self.public_service = service_data["public_service"]
        self.tags = service_data["tags"]
        self.summary = service_data["summary"]
        self.item_credits = service_data["credits"]
        experimental_addition = """
            <br><br>The NWS is accepting comments through December 31, 2022 on the Experimental NWC Visualization Services. 
            This service is one of many Experimental NWC Visualization Services. 
            Please provide feedback on the Experimental NWC Visualization Services at: https://www.surveymonkey.com/r/Exp_NWCVisSvcs_2022
            <br><br>Link to graphical web page: https://www.weather.gov/owp/operations
            <br><br>Link to data download (shapefile): TBD
            <br><br>Link to metadata: https://nws.weather.gov/products/PDD/SDD_ExpNWCVisualizationServices_2022.pdf
        """

        self.description =  service_data["description"] 
        if self.public_service:
            self.description = self.description + experimental_addition

        # PUBLISHED LOCATION
        if not self.published_data_location:
            self.published_data_location = os.path.join(
                consts.PUBLISHED_ROOT, self.server_name, self.folder_name,
                self.service_name)

        if not self.published_referenced_data_location:
            self.published_referenced_data_location = os.path.join(
                consts.PUBLISHED_ROOT, consts.PRIMARY_SERVER, consts.REFERENCE_FOLDER)

        if not self.pristine_data_location:
            self.pristine_data_location = os.path.join(
                consts.PRISTINE_ROOT, self.server_name, self.folder_name,
                self.service_name)

        if not self.proproject_location:
            self.proproject_location = os.path.join(MAPX_DIR, self.configuration, f"{self.service_name}.mapx")

        # DYNAMIC LOCATIONS
        if not self.cache_location:
            self.cache_location = os.path.join(
                consts.CACHE_ROOT, consts.SERVICES, self.server_name, self.folder_name, self.service_name
            )

        if not self.flags_location:
            if consts.FLAGS_ROOT.startswith(r"s3://"):
                self.flags_location = f"{consts.FLAGS_ROOT}/{self.server_name}/{self.folder_name}"
            else:
                self.flags_location = os.path.join(consts.FLAGS_ROOT, self.server_name, self.folder_name)

        if not self.workspace_location:
            self.workspace_location = os.path.join(
                consts.WORKSPACE_ROOT, self.server_name, self.folder_name,
                self.service_name)

        if not self.geodatabase_name:
            self.geodatabase_name = f'{self.service_name}.gdb'

        if self.service_type == "ImageService":
            self.rest_service_type = "ImageServer"
        elif self.service_type == "MapService":
            self.rest_service_type = "MapServer"
        else:
            raise Exception("service_type must be ImageService or MapService")

        lockfile_name = f'{self.service_name}.lock'

        if consts.FLAGS_ROOT.startswith(r"s3://"):
            self.service_published_file = f"{self.flags_location}/{self.service_name}"
            self.service_lockfile = os.path.join(os.getenv("TEMP"), lockfile_name)
        else:
            self.service_published_file = os.path.join(self.flags_location, self.service_name)
            self._makedirs(self.flags_location)
            self.service_lockfile = os.path.join(self.flags_location, lockfile_name)

        self.one_off = False
        try:
            caller = getframeinfo(stack()[1][0])
            process_dir = os.path.dirname(caller.filename)
            pipeline_file = os.path.join(process_dir, 'pipeline.yml')
            validator = validation.PipelineConfigValidator(pipeline_file)
            context = validator.get_validated_dict()
            if 'seed_times' in context:
                if context['seed_times']:
                    self.one_off = True
        except Exception as e:
            print(e)

        if not self.server_host:
            self.server_host = consts.EGIS_HOST

    def _get_token(self, host=consts.EGIS_HOST, a_server=None, a_expiration=5):
        """
        Get a token for managing an ArcGIS Server.

        Args:
            a_expiration(int): Time in minutes to set expiration of the token.

        Returns:
            str: The token. Raises an Exception otherwise
        """

        MAX_ATTEMPTS = 2
        error_obj = None
        server_name = a_server or self.server_name

        # Build request components

        url = f"https://{host}/{consts.PORTAL}/sharing/rest/generateToken"
        server_url = f"https://{host}/{server_name}"

        data = {
            'username': consts.EGIS_USERNAME,
            'password': consts.EGIS_PASSWORD,
            'expiration': str(a_expiration),  #: Token timeout in minutes; defaults to 60.
            'client': 'referer',
            'referer': server_url,
            'f': 'json'
        }

        for attempt in range(MAX_ATTEMPTS):
            try:
                # Request the token
                r = requests.post(url, data=data, verify=False)

                json_response = r.json()

                # Validate result

                if json_response is None or "token" not in json_response:
                    if json_response is None:
                        raise Exception("Failed to get token for unkown reason.")
                    else:
                        raise Exception(f"Failed to get token: {json_response['messages']}.")
                else:
                    return json_response['token']  # SUCCESS
            except Exception as e:
                error_obj = e
                self._log.warning(
                    f'The following error occurred while attempting to get a token on server '
                    f'"{a_server}":\n{str(error_obj)}\nTrying again...'
                )

        # If reaches this point, max attempts were reached without succeeding

        raise Exception(
            f'The following error occurred while attempting to get a token on server "{a_server}":\n{str(error_obj)}'
        )

    def _start_or_stop_service_rest(self, a_action, a_server=None, a_folder=None, a_service=None):
        """
        Start or stop a map service.

        Args:
            a_action(str): Either 'start' or 'stop'.
            a_server(str): Either 'image', 'raster', 'server', or 'primary'.
            a_service(str): Name of map service.
            a_folder(str): Name of service directory folder of the map service. Optional.

        Returns:
            None if successful, raises an Exception otherwise.
        """
        MAX_ATTEMPTS = 1
        SLEEP = 10  # seconds
        error_obj = None
        # Get vars
        a_server = a_server or self.server_name
        a_folder = a_folder or self.folder_name
        a_service = a_service or f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        full_service_name = f'{a_folder}/{a_service}' if a_folder else a_service
        # Get Token
        token = self._get_token(a_server=a_server)
        # Build URL
        url = (
            f"https://{self.server_host}/{a_server}/admin/services/{full_service_name}.{self.rest_service_type}/{a_action}"  # noqa: E501
        )
        data = {
            'token': token,
            'f': 'json'
        }
        self._log.debug(f'{a_action.upper()} service request url: "{url}"')
        for attempt in range(MAX_ATTEMPTS):
            result = None
            try:
                r = requests.post(url, data=data, verify=False)
                result = r.json()
                self._validate_result(result)
                return  # SUCCESS
            except Exception as e:
                if result:
                    error_obj = result
                    if any('Could not find resource or operation' in message for message in error_obj['messages']):
                        raise Exception(
                            f'Unable to {a_action.upper()} service "{full_service_name}" due to the following error:'
                            f'\nService does not exist.'
                        )
                else:
                    error_obj = e
            self._log.warning(
                f'Unable to {a_action.upper()} service "{full_service_name}" due to the following error:'
                f'\n{error_obj}\nTrying again in {SLEEP} seconds...'
            )
            time.sleep(SLEEP)
        raise Exception(
            f'Unable to {a_action.upper()} service "{full_service_name}" with the following error:\n{error_obj}'
        )

    def _validate_result(self, a_result):
        """
        Evaluate result of an ArcGIS Server admin api request.
        """
        if a_result is not None and 'status' in a_result:
            if a_result['status'] == 'success':
                return  # SUCCESS

            if a_result['status'] == 'warning':
                self._log.warning(f"Warning returned from Start/Stop service request - {a_result}")
                return  # SUCCESS WITH WARNING

        raise Exception(f"Unsuccessful result returned: {a_result}.")

    def _update_portal_item(self):
        """
        Update portal item properties as needed.

        Returns:
            None if successful. Otherwise, an Exception will be raised.
        """
        self._log.info("Updating Portal Item...")
        properties = self.get_service_properties()

        token = self._get_token(a_server=consts.PORTAL)

        try:
            portal_id = properties['portalProperties']['portalItems'][0]['itemID']
        except Exception:
            raise Exception("No Portal ID found for service")

        post_url = (
            f"https://{consts.EGIS_HOST}/{consts.PORTAL}/sharing/rest/content/users/admin/items/{portal_id}/update"
        )

        data = {
            'token': token,
            'f': 'json',
            'accessInformation': self.item_credits,
            'description': self.description
        }

        try:
            response = requests.post(post_url, data=data)
        except requests.exceptions.SSLError:
            response = requests.post(post_url, data=data, verify=False)

        if response.status_code != 200:
            raise Exception(f"Attempt to update portal item failed: {response.content}")
        else:
            response_obj = response.json()
            if 'error' in response_obj:
                raise Exception(f"Attempt to update portal item failed: {response_obj}")

        self._log.info("Portal item was updated successfully.")

    def get_service_properties(self):

        # Get Token
        token = self._get_token(a_server=self.server_name)
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        full_service_name = f'{self.folder_name}/{service_name}' if self.folder_name else service_name

        get_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/{full_service_name}.{self.rest_service_type}"
        )

        params = {
            'token': token,
            'f': 'json'
        }

        try:
            properties = requests.get(get_url, params=params).json()
        except requests.exceptions.SSLError:
            properties = requests.get(get_url, params=params, verify=False).json()

        return properties

    def get_service_iteminfo(self):

        # Get Token
        token = self._get_token(a_server=self.server_name)
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        full_service_name = f'{self.folder_name}/{service_name}' if self.folder_name else service_name

        get_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/"
            f"{full_service_name}.{self.rest_service_type}/itemInfo"
        )

        params = {
            'token': token,
            'f': 'json'
        }

        try:
            iteminfo = requests.get(get_url, params=params).json()
        except requests.exceptions.SSLError:
            iteminfo = requests.get(get_url, params=params, verify=False).json()

        return iteminfo

    def _update_service_definition(self):
        """
        Update portal item properties as needed.

        Returns:
            None if successful. Otherwise, an Exception will be raised.
        """
        iteminfo = self.get_service_iteminfo()

        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        full_service_name = '{self.folder_name}/{service_name}' if self.folder_name else service_name

        iteminfo['name'] = service_name
        iteminfo['description'] = self.description
        iteminfo['accessInformation'] = self.item_credits

        post_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/"
            f"{full_service_name}.{self.rest_service_type}/iteminfo/edit"
        )

        data = {
            'token': self._get_token(a_server=self.server_name),
            'f': 'json',
            'serviceItemInfo': json.dumps(iteminfo)
        }

        response = requests.post(post_url, data=data, verify=False)
        if response.status_code != 200:
            raise Exception(f"Attempt to update service item info failed: {response.content}")
        response_obj = response.json()
        if 'status' not in response_obj:
            raise Exception(f"Attempt to update service item info failed: {response_obj}")
        if response_obj['status'] == 'error':
            raise Exception(f"Attempt to update service item info failed: {response_obj}")

    def _swap_data(self, a_working_location):
        """
        Update the data behind the service using the copy and replace method. Using this method, stopping the
        service is not required.

        Args:
            a_working_location (str): Path to the working directory.
        """
        # If working location is a directory, recursively copy
        if os.path.isdir(a_working_location):
            self._copy_dir(a_working_location, self.published_data_location)
        else:
            pass

    def _get_working_location_path_for_event(self, event_time, for_cache=False):
        # Derive working directory name from the published directory name
        active_name, active_ext = os.path.splitext(os.path.basename(self.published_data_location))
        time_stamp = '{:%Y%m%dT%H%M%S}'.format(event_time)
        working_name = f'{time_stamp}{active_ext}'

        if for_cache:
            # # Compose path to the cache location
            working_location_path = os.path.join(self.cache_location, working_name)
        else:
            # # Compose path to the workspace location
            working_location_path = os.path.join(self.workspace_location, working_name)

        return working_location_path

    def _create_working_location(self, working_location):
        """
        Copy/create a folder for working in. If a pristine location is given and exists, then it will be copied.
        Otherwise the working location is created on the fly.

        Args:
            working_location(str): Path at which to create the working location. This will contain a copy of the
                contents of the pristine directory if one is specified. Otherwise, it will be an empty directory.

        Returns:
            None if successful. Otherwise, an Exception will be raised.
        """
        # The remove often fails and retries when there is no sleep because the lock file has not been deleted yet.
        if os.path.exists(working_location):
            self._log.debug(f"Waiting 15 seconds before attempting to remove {working_location}")
            time.sleep(15)
            remove_success = self._remove(working_location)
            if not remove_success:
                raise Exception(f"Unable to remove existing workspace at {working_location}.")

        # If pristine location is defined, then create workspace by copying it
        if self.pristine_data_location:
            # Copy pristine to working location name if pristine exists
            # Otherwise create the working directory as an empty directory
            if os.path.isdir(self.pristine_data_location):
                self._copy_dir(self.pristine_data_location, working_location)
            else:
                os.makedirs(working_location)
        # Otherwise, just create the working location as an empty directory
        else:
            os.makedirs(working_location)

        # If the new working location doesn't validate, remove it so that a fresh workspace is created next time
        try:
            self._validate_working_location(working_location, deep_check=True)
        except Exception:
            remove_success = self._remove(working_location)
            if not remove_success:
                raise Exception(f"Unable to remove existing workspace at {working_location}.")

    def _clean_cache(self):
        """
        Clean data cache.
        """
        keep_directories = self._get_directory_cache_list()
        if os.path.isdir(self.cache_location):
            for datedir in os.listdir(self.cache_location):
                dirpath = os.path.join(self.cache_location, datedir)

                if any(dirpath in kd for kd in keep_directories):
                    continue
                else:
                    self._remove(dirpath)

    def _clean_workspace(self):
        if os.path.isdir(self.workspace_location):
            for dirname in os.listdir(self.workspace_location):
                dirpath = os.path.join(self.workspace_location, dirname)
                self._remove(dirpath)

    def _validate_working_location(self, a_working_location, deep_check=False):
        """
        Validate the given working location.

        Args:
            a_working_location(str): Path to the working directory.
            deep_check(bool): Check that all contents match if True. Only check that directory exists if otherwise.

        Returns:
            None if valid. Raises an Exception otherwise.
        """
        # VALIDATION: Working location must exist or cannot proceed
        if not os.path.isdir(a_working_location):
            raise Exception("Provided working location path does not exist or is not a directory.")

        if deep_check:
            if self.pristine_data_location:
                if os.path.isdir(self.pristine_data_location):
                    if not self._compare_dir(self.pristine_data_location, a_working_location):
                        raise Exception("The working location data does not match that of the pristine data location.")

    def _get_directory_cache_list(self):
        directories = []

        if self.output_cache_days > 0:
            cache_interval = dt.timedelta(days=self.output_cache_days)
            if self.next_process_event_time:
                new_data_interval = self.next_process_event_time - self.process_event_time
            else:
                # Guess at the new data interval based on the name
                if 'mrf' in self._name:
                    new_data_interval = dt.timedelta(hours=6)
                else:
                    new_data_interval = dt.timedelta(hours=1)

            earliest_keep_date = self.process_event_time - cache_interval

            iter_date = self.process_event_time
            while iter_date > earliest_keep_date:
                directories.append(self._get_working_location_path_for_event(iter_date, for_cache=True))
                iter_date -= new_data_interval

        return directories

    def delete_image_service(self):
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        token = self._get_token()

        self._log.info("Checking if service folder exists...")
        existURL = f"https://{self.server_host}/{self.server_name}/admin/services/exists"
        postdata = {'token': token, 'f': 'json', 'folderName': self.folder_name}
        response = requests.post(existURL, data=postdata, verify=False)

        if response.status_code != 200:
            raise Exception(f"Attempt to check service existence failed: {response.content}")
        else:
            response_obj = response.json()
            if 'status' in response_obj:
                if response_obj['status'] != 'success':
                    raise Exception(f"Attempt to check service existence failed: {response_obj}")
            exists = response_obj['exists']

        if not exists:
            createURL = f"https://{self.server_host}/{self.server_name}/admin/services/createFolder"
            postdata = {'token': token, 'f': 'json', 'folderName': self.folder_name}
            response = requests.post(createURL, data=postdata, verify=False)

            if response.status_code != 200:
                raise Exception(f"Attempt to check service existence failed: {response.content}")
            else:
                response_obj = response.json()
                if 'status' in response_obj:
                    if response_obj['status'] != 'success':
                        raise Exception(f"Attempt to check service existence failed: {response_obj}")
            return

        self._log.info("Checking if service exists...")
        existURL = f"https://{self.server_host}/{self.server_name}/admin/services/exists"
        postdata = {
            'token': token, 'f': 'json', 'type': 'ImageServer', 'serviceName': service_name,
            'folderName': self.folder_name
        }
        response = requests.post(existURL, data=postdata, verify=False)

        if response.status_code != 200:
            raise Exception(f"Attempt to check service existence failed: {response.content}")
        else:
            response_obj = response.json()
            if 'status' in response_obj:
                if response_obj['status'] != 'success':
                    raise Exception(f"Attempt to check service existence failed: {response_obj}")
            exists = response_obj['exists']

        if exists:
            self._log.info("Deleting existing service exists...")
            self.delete_service()

        return

    def publish_image_service(self):
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        token = self._get_token()

        self._log.info("Publishing ImageService setting service properties...")
        with open(paths.MD_PUBLISH_JSON) as json_data:
            data = json.loads(json_data.read())

        data['serviceName'] = service_name
        data['description'] = self.description
        data['properties']['copyright'] = self.item_credits
        data['properties']['path'] = self.image_service_data
        data['properties']['description'] = self.description
        service_data = json.dumps(data)

        createURL = f"https://{self.server_host}/{self.server_name}/admin/services/{self.folder_name}/createService"
        postdata = {'token': token, 'f': 'json'}
        postdata['service'] = service_data
        response = requests.post(createURL, data=postdata, verify=False)

        if response.status_code != 200:
            raise Exception(f"Attempt to publish image service failed: {response.content}")
        else:
            response_obj = response.json()
            if response_obj['status'] != 'success':
                raise Exception(f"Attempt to publish image service failed: {response_obj}")

    def publish_service(self):
        """
            Publishes a brand new service or overwrites an existing service
        """
        workspace = tempfile.mkdtemp()
        try:
            # Set output file names
            sddraft_filename = self.service_name + ".sddraft"
            sddraft_output_filename = os.path.join(workspace, sddraft_filename)

            service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
            summary = f'{self.summary}{consts.SUMMARY_TAG}'

            gis = arcgis.gis.GIS(f"https://{consts.EGIS_HOST}/portal", username=consts.EGIS_USERNAME,
                                 password=consts.EGIS_PASSWORD, verify_cert=False)
            servers = gis.admin.servers.list()
            publish_server = None

            conn_str = None
            try:
                conn_str = arcpy.management.CreateDatabaseConnectionString(
                    "POSTGRESQL", os.environ['EGIS_DB_HOST'], username=os.environ['EGIS_DB_USERNAME'],
                    password=os.environ['EGIS_DB_PASSWORD'], database=os.environ['EGIS_DB_DATABASE']
                )
                conn_str = re.findall("<WorkspaceConnectionString>(.*)</WorkspaceConnectionString>", str(conn_str))[0]
            except Exception as e:
                print(f"Failed to create a database string ({e})")

            sd_folder = os.path.join(paths.AUTHORITATIVE_ROOT, "sd_files")
            if not os.path.exists(sd_folder):
                os.makedirs(sd_folder)

            baseline_aprx_path = os.path.join(EMPTY_PRO_PROJECT_DIR, "Empty_Project.aprx")
            mapx_fpath = self.proproject_location

            if self.service_type == 'MapService':
                temp_aprx = arcpy.mp.ArcGISProject(baseline_aprx_path)
                temp_aprx.importDocument(mapx_fpath)
                temp_aprx_fpath = os.path.join(sd_folder, f'{service_name}.aprx')
                temp_aprx.saveACopy(temp_aprx_fpath)
                self._log.info("Reading data from map project file...")
                aprx = arcpy.mp.ArcGISProject(temp_aprx_fpath)

                schema = "services"

                m = aprx.listMaps()[0]

                print('Updating the connectionProperties of each layer...')
                for layer in m.listLayers():
                    if not layer.connectionProperties:
                        continue

                    layerCIM = layer.getDefinition('V2')

                    if layer.isRasterLayer:
                        new_s3_workspace = f"DATABASE={HYDROVIS_S3_CONNECTION_FILE_PATH}\\{service_name}\\published"
                        layerCIM.dataConnection.workspaceConnectionString = new_s3_workspace
                    else:
                        new_query = f"select * from hydrovis.{schema}.{service_name}"
                        try:
                            query = layerCIM.featureTable.dataConnection.sqlQuery.lower()
                            if " from " not in query:
                                raise Exception("No current valid query")
                            else:
                                db_source = query.split(" from ")[-1]
                                table_name = db_source.split(".")[-1]
                                new_db_source = f"hydrovis.{schema}.{table_name}"
                                new_query = query.replace(db_source, new_db_source)
                        except Exception as e:
                            print(f"no existing query - {e}")

                        layerCIM.featureTable.dataConnection.sqlQuery = new_query

                        old_dataset = layerCIM.featureTable.dataConnection.dataset
                        alias = old_dataset.split(".")[-1]
                        new_dataset = f"hydrovis.{schema}.{alias}"
                        layerCIM.featureTable.dataConnection.dataset = new_dataset

                        layerCIM.featureTable.dataConnection.workspaceConnectionString = conn_str

                        try:
                            delattr(layerCIM.featureTable.dataConnection, 'queryFields')
                        except Exception:
                            print("No querFields to delete")

                    layer.setDefinition(layerCIM)

                print('Updating the connectionProperties of each table...')
                for table in m.listTables():
                    if not table.connectionProperties:
                        continue

                    tableCIM = table.getDefinition('V2')

                    new_query = f"select * from hydrovis.{schema}.{service_name}"
                    try:
                        query = tableCIM.dataConnection.sqlQuery.lower()
                        if " from " not in query:
                            raise Exception("No current valid query")
                        else:
                            db_source = query.split(" from ")[-1]
                            table_name = db_source.split(".")[-1]
                            new_db_source = f"hydrovis.{schema}.{table_name}"
                            new_query = query.replace(db_source, new_db_source)
                    except Exception as e:
                        print(f"no existing query - {e}")

                    tableCIM.dataConnection.sqlQuery = new_query

                    old_dataset = tableCIM.dataConnection.dataset
                    alias = old_dataset.split(".")[-1]
                    new_dataset = f"hydrovis.{schema}.{alias}"
                    tableCIM.dataConnection.dataset = new_dataset

                    tableCIM.dataConnection.workspaceConnectionString = conn_str

                    try:
                        delattr(tableCIM.dataConnection, 'queryFields')
                    except Exception:
                        print("No querFields to delete")

                    table.setDefinition(tableCIM)

                aprx.save()

                m = aprx.listMaps()[0]

                experimental_addition = """
                    <br><br>The NWS is accepting comments through December 31, 2022 on the Experimental NWC Visualization Services. 
                    This service is one of many Experimental NWC Visualization Services. 
                    Please provide feedback on the Experimental NWC Visualization Services at: https://www.surveymonkey.com/r/Exp_NWCVisSvcs_2022
                    <br><br>Link to graphical web page: https://www.weather.gov/owp/operations
                    <br><br>Link to data download (shapefile): TBD
                    <br><br>Link to metadata: https://nws.weather.gov/products/PDD/SDD_ExpNWCVisualizationServices_2022.pdf
                """
                
                description = self.description
                if self.public_service:
                    description = description + experimental_addition

                # Create MapImageSharingDraft and set service properties
                self._log.info("Creating MapImageSharingDraft and setting service properties...")

                sharing_draft = m.getWebLayerSharingDraft("FEDERATED_SERVER", "MAP_IMAGE", service_name)
                sharing_draft.copyDataToServer = False
                sharing_draft.overwriteExistingService = True
                sharing_draft.serverFolder = self.folder_name
                sharing_draft.summary = summary
                sharing_draft.tags = self.tags
                sharing_draft.description = description
                sharing_draft.credits = self.item_credits
                sharing_draft.serviceName = service_name
                sharing_draft.offline = True

                self._log.info(f"Exporting MapImageSharingDraft to SDDraft file at {sddraft_output_filename}...")
                sharing_draft.exportToSDDraft(sddraft_output_filename)

                # Read the sddraft xml.
                doc = DOM.parse(sddraft_output_filename)

                typeNames = doc.getElementsByTagName('TypeName')
                for typeName in typeNames:
                    if typeName.firstChild.data == "MapServer":
                        extension = typeName.parentNode
                        definition = extension.getElementsByTagName("Definition")[0]
                        props = definition.getElementsByTagName("Props")[0]
                        property_sets = props.getElementsByTagName("PropertySetProperty")
                        for prop in property_sets:
                            key = prop.childNodes[0].childNodes[0].data
                            if key == "MinInstances":
                                prop.childNodes[1].childNodes[0].data = 1
                                
                            if key == "MaxInstances":
                                prop.childNodes[1].childNodes[0].data = 5
                    
                    if typeName.firstChild.data == "WMSServer" and self.public_service:
                        extension = typeName.parentNode
                        extension.getElementsByTagName("Enabled")[0].firstChild.data = "true"
                        
                    if typeName.firstChild.data == "FeatureServer" and self.enable_feature_service:
                        extension = typeName.parentNode
                        extension.getElementsByTagName("Enabled")[0].firstChild.data = "true"
                        
                        info = extension.getElementsByTagName("Info")[0]
                        property_sets = info.getElementsByTagName("PropertySetProperty")
                        for prop in property_sets:
                            key = prop.childNodes[0].childNodes[0].data
                            if key == "WebCapabilities":
                                prop.childNodes[1].childNodes[0].data = "Query"
                                
                            if key == "allowGeometryUpdates":
                                prop.childNodes[1].childNodes[0].data = "false"  
                    
                    if typeName.firstChild.data == "WFSServer" and self.public_service and self.enable_feature_service:
                        extension = typeName.parentNode
                        extension.getElementsByTagName("Enabled")[0].firstChild.data = "true"

                    # Output to a new sddraft.
                    splitext = os.path.splitext(sddraft_output_filename)
                    sddraft_mod_xml_file = splitext[0] + "_mod" + splitext[1]
                    f = open(sddraft_mod_xml_file, 'w')
                    doc.writexml(f)
                    f.close()

                    sddraft_output_filename = sddraft_mod_xml_file

                for server in servers:
                    if "server" in server.url or "egis-gis" in server.url:
                        publish_server = server
                        break

            elif self.service_type == 'ImageService':
                try:
                    self.delete_image_service()
                except Exception:
                    print("Service does not exist.")

                if self.create_referenced_md:
                    self._log.info("--> Creating Referenced Mosaic Dataset")
                    md_name = os.path.basename(self.image_service_data).split(".")[0]
                    published_reference_folder = os.path.join(
                        consts.PUBLISHED_ROOT, self.server_name,
                        consts.REFERRENCED_MOSAIC_FOLDER_NAME, self.service_name
                    )
                    published_reference_gdb = os.path.join(published_reference_folder, self.geodatabase_name)
                    published_reference_md = os.path.join(published_reference_gdb, md_name)

                    if not arcpy.Exists(self.image_service_data):
                        raise Exception(f"{self.image_service_data} does not exist")

                    if not os.path.exists(published_reference_folder):
                        os.makedirs(published_reference_folder)

                    if arcpy.Exists(published_reference_gdb):
                        arcpy.Delete_management(published_reference_gdb)

                    arcpy.CreateFileGDB_management(published_reference_folder, self.geodatabase_name)

                    arcpy.management.CreateReferencedMosaicDataset(
                        self.image_service_data, published_reference_md
                     )

                    self.image_service_data = published_reference_md

                if not arcpy.Exists(self.image_service_data):
                    raise Exception(f"{self.image_service_data} does not exist")

                sharing_draft = arcpy.CreateImageSDDraft(self.image_service_data,
                                                         out_sddraft=sddraft_output_filename,
                                                         service_name=service_name,
                                                         copy_data_to_server=False,
                                                         folder_name=self.folder_name,
                                                         summary=summary,
                                                         tags=self.tags)

                for server in servers:
                    if "image" in server.url or "egis-img" in server.url:
                        publish_server = server
                        break

            else:
                raise Exception("service_type must be MapService or ImageService")

            self._log.info("Staging the service...")
            sd_filename = self.service_name + ".sd"
            sd_output_filename = os.path.join(workspace, sd_filename)
            arcpy.StageService_server(sddraft_output_filename, sd_output_filename)

            self._log.info("Publishing the service...")
            if not publish_server:
                raise Exception("Could not find an appropriate server for publishing")

            publish_server.publish_sd(sd_output_filename)
            self._log.info("Successfully published service!")

            service_type = " ".join(re.findall('[A-Z][^A-Z]*', self.service_type))
            portal_content = gis.content.search(service_name, item_type=service_type)
            egis_item = [item for item in portal_content if item.title == service_name][0]

            if self.public_service or os.environ['VIZ_ENVIRONMENT'] in ['dev', 'ti']:
                egis_item.share(org=True, everyone=True)
                print(f"---> Updated {service_name} sharing to org and public in Portal.")
            else:    
                egis_item.share(org=True)
                print(f"---> Updated {service_name} sharing to org in Portal.")
                
            egis_item.update({"accessInformation": self.item_credits, "description": self.description})

        except Exception as e:
            raise e
        finally:
            shutil.rmtree(workspace)

        # Write published file to act as flag to not publish again
        self.create_publish_flag_file()

    def delete_service(self):
        """
            Deletes service
        """
        if self.server_name == "nonservice":
            self._log.info(f"Skipping EGIS delete for {self.service_name}")
            return

        success = False

        token = self._get_token(a_server=self.server_name)
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        mapservice_service_name = f"{self.folder_name}/{service_name}.MapServer"
        imageservice_service_name = f"{self.folder_name}/{service_name}.ImageServer"

        mapservice_post_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/{mapservice_service_name}/delete"
        )

        imageservice_post_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/{imageservice_service_name}/delete"
        )

        data = {
            'token': token,
            'f': 'json'
        }

        if self.server_name == consts.IMAGE_SERVER:
            primary_post_url = imageservice_post_url
            secondary_post_url = mapservice_post_url
        else:
            primary_post_url = mapservice_post_url
            secondary_post_url = imageservice_post_url

        try:
            response = requests.post(primary_post_url, data=data)
        except requests.exceptions.SSLError:
            response = requests.post(primary_post_url, data=data, verify=False)

        if response.status_code != 200:
            print(f"Attempt to delete failed: {response.content}")
        else:
            response_obj = response.json()
            success = True
            if 'status' not in response_obj:
                success = False
                print(f"Attempt to delete failed: {response_obj}")
            elif response_obj['status'] == 'error':
                success = False
                print(f"Attempt to delete failed: {response_obj}")

        if success:
            self._log.info("Service was deleted successfully.")
            return
        else:
            try:
                response = requests.post(secondary_post_url, data=data)
            except requests.exceptions.SSLError:
                response = requests.post(secondary_post_url, data=data, verify=False)

            if response.status_code != 200:
                print(f"Attempt to delete failed: {response.content}")
            else:
                response_obj = response.json()
                success = True
                if 'status' not in response_obj:
                    success = False
                    print(f"Attempt to delete failed: {response_obj}")
                if response_obj['status'] == 'error':
                    success = False
                    print(f"Attempt to delete failed: {response_obj}")

        if success:
            self._log.info("Service was deleted successfully.")

    def update_service_properties(self):
        self._log.info("Updating service properties...")
        properties = self.get_service_properties()

        properties['maxInstancesPerNode'] = self.max_service_instances
        properties['recycleInterval'] = 8760
        properties['description'] = self.description
        properties['properties']['description'] = self.description
        properties['properties']['copyright'] = self.item_credits
        properties['properties']['antialiasingMode'] = 'Fast'
        properties['properties']['hasStaticData'] = 'false'
        properties['properties']['schemaLockingEnabled'] = 'false'

        if self.service_type == "ImageService":
            properties['properties']['hasLiveData'] = 'true'
            properties['properties']['path'] = self.image_service_data

        token = self._get_token(a_server=self.server_name)
        service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
        full_service_name = f'{self.folder_name}/{service_name}' if self.folder_name else service_name

        post_url = (
            f"https://{self.server_host}/{self.server_name}/admin/services/"
            f"{full_service_name}.{self.rest_service_type}/edit"
        )

        data = {
            'token': token,
            'f': 'json',
            'service': json.dumps(properties)
        }

        try:
            response = requests.post(post_url, data=data)
        except requests.exceptions.SSLError:
            response = requests.post(post_url, data=data, verify=False)

        if response.status_code != 200:
            raise Exception(f"Attempt to update service properties failed: {response.content}")
        else:
            response_obj = response.json()
            if 'status' not in response_obj:
                raise Exception(f"Attempt to update service properties failed: {response_obj}")
            if response_obj['status'] == 'error':
                raise Exception(f"Attempt to update service properties failed: {response_obj}")

        self._log.info("Service properties were updated successfully.")

    def _post_process(self, process_event_time, published_data_location):
        pass

    def _post_publish(self, process_event_time, published_data_location):
        pass

    def execute(self, a_event_time, a_input_files, a_next_event_time=None):
        """
        Extends the PublishingProcess.execute method with additional steps to accomplish updating the services on the
        EGIS system. There are three primary tasks done by execute:
            1. Execute the processing by calling _process().
            2. Update the data in the published directory.
            3. Update properties on the service such as time stamps.

        Args:
            a_event_time (str): Serialized datetime corresponding with this processing event.
            a_input_files (str): Path to file with serialized list of files to be processed.
            a_event_time (str): Serialized datetime corresponding with the next expected processing event.

        Returns:
            bool: True if successful
        """
        success = False
        current_working_location = None
        try:
            self.process_event_time = dt.datetime.strptime(a_event_time, mon_consts.DATE_FORMAT)
            self.pretty_event_datetime = a_event_time
            self.next_process_event_time = dt.datetime.strptime(a_next_event_time, mon_consts.DATE_FORMAT) if a_next_event_time else None  # noqa: E501
            self.input_files = []

            # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
            self._log.info(mon_consts.EXECUTE_CALLED_TEXT, self.pretty_event_datetime)

            if not os.path.exists(self.workspace_location):
                self._makedirs(self.workspace_location)

            DO_PUBLISH = self.check_for_publish_flag_file()

            if not os.path.exists(self.published_data_location):
                if DO_PUBLISH:
                    self._makedirs(self.published_data_location)
                else:
                    raise Exception(f"The published_data_location must be an existing directory: "
                                    f"{self.published_data_location}")

            if not os.path.exists(a_input_files):
                raise Exception(f'Could not find file containing file list: "{a_input_files}"')

            with open(a_input_files) as files_list_file:
                content = files_list_file.read()
                self.input_files = json.loads(content)

            self._log.debug(f'Input files: {self.input_files}')

            # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
            self._log.info(mon_consts.VALIDATING_WORKSPACE_TEXT, self.pretty_event_datetime)
            current_working_location = self._get_working_location_path_for_event(self.process_event_time)
            try:
                self._validate_working_location(current_working_location, deep_check=True)
            except Exception as e:
                self._log.warning(f'Workspace for {self.pretty_event_datetime} invalid. Re-creating it now. ({e})')
                self._create_working_location(current_working_location)

            # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
            self._log.info(mon_consts.EXECUTING_PROCESSING_TEXT, self.pretty_event_datetime)
            processing_output_location = current_working_location
            potential_geodb_location = os.path.join(current_working_location, self.geodatabase_name)
            if os.path.exists(potential_geodb_location):
                processing_output_location = potential_geodb_location

            self._process(self.process_event_time, self.input_files, processing_output_location)

            if not self.one_off:
                # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
                self._log.info(mon_consts.UPDATING_DATA_TEXT, self.pretty_event_datetime)
                self._swap_data(current_working_location)

            self._post_process(self.process_event_time, self.published_data_location)

            if not self.one_off:
                self._log.debug(f'Acquiring lockfile to update service at {self.service_lockfile}...')
                service_lock = filelock.FileLock(self.service_lockfile)
                with service_lock:
                    # Check for "published" file. If it does not exist, publish the service and create it
                    if DO_PUBLISH:
                        # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
                        self._log.info(mon_consts.PUBLISHING_SERVICE_TEXT, self.pretty_event_datetime)

                        self.publish_service()

                        # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
                        self._log.info(mon_consts.UPDATING_SERVICE_PROPS_TEXT, self.pretty_event_datetime)
                        try:
                            self.update_service_properties()
                        except Exception as e:
                            self._log.warning(e)

                    service_name = f'{self.service_name}{consts.SERVICE_NAME_TAG}'
                    self._start_or_stop_service_rest('stop', self.server_name, self.folder_name, service_name)
                    time.sleep(10)
                    self._start_or_stop_service_rest('start', self.server_name, self.folder_name, service_name)

                self._post_publish(self.process_event_time, self.published_data_location)

                success = True
                # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
                self._log.info(mon_consts.EXECUTE_SUCCESS_TEXT, self.pretty_event_datetime)

        except Exception as e:
            self._log.error(
                f'Processing for {self.pretty_event_datetime} failed with the following details:'
                f'\n{str(e)}\n{traceback.format_exc()}'
            )
        else:
            self._log.info('Cleaning input file...')
            os.remove(a_input_files)

            # Handle caching
            if self.output_cache_days > 0 or self.one_off:
                if current_working_location:
                    if self.one_off:
                        self._log.info(f'Moving one off processed data to {self.cache_location}')
                    else:
                        self._log.info('Moving current workspace to cache...')
                    # Move working location to cache
                    self._copy_dir(current_working_location, self.cache_location, include_root=True)
        finally:
            if not self.one_off:
                self._log.info('Cleaning cache...')
                self._clean_cache()
                self._log.info('Cleaning workspace...')
                self._clean_workspace()

                if self.next_process_event_time:
                    self._log.info(f'Creating workspace for next event to process: {a_next_event_time}')
                    next_working_location = self._get_working_location_path_for_event(self.next_process_event_time)
                    try:
                        self._create_working_location(next_working_location)
                    except Exception as e:
                        self._log.warning(str(e))

        return success

    def check_for_publish_flag_file(self):
        if consts.FLAGS_ROOT.startswith(r"s3://"):
            s3_resource = boto3.resource('s3')
            s3_bucket = self.service_published_file.split("/", 3)[2]
            s3_key = f'{self.service_published_file.split("/", 3)[3]}/{self.service_name}'

            DO_PUBLISH = False
            try:
                s3_resource.Object(s3_bucket, s3_key).load()
            except Exception:
                DO_PUBLISH = True
        else:
            DO_PUBLISH = not os.path.isfile(self.service_published_file)

        return DO_PUBLISH

    def create_publish_flag_file(self):
        if consts.FLAGS_ROOT.startswith(r"s3://"):
            tmp_published_file = os.path.join(os.getenv("TEMP"), str(uuid.uuid4()))
            open(tmp_published_file, 'a').close()

            s3_bucket = self.service_published_file.split("/", 3)[2]
            s3_key = f'{self.service_published_file.split("/", 3)[3]}/{self.service_name}'

            s3 = boto3.client('s3')
            s3.upload_file(tmp_published_file, s3_bucket, s3_key, ExtraArgs={'ServerSideEncryption': 'aws:kms'})

            os.remove(tmp_published_file)
        else:
            open(self.service_published_file, 'a').close()

    def image_server_postprocess(self, gdb_name, mosaic_name, rasters, process_event_time, published_data_location,
                                 new_name_dict, symbology, time_field):
        arcpy.env.overwriteOutput = True
        arcpy.AddMessage("Post Processing Published Data")
        mosaic_gdb = os.path.join(published_data_location, f"{gdb_name}.gdb")
        mosaic_ds = os.path.join(mosaic_gdb, mosaic_name)
        self.create_referenced_md = True
        self.image_service_data = mosaic_ds

        if not arcpy.Exists(mosaic_gdb):
            arcpy.AddMessage("--> Creating GDB")
            arcpy.CreateFileGDB_management(published_data_location, f"{gdb_name}.gdb")

        if self.check_for_publish_flag_file():
            if not arcpy.Exists(mosaic_ds):
                arcpy.AddMessage("--> Creating Mosaic Dataset")
                proj = "PROJCS['WGS_1984_Web_Mercator_Auxiliary_Sphere',GEOGCS['GCS_WGS_1984',DATUM['D_WGS_1984'" \
                       ",SPHEROID['WGS_1984',6378137.0,298.257223563]],PRIMEM['Greenwich',0.0],UNIT['Degree'" \
                       ",0.0174532925199433]],PROJECTION['Mercator_Auxiliary_Sphere'],PARAMETER['False_Easting',0.0]" \
                       ",PARAMETER['False_Northing',0.0],PARAMETER['Central_Meridian',0.0],PARAMETER[" \
                       "'Standard_Parallel_1',0.0],PARAMETER['Auxiliary_Sphere_Type',0.0],UNIT['Meter',1.0]]"
                arcpy.CreateMosaicDataset_management(mosaic_gdb, mosaic_name, proj)
            else:
                arcpy.AddMessage("--> Removing Rasters to Mosaic Dataset")
                arcpy.management.RemoveRastersFromMosaicDataset(mosaic_ds, "OBJECTID>=0")

            arcpy.AddMessage("--> Adding Rasters to Mosaic Dataset")
            arcpy.management.AddRastersToMosaicDataset(mosaic_ds, "Raster Dataset", rasters)
            update_field_name(mosaic_ds, new_name_dict)
            arcpy.SetMosaicDatasetProperties_management(mosaic_ds, resampling_type='NEAREST',
                                                        processing_templates=symbology,
                                                        default_processing_template=symbology,
                                                        transmission_fields=f"Name;{time_field};update_time")

        add_ref_time(mosaic_ds, process_event_time, field_name=time_field, method='calculate_field')
        add_update_time(mosaic_ds, method='calculate_field')
