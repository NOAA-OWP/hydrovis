import requests
import os

def lambda_handler(event, context):
    gis_host = os.environ['GIS_HOST']
    portal_healthy = check_portal_health(gis_host)
    
    if not portal_healthy:
        raise Exception(f"{gis_host} portal is unhealthy")
        
    image_healthy = check_server_health(gis_host, "image")

    if not image_healthy:
        raise Exception(f"{gis_host} image server is unhealthy")
        
    server_healthy = check_server_health(gis_host, "server")
    
    if not server_healthy:
        raise Exception(f"{gis_host} gis server is unhealthy")
        
    print(f"{gis_host} portals and servers are healthy")
    
def check_portal_health(gis_host):
    res = requests.get(f"https://{gis_host}/portal/portaladmin/healthCheck?f=json").json()
    healthy = True if res['status'] == "success" else False
    
    return healthy
    
def check_server_health(gis_host, server_name):
    res = requests.get(f"https://{gis_host}/{server_name}/rest/info/healthCheck?f=json").json()
    healthy = res['success']
    
    return healthy
