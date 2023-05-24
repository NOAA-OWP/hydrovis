import boto3
import os
import time
from arcgis.gis import GIS
from viz_classes import s3_file
import yaml

def lambda_handler(event, context):
    
    s3 = boto3.client('s3')
    folder = event['folder']
    service_name = event['args']['service']
    service_metadata = get_service_metadata(folder, service_name)
    
    service_tag = os.getenv('SERVICE_TAG')
    service_name_publish = service_name + service_tag
    folder = service_metadata['egis_folder']
    summary = service_metadata['summary']
    description = service_metadata['description']
    tags = service_metadata['tags']
    credits = service_metadata['credits']
    server = service_metadata['egis_server']
    public_service = True if service_tag == "_alpha" else service_metadata['public_service']
    publish_flag_bucket = os.getenv('PUBLISH_FLAG_BUCKET')
    publish_flag_key = f"published_flags/{server}/{folder}/{service_name}/{service_name}"

    print("Attempting to Initialize the ArcGIS GIS class with the EGIS Portal.")
    # Connect to the GIS
    try:
        gis = GIS(os.getenv('GIS_HOST'), os.getenv('GIS_USERNAME'), os.getenv('GIS_PASSWORD'), verify_cert=False)
    except Exception as e:
        print("Failed to connect to the GIS")
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

    # Check to see if the service already exists and a publish flag is present or not.
    matching_services = [service for service in publish_server.services.list(folder=folder) if service.properties['serviceName'] == service_name or service.properties['serviceName'] == service_name_publish]  # noqa: E501
    publish_flag = s3_file(publish_flag_bucket, publish_flag_key).check_existence()
    if len(matching_services) > 0 and publish_flag is True:
        print(f"{matching_services[0].properties['serviceName']} is already online.")
        print(f"{service_name} already published")
        publish = False
    elif len(matching_services) > 0 and publish_flag is False:
        print(f"{matching_services[0].properties['serviceName']} is already online, but a publish flag isn't. Attempting to republish.")
        publish = True
    else:
        print(f"{service_name_publish} does not currently exist on EGIS. Attempting to publish.")
        publish = True
        
    if publish is True:  
        # Check to see if an sd file is present on s3
        sd_s3_path = os.getenv('SD_S3_PATH') + service_name + '.sd'
        
        if not s3_file(os.getenv('S3_BUCKET'), sd_s3_path).check_existence():
            print(f"---> {sd_s3_path} does not currently exist. Skipping.")
        else:
            print(f"---> An sd file for {service_name} is present on S3. Proceeding with publish.")
            local_sd_file = f'/tmp/{service_name}.sd'
            s3.download_file(os.getenv('S3_BUCKET'), sd_s3_path, local_sd_file)
            print(f"---> Downloaded {sd_s3_path}")
            # Publish the service
            publish_server.services.publish_sd(sd_file=local_sd_file, folder=folder)
            print(f"---> Published {sd_s3_path}")

            # Find the new service and update its item properties and sharing to match what's in the db
            # (yes, the ArcGIS Python API uses another class to do this for some reason)
            try:
                portal_contents = gis.content.search(service_name, item_type='Map Service')
                new_item = [item for item in portal_contents if item.title == service_name_publish][0]
            except IndexError as e:
                print(f"Error: Didn't find the just published {service_name} on portal: {portal_contents}")
                raise e
            new_item.update(item_properties={'snippet': summary, 'description': description,
                            'tags': tags, 'accessInformation': credits})
            
            print(f"---> Updated {service_name} descriptions, tags, and credits in Portal.")
            if public_service:
                new_item.share(org=True, everyone=True)
                print(f"---> Updated {service_name} sharing to org and public in Portal.")
            else:    
                new_item.share(org=True)
                print(f"---> Updated {service_name} sharing to org in Portal.")

            # Ensuring that the description for the service matches the iteminfo
            matching_service = matching_services[0]
            if not matching_service.properties['description']:
                print("Updating service property description to match iteminfo")
                service_properties = matching_service.properties
                service_properties['description'] = matching_service.iteminformation.properties['description']
                matching_service.edit(dict(service_properties))
            
            # Create publish flag file
            tmp_published_file = f"/tmp/{service_name}"
            open(tmp_published_file, 'a').close()
            s3.upload_file(tmp_published_file, publish_flag_bucket, publish_flag_key, ExtraArgs={'ServerSideEncryption': 'aws:kms'})
            print(f"---> Created publish flag {publish_flag_key} on {publish_flag_bucket}.")

            os.remove(local_sd_file)
            print(f"---> Successfully published {service_name} using {sd_s3_path}.")
            
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
