import boto3
import os
import time
from arcgis.gis import GIS
from viz_classes import s3_file
import yaml
import itertools

def lambda_handler(event, context):

	s3 = boto3.client('s3')
	s3_bucket = os.getenv('S3_BUCKET')
	s3_sd_path = os.getenv('SD_S3_PATH') # not to be confused with sd_s3_path
	egis_db_host = os.getenv('EGIS_DB_HOST')
	egis_db_username = os.getenv('EGIS_DB_USERNAME')
	egis_db_password = os.getenv('EGIS_DB_PASSWORD')
	egis_db_database = os.getenv('EGIS_DB_DATABASE')
	egis_db_password_secret_name = os.getenv('EGIS_DB_PASSWORD_SECRET_NAME')
	environment = os.getenv('ENVIRONMENT')
	folder = event['folder']
	service_name = event['args']['service']
	service_metadata = get_service_metadata(folder, service_name)
	service_tag = os.getenv('SERVICE_TAG')
	service_name_publish = service_name + service_tag
	folder = service_metadata['egis_folder'] # folder is hereafter reassigned after use in get_service_metadata above
	summary = service_metadata['summary']
	description = service_metadata['description']
	tags = service_metadata['tags']
	credits = service_metadata['credits']
	server = service_metadata['egis_server']
	public_service = True if service_tag == "_alpha" else service_metadata['public_service']
	feature_service = service_metadata['feature_service']
	publish_flag_bucket = os.getenv('PUBLISH_FLAG_BUCKET')
	publish_flag_key = f"published_flags/{server}/{folder}/{service_name}/{service_name}"

	print("Attempting to Initialize the ArcGIS GIS class with the EGIS Portal.")
	try:
		gis = GIS(os.getenv('GIS_HOST'), os.getenv('GIS_USERNAME'), os.getenv('GIS_PASSWORD'), verify_cert=False)
	except Exception as e:
		print("Failed to connect to the GIS.")
		raise e
	
	gis_servers = gis.admin.servers.list()
	publish_server = None
	for gis_server in gis_servers:
		if server == "server":
			if "server" in gis_server.url or "egis-gis" in gis_server.url:
				publish_server = gis_server
				break
		elif server == "image":
			if "image" in gis_server.url or "egis-img" in gis_server.url:
				publish_server = gis_server
				break
	if not publish_server:
		raise Exception(f"Could not find appropriate GIS server for {server}")

	counter = itertools.count(start=1)
	while True:
		# Check to see if the service already exists and a publish flag is present or not.
		time.sleep(30)
		# List comprehension to get requested service
		matching_services = [service for service in publish_server.services.list(folder=folder) if 'serviceName' in service.properties and (service.properties['serviceName'] == service_name or service.properties['serviceName'] == service_name_publish)]  # noqa: E501
		publish_flag = s3_file(publish_flag_bucket, publish_flag_key).check_existence()
		if len(matching_services) > 0 and publish_flag:
			print(f"{matching_services[0].properties['serviceName']} is already online and published.")
			print(f"{service_name} already published")
			publish = False
		elif len(matching_services) > 0 and not publish_flag:
			print(f"{matching_services[0].properties['serviceName']} is already online, but a publish flag isn't. Attempting to republish.")
			publish = True
		else:
			print(f"{service_name_publish} does not currently exist on EGIS. Attempting to publish.")
			publish = True

		if not publish:
			break

		if publish:
			sd_s3_path = f"{os.getenv('SD_S3_PATH')}/{service_name}.sd"
			if not s3_file(s3_bucket, sd_s3_path).check_existence():
				print(f"---> {sd_s3_path} does not currently exist. Attempting to publish via GP service.")
				i = next(counter)
				if i > 5:
					print(f"Retried gp service publish {i} times. Skipping {sd_s3_path}. Please investigate and republish manually using ArcGIS Rest Services Directory")
					break
				try:
					# Make POST request to GP Service to (re)create a service definition file in order to (re)publish.
					mapx_to_sd(service_name, summary, description, public_service, tags, credits, feature_service, s3_sd_path, gis, egis_db_host, egis_db_username, egis_db_password, egis_db_database, s3_bucket, environment, folder, egis_db_password_secret_name)
				except Exception as e:
					print("Error with publishing")
					raise e
				continue

			else:
				# If there was already an SD file, then publish. Otherwise the gp service should have created it and recalled this block
				print(f"---> An sd file for {service_name} is present on S3. Proceeding with publish.")
				local_sd_file = f'/tmp/{service_name}.sd'
				s3.download_file(s3_bucket, sd_s3_path, local_sd_file)
				print(f"---> Downloaded {sd_s3_path}")
				# Publish the service
				success = publish_server.services.publish_sd(sd_file=local_sd_file, folder=folder) # arcgis.gis.GIS publish_sd method
				print(f"Publish success: {success}")
				print(f"---> Published {sd_s3_path}")

				matching_services = [service for service in publish_server.services.list(folder=folder) if 'serviceName' in service.properties and (service.properties['serviceName'] == service_name or service.properties['serviceName'] == service_name_publish)]  # noqa: E501
				if not matching_services:
					print(f"Service not found, though supposedly published successfully. Removing SD file and recreating it...")
					os.remove(local_sd_file)
					s3.delete_object(Bucket=s3_bucket, Key=sd_s3_path)
					continue
				# Ensuring that the description for the service matches the iteminfo
				matching_service = matching_services[0]
				if not matching_service.properties['description']:
					print("Updating service property description to match iteminfo")
					service_properties = matching_service.properties
					service_properties['description'] = matching_service.iteminformation.properties['description']
					try:
						matching_service.edit(dict(service_properties))
					except:
						matching_service = [service for service in publish_server.services.list(folder=folder) if 'serviceName' in service.properties and (service.properties['serviceName'] == service_name or service.properties['serviceName'] == service_name_publish)][0]
						if not matching_service.properties['description']:
							raise Exception("Failed to update the map service description")
							
				portalItems = matching_service.properties["portalProperties"]['portalItems']

				for portalItem in portalItems:
					new_item = gis.content.get(portalItem['itemID'])
					new_item.update(item_properties={'snippet': summary, 'description': description, 'tags': tags, 'accessInformation': credits})
				
					print(f"---> Updated {portalItem} descriptions, tags, and credits in Portal.")
					if public_service:
						new_item.share(org=True, everyone=True)
						print(f"---> Updated {portalItem} sharing to org and public in Portal.")
					else:    
						new_item.share(org=True)
						print(f"---> Updated {portalItem} sharing to org in Portal.")
				
				# Create publish flag file
				tmp_published_file = f"/tmp/{service_name}"
				open(tmp_published_file, 'a').close()
				s3.upload_file(tmp_published_file, publish_flag_bucket, publish_flag_key, ExtraArgs={'ServerSideEncryption': 'aws:kms'})
				print(f"---> Created publish flag {publish_flag_key} on {publish_flag_bucket}.")
				os.remove(local_sd_file)
				print(f"---> Successfully published {service_name} using {sd_s3_path}.")
				publish = False
				
		if len(matching_services) > 0 and server == "image":
			matching_service = matching_services[0]
			service_started = True
			try:
				print(f"Stopping the {service_name} service")
				matching_service.stop()
				service_stopped = True
			except ValueError as e:
				print(f"Error starting {service_name}. Could be a timeout response issue. ({e})")
				print(f"Checking {service_name} service periodically to see if successful")
				attempts = 0
				while attempts <= 5:
					print(f"Waiting 20 seconds to {service_name} status")
					time.sleep(20)
					attempts += 1
					status = matching_service.status
					print(f"{service_name} status is {status}")
					service_stopped = True if status['configuredState']=='STOPPED' and status['realTimeState']=='STOPPED' else False
					if service_stopped:
						break
					
			if not service_stopped:
				raise Exception(f"{service_name} failed to stop in a timely manner")
			time.sleep(10)
			try:
				print(f"Starting the {service_name} service")
				matching_service.start()
				service_started = True
			except ValueError as e:
				print(f"Error starting {service_name}. Could be a timeout response issue. ({e})")
				print(f"Checking {service_name} service periodically to see if successful")
				attempts = 0
				while attempts <= 5:
					print(f"Waiting 20 seconds to {service_name} status")
					time.sleep(20)
					attempts += 1
					status = matching_service.status
					print(f"{service_name} status is {status}")
					service_started = True if status['configuredState']=='STARTED' and status['realTimeState']=='STARTED' else False
					if service_started:
						break
			if not service_started:
				raise Exception(f"{service_name} failed to start in a timely manner")
			print(f"{service_name} started successfully")
	return True
	
def get_service_metadata(folder, service_name):
	yml_path = os.path.join("services", folder, f"{service_name}.yml")

	service_stream = open(yml_path, 'r')
	service_metadata = yaml.safe_load(service_stream)
	
	return service_metadata

def mapx_to_sd(service_name, summary, description, public_service, tags, credits, feature_service, sd_files, gis, egis_db_host, egis_db_username, egis_db_password, egis_db_database, s3_bucket, environment, folder, egis_db_password_secret_name):
	service_suffix = ''
	subdomain = 'maps'
	if environment == 'ti':
		service_suffix = '_alpha'
		subdomain += '-testing'
	elif environment == 'uat':
		service_suffix = '_beta'
		subdomain += '-staging'

	payload = {
		'service_name': service_name,
		'service_summary': summary,
		'service_summary_suffix': service_suffix,
		'service_description': description,
		'service_public': public_service,
		'service_feature': feature_service,
		'service_tags': tags,
		'service_credits': credits,
		'egis_db_host': egis_db_host,
		'egis_db_username': egis_db_username,
		'egis_db_password': egis_db_password,
		'egis_db_password_secret_name': egis_db_password_secret_name, # needs value?
		'egis_db_database': egis_db_database,
		'egis_db_schema': 'services',
		'egis_folder': folder,
		'deployment_bucket': s3_bucket,
		's3_pro_project_path': 'viz/pro_projects', # needs to be set by terraform. mapx files directory
		's3_sd_path': sd_files,
		'returnZ': 'false',
		'returnM': 'false',
		'returnTrueCurves': 'false',
		'returnFeatureCollection': 'false',
		'context': '',
		'f': 'pjson'
	}

	request_url = f"https://{subdomain}.water.noaa.gov/gp/rest/services/Utilities/MapxToSD/GPServer/MapxToSD/execute"
	gis._con._session.post(request_url, data=payload, timeout=30)
