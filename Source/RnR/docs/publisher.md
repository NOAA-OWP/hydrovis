# Publisher

The data publisher section of the RnR event driven architecture is shown below. 

![alt text](photos/data_publisher.png)

## What is its job?

This application is spun up by docker compose and is tasked with:
1. Requesting RFC information from a DB
2. Pulling Forecasts from the RFC points
3. Formatting the forecasts in a json message body
4. Posting the forecasts to the Rabbit MQ message queue to be processed by the consumer

## How is this accessed

The publisher is pinged by the following localhost endpoints:
- /api/v1/publish/start
    - Runs the publish endpoint for all RFC 
- /api/v1/publish/{lid}
    - Runs the publish endpoint for a specific RFC location ID

## What is the port?
- localhost:8000/docs