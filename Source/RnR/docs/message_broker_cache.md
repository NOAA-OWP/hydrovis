# Message Broker and Cache

The message broker is a piece of software that is used to take message bodies from the Publisher, sort them, then post the messages. Redis caching is used to make sure we are only running the workflow as required when there are new forecasts

![alt text](photos/message_broker_and_cache.png)

## What is its job?

Hold messages in a queue based on priority so the consumer can successfully route them, or cache data that has already been routed. There are three queues:
1. Priority:
- For locations that are experiencing flooding
2. Base:
- For all other locations
3. Error: For all Locations that cause errors / trigger exceptions. 

## How is this accessed

The publisher calls the message broker internally, same with caching. 

## What is the port?
- To view the rabbit MQ portal, go to localhost:15672

![alt text](photos/rabbit_mq.png)
