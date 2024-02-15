# Esri start of added imports
import sys, os, arcpy
# Esri end of added imports

# Esri start of added variables
g_ESRI_variable_1 = os.path.join(arcpy.env.packageWorkspace,'test\\Empty_Project.aprx')
# Esri end of added variables

import arcpy
import os
import re
import boto3
import base64
import tempfile
import json
import xml.dom.minidom as DOM

s3 = boto3.resource('s3')
s3_client = boto3.client('s3')
current_dir = os.path.dirname(os.path.abspath(__file__))
working_dir = tempfile.mkdtemp()
s3_connection_file_path = "\\connection_files\\HydroVis_S3_processing_outputs.acs"


def update_db_sd_file(service_name, service_summary, service_summary_suffix, service_description, service_public, service_feature,service_tags,service_credits,
                      egis_db_host, egis_db_username, egis_db_password, egis_db_database, egis_db_schema, egis_folder, deployment_bucket, s3_pro_project_path, s3_sd_path):
    mapx_s3_path = f"{s3_pro_project_path}/{service_name}.mapx"
    mapx_fpath = os.path.join(working_dir, f"{service_name}.mapx")
    baseline_aprx_path = os.path.join(current_dir, 'Empty_Project.aprx')
    temp_aprx_fpath = os.path.join(working_dir, f"{service_name}.aprx")

    arcpy.AddMessage(f"Downloading {deployment_bucket}/{mapx_s3_path}")
    s3_client.download_file(deployment_bucket, mapx_s3_path, mapx_fpath)

    conn_str = arcpy.management.CreateDatabaseConnectionString(
        "POSTGRESQL", egis_db_host, username=egis_db_username,
        password=egis_db_password, database=egis_db_database
    )
    conn_str = re.findall('<WorkspaceConnectionString>(.*)</WorkspaceConnectionString>', str(conn_str))[0]

    service_name = os.path.basename(mapx_fpath).split(".")[0]
    arcpy.AddMessage(f"Creating SD file for {service_name}...")
    
    temp_aprx = arcpy.mp.ArcGISProject(baseline_aprx_path)
    temp_aprx.importDocument(mapx_fpath)
    temp_aprx.saveACopy(temp_aprx_fpath)
    aprx = arcpy.mp.ArcGISProject(temp_aprx_fpath)
    
    sd_file = create_sd_file(aprx, service_name, working_dir, conn_str, service_summary, service_summary_suffix, service_description, service_public, service_feature,service_tags,service_credits, egis_db_schema, egis_folder)
    
    del temp_aprx
    del aprx
    os.remove(temp_aprx_fpath)

    arcpy.AddMessage(f"Uploading {sd_file} to {deployment_bucket}")
    s3_client.upload_file(
        sd_file, deployment_bucket,
        f"{s3_sd_path}/{os.path.basename(sd_file)}"
    )


def create_sd_file(aprx, service_name, working_dir, conn_str, service_summary, service_summary_suffix, service_description, service_public, service_feature,service_tags,service_credits, egis_db_schema, egis_folder):
    service_name_suffix = f"_{service_summary_suffix.lower()}"
    sd_service_name = f"{service_name}{service_name_suffix}"
    schema = egis_db_schema

    m = aprx.listMaps()[0]

    arcpy.AddMessage('Updating the connectionProperties of each layer...')
    for layer in m.listLayers():
        if not layer.connectionProperties:
            continue

        layerCIM = layer.getDefinition('V2')

        if layer.isRasterLayer:
            new_s3_workspace = f"DATABASE={s3_connection_file_path}\\{service_name}\\published"
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
                arcpy.AddMessage(f"no existing query - {e}")

            layerCIM.featureTable.dataConnection.sqlQuery = new_query

            old_dataset = layerCIM.featureTable.dataConnection.dataset
            alias = old_dataset.split(".")[-1]
            new_dataset = f"hydrovis.{schema}.{alias}"
            layerCIM.featureTable.dataConnection.dataset = new_dataset

            layerCIM.featureTable.dataConnection.workspaceConnectionString = conn_str

            try:
                delattr(layerCIM.featureTable.dataConnection, 'queryFields')
            except Exception:
                arcpy.AddMessage("No querFields to delete")

        layer.setDefinition(layerCIM)

    arcpy.AddMessage('Updating the connectionProperties of each table...')
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
            arcpy.AddMessage(f"no existing query - {e}")

        tableCIM.dataConnection.sqlQuery = new_query

        old_dataset = tableCIM.dataConnection.dataset
        alias = old_dataset.split(".")[-1]
        new_dataset = f"hydrovis.{schema}.{alias}"
        tableCIM.dataConnection.dataset = new_dataset

        tableCIM.dataConnection.workspaceConnectionString = conn_str

        try:
            delattr(tableCIM.dataConnection, 'queryFields')
        except Exception:
            arcpy.AddMessage("No querFields to delete")

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
    
    if service_public:
        service_description = service_description + experimental_addition

    service_summary = service_summary + service_summary_suffix
    
    # Create MapImageSharingDraft and set service properties
    arcpy.AddMessage(f"Creating MapImageSharingDraft and setting service properties for {sd_service_name}...")
    sharing_draft = m.getWebLayerSharingDraft("FEDERATED_SERVER", "MAP_IMAGE", sd_service_name)
    sharing_draft.copyDataToServer = False
    sharing_draft.overwriteExistingService = True
    sharing_draft.serverFolder = egis_folder
    sharing_draft.summary = service_summary
    sharing_draft.tags = service_tags
    sharing_draft.description = service_description
    sharing_draft.credits = service_credits
    sharing_draft.serviceName = sd_service_name
    sharing_draft.offline = True

    sddraft_filename = service_name + ".sddraft"
    sddraft_output_filename = os.path.join(working_dir, sddraft_filename)
    if os.path.exists(sddraft_output_filename):
        os.remove(sddraft_output_filename)

    arcpy.AddMessage(f"Exporting MapImageSharingDraft to SDDraft file at {sddraft_output_filename}...")
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
        
        if typeName.firstChild.data == "WMSServer" and service_public:
            extension = typeName.parentNode
            extension.getElementsByTagName("Enabled")[0].firstChild.data = "true"
            
        if typeName.firstChild.data == "FeatureServer" and service_feature:
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
        
        if typeName.firstChild.data == "WFSServer" and service_public and service_feature:
            extension = typeName.parentNode
            extension.getElementsByTagName("Enabled")[0].firstChild.data = "true"

    # Output to a new sddraft.
    splitext = os.path.splitext(sddraft_output_filename)
    sddraft_mod_xml_file = splitext[0] + "_mod" + splitext[1]
    f = open(sddraft_mod_xml_file, 'w')
    doc.writexml(f)
    f.close()

    sddraft_output_filename = sddraft_mod_xml_file

    sd_filename = service_name + ".sd"
    sd_output_filename = os.path.join(working_dir, sd_filename)
    if os.path.exists(sd_output_filename):
        os.remove(sd_output_filename)
    arcpy.StageService_server(sddraft_output_filename, sd_output_filename)

    os.remove(sddraft_output_filename)

    return sd_output_filename

# From AWS Docs
def get_secret_password(secret_name, region_name, key):
    """
        Gets a password from a sercret stored in AWS secret manager.

        Args:
            secret_name(str): The name of the secret
            region_name(str): The name of the region

        Returns:
            password(str): The text of the password
    """
    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager',region_name=region_name)
    get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            j = json.loads(secret)
            password = j[key]
    else:
        decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
        arcpy.AddMessage("password binary:" + decoded_binary_secret)
        password = decoded_binary_secret.password

    return password

def run():    
    # Args
    service_name = arcpy.GetParameterAsText(0)
    service_summary = arcpy.GetParameterAsText(1)
    service_summary_suffix = arcpy.GetParameterAsText(2)
    service_description = arcpy.GetParameterAsText(3)
    service_public = arcpy.GetParameterAsText(4)
    service_feature = arcpy.GetParameterAsText(5)
    service_tags = arcpy.GetParameterAsText(6)
    service_credits = arcpy.GetParameterAsText(7)
    egis_db_host = arcpy.GetParameterAsText(8)
    egis_db_username = arcpy.GetParameterAsText(9)
    egis_db_password = arcpy.GetParameterAsText(10)
    egis_db_password_secret_name = arcpy.GetParameterAsText(11)
    egis_db_database = arcpy.GetParameterAsText(12)
    egis_db_schema = arcpy.GetParameterAsText(13)
    egis_folder = arcpy.GetParameterAsText(14)
    deployment_bucket = arcpy.GetParameterAsText(15)
    s3_pro_project_path = arcpy.GetParameterAsText(16)
    s3_sd_path = arcpy.GetParameterAsText(17)

    if not egis_db_password:
        try:
            aws_region = 'us-east-1'
            egis_db_password = get_secret_password(egis_db_password_secret_name, aws_region, 'password')
        except:
            aws_region = 'us-east-2'
            egis_db_password = get_secret_password(egis_db_password_secret_name, aws_region, 'password')
    update_db_sd_file(service_name, service_summary, service_summary_suffix, service_description, service_public, service_feature,service_tags,service_credits,
                      egis_db_host, egis_db_username, egis_db_password, egis_db_database, egis_db_schema, egis_folder, deployment_bucket, s3_pro_project_path, s3_sd_path)

run()
