# Publish/Republish Geoprocessing Service
*This service is used in conjunction with the `Core/LAMBDA/viz_functions/viz_publish_service/lambda_function.py` LAMBDA function for automatically publishing/republishing Hydrovis services.*

### Overview
This geoprocessing service takes a .mapx file as input, and outputs a .sd (service definition) file. This service definition file is what the viz_publish_service lambda uses to publish services.

#### Environment variables for Publish Service
As enumerated in `Core\LAMBDA\viz_functions\main.tf`
```
GIS_PASSWORD        = var.egis_portal_password
GIS_HOST            = local.egis_host
GIS_USERNAME        = "hydrovis.proc"
PUBLISH_FLAG_BUCKET = var.python_preprocessing_bucket
S3_BUCKET           = var.viz_authoritative_bucket
SD_S3_PATH          = "viz_sd_files"
SERVICE_TAG         = local.service_suffix
EGIS_DB_HOST        = var.egis_db_host
EGIS_DB_DATABASE    = var.egis_db_name
EGIS_DB_USERNAME    = jsondecode(var.egis_db_user_secret_string)["username"]
EGIS_DB_PASSWORD    = jsondecode(var.egis_db_user_secret_string)["password"]
ENVIRONMENT         = var.environment
```

### How to install the geoprocessing service on the ArcGIS Server stack

1. On an EC2 with ArcPro, copy the script in this PR (`mapxtosd.py`) to the computer, and include in that same directory a folder called `files` with `Empty_Project.aprx` in it (this is needed for the script, and can be found in the same utils folder of the repo with the script file). You will also need to sign-in to the Portal of the EGIS you're planning to publish to with the admin credentials.


2. In Catalog, create a new toolbox (regular is fine, doesn't need to be a Python Toolbox), and create a new script inside of that toolbox.
   ![305200320-f4441937-0f39-4030-a548-55b84f7b08e4](https://github.com/user-attachments/assets/b95507d9-9210-4004-9c7f-e562ea1f8358)


3. Set the name and set the Script File to point to the script contained in this PR, and check the box for Import script (no other options of the first page need to be checked). On the parameters page, setup parameters for all the input arguments listed in the script (make sure egis_db_password is optional, as retrieving the secret as an environment variable is the more secure method). Click OK to create the script tool:

      ![305201162-fd3307f7-3776-456c-b2d6-9079bdc5be55](https://github.com/user-attachments/assets/f0a7b88b-6922-4d92-bb92-396bfc4df8db)

6. Open the new script tool, and setup a test run with a real service. Getting it to run successfully may take some troubleshooting.

   ![305202273-c582acf4-b626-4f01-9f29-b5d0b5b991f3](https://github.com/user-attachments/assets/0b50810f-405b-47ba-9158-fb17e1fbc516)

8. Once it runs successfully, click `Open History`, right click on the successful run, go to `Share As` -> `Share Web Tool` (this will be greyed out if you're not logged in as the admin account). Assign the description and tags that you want, choose to copy data to the server, and choose the Server to publish to (I chose GP in TI, which makes sense... but this will need to be done in UAT and Prod in coordination with the EGIS folks, to ensure that it's the server they want running these workflows.). Don't share with everyone (e.g. public), only authenticated users:

   ![305212710-457918e1-644e-430c-a2b5-ccbaff982ebe](https://github.com/user-attachments/assets/84bd47d9-34e4-4133-800f-d86bfe81a1ee)

10. When you validate, you'll probably get some warnings about Empty_Project.aprx and some connection string being uploaded to the server, that's fine and good. You should be able to test the tool through a REST job, as is possible in the test service I created here: https://maps-testing.water.noaa.gov/gp/rest/services/Utilities/MapxToSD/GPServer/MapxToSD/execute
