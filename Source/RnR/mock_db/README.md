# Mock DB:
- This dir contains information from PI-2 to setup a mock database to read RFC information from. 
- There is a missing `rnr_schema.dump` file that is missing as it is too large for Git

To create the mock DB, you can run
`docker build -t mock_db -f Dockerfile.mock_db . `

or, you can reference the github container registry image similar to how compose does it:
```yaml
  mock_db:
    image: ghcr.io/taddyb33/hydrovis/mock_database:0.0.1
    environment:
      - POSTGRES_PASSWORD=pass123
      - POSTGRES_USER=postgres
      - POSTGRES_DB=vizprocessing
    ports:
      - "5432:5432"

```