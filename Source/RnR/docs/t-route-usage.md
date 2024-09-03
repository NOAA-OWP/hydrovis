# T-Route Usage 

Our docker compose file uses a prebuilt docker image from T-Route to call T-Route as a service for river routing:

```yaml
troute:
image: ghcr.io/taddyb33/t-route-dev:0.0.2
ports:
    - "8004:8000"
volumes:
    - type: bind
    source: ./data/troute_output
    target: /t-route/output
    bind:
        selinux: z
    - type: bind
    source: ./data
    target: /t-route/data
    bind:
        selinux: z
command: sh -c ". /t-route/.venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000"
healthcheck:
    test: curl --fail -I http://localhost:8000/health || exit 1
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 5s
```

This searches the `ghcr.io/taddyb33/` container registry for a t-route-dev image. 

## Why an API?

T-Route is used in many contexts for hydrological river routing:
- NGEN 
- Scientific Python 
- Replace and Route (RnR)

In the latest PR for RnR, there is a requirement to run T-Route as a service. This service requires an easy way to dynamically create config files, restart flow from Initial Conditions, and run T-Route. To satisfy this requirement, a FastAPI endpoint was created in `/src/app` along with code to dynamically create t-route endpoints. 

## Why use shared volumes?

Since T-Route is running in a docker container, there has to be a connection between the directories on your machine and the directories within the container. We're sharing the following folders by default:
- `data/rfc_channel_forcings`
  - For storing RnR RFC channel domain forcing files (T-Route inputs)
- `data/rfc_geopackage_data`
  - For storing HYFeatures gpkg files 
  - Indexed by the NHD COMID, also called hf_id. Ex: 2930769 is the hf_id for the CAGM7 RFC forecast point. 
- `data/troute_restart`
  - For storing TRoute Restart files
- `data/troute_output`
  - For outputting results from the T-Route container