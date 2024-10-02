# Consumer 

![alt text](photos/consumer.png)

## What is its job?

The data consumer pulls messages from the message queue and runs a series of microservices on the message json body:
1. Reads in the message
2. Processes the forecast into T-Route inputs
3. Determines the HYFeatures ID
4. Runs T-Route
5. Post-processes and plots the data

## How is this accessed

The consumer is an asynchronous task that is spun up using the docker compose and will await messages from the queue

```yaml
  consumer:
    build:
      context: .
      dockerfile: Dockerfile.app
    restart: always
    volumes:
      - type: bind
        source: ./data
        target: /app/data
    environment:
      - PIKA_URL=rabbitmq
      - RABBITMQ_HOST=rabbitmq
      - SQLALCHEMY_DATABASE_URL=postgresql://{}:{}@{}/{}
      - DB_HOST=mock_db
      - REDIS_URL=redis
      - SUBSET_URL=http://hfsubset:8000/api/v1
      - TROUTE_URL=http://troute:8000/api/v1
    command: sh -c ". /app/.venv/bin/activate && python src/rnr/app/consumer_manager.py"
    depends_on:
      redis:
        condition: service_started
      troute:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
```