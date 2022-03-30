#!/bin/bash

echo "---- SETTING UP RABBITMQ ----"

MQINGESTENDPOINT="${MQINGESTENDPOINT}"
MQUSERNAME="${MQUSERNAME}"
MQPASSWORD="${MQPASSWORD}"
RFC_FCST_USER="${RFC_FCST_USER}"
RFC_FCST_USER_PASSWORD="${RFC_FCST_USER_PASSWORD}"
MQVHOST="${MQVHOST}"

### Get RabbitMQ Endpoint ###
RSCHEME="$${MQINGESTENDPOINT/:*}"
RPORT="$${MQINGESTENDPOINT##*:}"
RHOST=$(echo $${MQINGESTENDPOINT} | cut -d : -f 2 | tr -d "/")

echo "Adding $${MQVHOST} vhost to $${RHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     "https://$${RHOST}/api/vhosts/$${MQVHOST}"

echo "Removing default vhost to $${RHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X DELETE "https://$${RHOST}/api/vhosts/%2f"

echo "Adding $${RFC_FCST_USER} to $${RHOST}"
curl --trace-ascii /dev/stdout -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"password":"'"$${RFC_FCST_USER_PASSWORD}"'","tags":"none"}' \
     "https://$${RHOST}/api/users/$${RFC_FCST_USER}"

echo "Adding hml_event_queue queues for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"arguments":{"x-dead-letter-exchange":"dl.hml","x-dead-letter-routing-key":"dl_hml_event_queue"}}' \
     "https://$${RHOST}/api/queues/$${MQVHOST}/hml_event_queue"

echo "Adding xml_queue queues for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"arguments":{"x-dead-letter-exchange":"dl.hml","x-dead-letter-routing-key":"dl_xml_queue"}}' \
     "https://$${RHOST}/api/queues/$${MQVHOST}/xml_queue"

echo "Adding dl_xml_queue queues for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"arguments":{"x-dead-letter-exchange":"hml","x-dead-letter-routing-key":"xml_queue","x-message-ttl":60000}}' \
     "https://$${RHOST}/api/queues/$${MQVHOST}/dl_xml_queue"

echo "Adding dl_hml_event_queue queues for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"arguments":{"x-dead-letter-exchange":"hml","x-dead-letter-routing-key":"hml_event_queue","x-message-ttl":900000}}' \
     "https://$${RHOST}/api/queues/$${MQVHOST}/dl_hml_event_queue"

echo "Adding dl.hml exchange for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"internal": false,"arguments":{}}' \
     "https://$${RHOST}/api/exchanges/$${MQVHOST}/dl.hml"

echo "Adding hml exchange for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"auto_delete":false,"durable":true,"internal": false,"arguments":{}}' \
     "https://$${RHOST}/api/exchanges/$${MQVHOST}/hml"

echo "Binding dl.hml exchange to dl_hml_event_queue queue for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X POST \
     -d '{"routing_key":"dl_hml_event_queue", "arguments":{}}' \
     "https://$${RHOST}/api/bindings/$${MQVHOST}/e/dl.hml/q/dl_hml_event_queue"

echo "Binding dl.hml exchange to dl_xml_queue queue for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X POST \
     -d '{"routing_key":"dl_xml_queue", "arguments":{}}' \
     "https://$${RHOST}/api/bindings/$${MQVHOST}/e/dl.hml/q/dl_xml_queue"

echo "Binding hml exchange to hml_event_queue queue for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X POST \
     -d '{"routing_key":"hml_event_queue", "arguments":{}}' \
     "https://$${RHOST}/api/bindings/$${MQVHOST}/e/hml/q/hml_event_queue"

echo "Binding hml exchange to xml_queue queue for $${MQVHOST}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X POST \
     -d '{"routing_key":"xml_queue", "arguments":{}}' \
     "https://$${RHOST}/api/bindings/$${MQVHOST}/e/hml/q/xml_queue"

echo "Updating permissions for $${RFC_FCST_USER}"
curl -u $${MQUSERNAME}:$${MQPASSWORD} -H "content-type:application/json" -X PUT \
     -d '{"configure":".*","write":".*","read":".*"}' \
     "https://$${RHOST}/api/permissions/$${MQVHOST}/$${RFC_FCST_USER}"
