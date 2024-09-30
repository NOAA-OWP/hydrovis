#!/bin/bash

echo "Pulling image"
docker pull deltares/sfincs-cpu:sfincs-v2.0.3-Cauberg

echo "Copying data"
rm -rf /tmp/sfincs_temp/ && mkdir /tmp/sfincs_temp/
cp -r data/SFINCS/ngwpc_data /tmp/sfincs_temp/

echo "Running SFINCS"
sudo chmod -R 777 /tmp/sfincs_temp/
docker run -v /tmp/sfincs_temp/ngwpc_data/:/data:rw deltares/sfincs-cpu:sfincs-v2.0.3-Cauberg
sudo chmod -R 777 /tmp/sfincs_temp/

echo "Copying Data"
cp -r /tmp/sfincs_temp/ngwpc_data/sfincs_map.nc data/SFINCS/ngwpc_data/

echo "Done Running SFINCS"
