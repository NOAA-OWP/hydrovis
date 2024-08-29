# Replace and Route

A near real-time system that leverages the NWM data assimilation and channel routing capabilities to extend official flood forecasts issued by RFCs to all river reaches downstream of RFC forecast points by routing the forecasts through the river network to the next downstream forecast point. 

Key Features of Replace and Route:
- Deploys a message broker architecture to process incoming RFC forecasts
- Utilizes v20.1 of the enterprise hydrofabric
- Routes forecasted flow to downstream RFC locations 
- Uses docker compose to manage architecture
- Uses a jupyter-notebook to view and manage code through a container

<img src="docs/API_spec.png" alt="isolated" width="750"/>

## Installation

1. Install a virtual environment and download dependencies

```shell
pip install uv
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

2. Make sure docker compose is installed on your system
- https://docs.docker.com/compose/install/

3. Start the service
```shell
docker compose up
```

4. View swagger docs for the services

Each of the URLS corresponds to one of the services:

- Publisher app:
  - localhost:8000/docs
- Front-end:
  - localhost:8001/frontend/v1/plot
- T-route
  - localhost:8004/docs
- hfsubset
  - localhost:8008/docs
- jupyter
  - localhost:8888/lab


## Dependencies

The following containers are utilized 
1. RabbitMQ
  - rabbitmq:3.13-management
2. Mock DB
  - ghcr.io/taddyb33/hydrovis/mock_database:0.0.1
3. HFsubset
  - ghcr.io/taddyb33/hfsubset-legacy:0.0.4
4. T-Route
  - ghcr.io/taddyb33/t-route-dev:0.0.2
5. Redis
  - redis:7.2.5

## Usage

Follow the installation to get to the API services. 

To download RFC data based on the mock DB LIDS, run the following command once the DB is up:

```shell
curl -X 'POST' \
  'http://localhost:8000/api/v1/rfc/build_rfc_geopackages' \
  -H 'accept: application/json' \
  -d ''
```

## How to test the software

Run the following command from the project's home dir
```sh
pytest -s
```

## Known issues

- Since there are only 170 locations in the mock DB, this is just a subset of all locations. So, there will be errors if there is no found LID in the DB (This happens oftern)

## Getting help

If you have questions, concerns, bug reports, etc, please file an issue in this repository's Issue Tracker.

## Getting involved

This section should detail why people should get involved and describe key areas you are
currently focusing on; e.g., trying to get feedback on features, fixing certain bugs, building
important pieces, etc.

General instructions on _how_ to contribute should be stated with a link to [CONTRIBUTING](CONTRIBUTING.md).


----

## Open source licensing info
1. [TERMS](TERMS.md)
2. [LICENSE](LICENSE)


----

## Credits and References

Credits to the following developers:
- Tadd Bindas @taddyb33
- David Martin @david-w-martin

Also, thank you to all OWP members / collaborators
- Shawn Crawley
- Fernando Salas
- Derek G
- Nels Frazier (T-Route dev)
- Mike Johnson (Hydrofabric dev)