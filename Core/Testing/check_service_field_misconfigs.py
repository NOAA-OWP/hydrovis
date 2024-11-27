from requests import Session
from pathlib import Path
import yaml
import json

from egis_helpers import get_token

PORTAL_URL = 'https://maps.water.noaa.gov/portal'
SERVER_URL_TEMPLATE = 'https://maps.water.noaa.gov/{server}'

THIS_DIR = Path(__file__).parent
CORE_DIR = THIS_DIR.parent
SERVICES_DIR = CORE_DIR / "LAMBDA" / "viz_functions" / "viz_publish_service" / "services"

SESSION = Session()

services_by_location = {}
server_services = []
for root, dirs, files in SERVICES_DIR.walk():
    for fname in files:
        if fname.endswith('.yml') and (root / fname.replace('.yml', '.mapx')).exists():
            with open(root / fname) as stream:
                service_config = yaml.safe_load(stream)
            server = service_config['egis_server']
            folder = service_config['egis_folder']
            if server not in services_by_location:
                services_by_location[server] = {}
            if folder not in services_by_location[server]:
                services_by_location[server][folder] = []
            service_name = fname.split('.')[0]
            services_by_location[server][folder].append(service_name)
            if server != "image":
                server_services.append(service_name)

service_iter_count = 0
service_count = len(server_services)
failures = {}
print(f"Beginning checks for {service_count} services...")
for server, folders in services_by_location.items():
    if server == "image": continue
    server_url = SERVER_URL_TEMPLATE.format(server=server)
    server_token = get_token(PORTAL_URL, server_url)
    for folder, services in folders.items():
        for service in services:
            service_iter_count += 1
            print(f"Checking {service_iter_count} of {service_count}...")
            service_root_url = f'{server_url}/rest/services/{folder}/{service}/MapServer'
            print(f"... {service_root_url}")
            service_info = SESSION.get(f'{service_root_url}?token={server_token}&f=json').json()
            if "error" in service_info:
                code = service_info["error"]["code"]
                message = service_info["error"]["message"]
                failures[service_root_url] = {"error": f"{code}: {message}"}
                continue
            
            for i, layer in enumerate(service_info['layers']):
                print(f"...... Checking layer {i}")
                layer_root_url = f'{service_root_url}/{layer["id"]}'
                layer_info = SESSION.get(f'{layer_root_url}?token={server_token}&f=json').json()
                if layer_info["type"] == "Group Layer": continue
                for field in layer_info["fields"]:
                    field_name = field['name']
                    if field_name == 'geom': continue
                    try:
                        query_url = f'{layer_root_url}/query?token={server_token}&where=1%3D1&outFields={field_name}&resultRecordCount=1&returnGeometry=false&f=json'
                        query_result = SESSION.get(query_url).json()
                        if "error" in query_result:
                            code = query_result["error"]["code"]
                            message = query_result["error"]["message"]
                            failures[query_url] = {"field": field, "error": f"{code}: {message}"}
                    except Exception as e:
                        failures[query_url] = {"field": field, "error": str(e)}

if failures:
    results_file = THIS_DIR / "service_field_results.json"
    print(f"Issues encountered. Writing results to {results_file}")
    results_file.write_text(json.dumps(failures, indent=2))
else:
    print("There were no issues encountered!")

print("FIN")