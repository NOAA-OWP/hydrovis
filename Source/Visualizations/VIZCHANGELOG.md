All notable changes to this project will be documented in this file.
We follow the [Semantic Versioning 2.0.0](http://semver.org/) format.

<br/><br/>


## v3.3.0 - 2023-5-5 - [PR #426](https://github.com/NOAA-OWP/hydrovis/pull/426)

This merge adds the Jupyter notebook used when new FIM versions are available.

## Additions

- `Source/Visualizations/aws_loosa/utils/10. FIM Version Update.ipynb`

<br/><br/>

## v3.2.0 - 2023-4-5 - [PR #403](https://github.com/NOAA-OWP/hydrovis/pull/403)

This merge activates the 1ft intervals for Stage-Based CatFIM. Intervals begin at Action stage and increment by 1 ft until the Major stage + 5ft is reached. Sublayers are created for each category. Each category has an intervals layer and the threshold layer.

Also includes a minor update to all inundation map services, to limit the scale of drawing, in order to improve render performance.

## Changes
- `/hydrovis/Core/VIZ/EC2/code/aws_loos/pro_projects/db_pipeline/stage_based_catfim.mapx`
- `/hydrovis/Core/VIZ/EC2/code/aws_loos/pro_projects/db_pipeline/<service>_inundation.mapx`

<br/><br/>


## v3.1.0 - 2023-3-30 - [PR #371](https://github.com/NOAA-OWP/hydrovis/pull/371)

This merge addresses a request by WPOD to separate the Flow-Based and Stage-Based CatFIM magnitude-specific maps into individual layers, and to update certain aliases. Ordering of fields in the attribute table has also been improved.

### Changes
In the following files, the magnitude-specific maps were separated into individual sublayers. All layers still rely on the same database table, but definition queries were added to query the desired magnitude polygons. I have also changed `AHPS LID` to `NWS LID` and `Q` to `Flow` where applicable.

- `/hydrovis/Core/VIZ/EC2/code/aws_loos/pro_projects/db_pipeline/flow_based_catfim.mapx`
- `/hydrovis/Core/VIZ/EC2/code/aws_loos/pro_projects/db_pipeline/stage_based_catfim.mapx`

<br/><br/>

## v3.0.4 - 2023-1-30 - [PR #50](https://github.com/NOAA-OWP/hydrovis-visualization/pull/50)

This merge is to fix mapx fields and aliases from the FIM4 implementation, add stability for step functions, add src skill static service, be able to run nwm aep fim in pipeline

## Changes
- `aws_loosa/lambdas/functions/viz_db_postprocess_sql/summaries/*_inundation/building_footprints_fimpact.sql`:
  - changed interpoldated_stage_ft to hand_stage_ft
  - changed flooded_area_sqmi to 0
- `aws_loosa/lambdas/functions/viz_db_postprocess_sql/summaries/*_inundation/src_skill.sql`: 
  - changed nwm_feature_id_str to feature_id_str for consistency
- `pro_projects/db_pipeline/*_inundation_*.mapx`:
  - Updated fields and aliases according for changes above

<br/><br/>

## v3.0.3 - 2023-1-6 - [PR #42](https://github.com/NOAA-OWP/hydrovis-visualization/pull/42)

This merge is for forecast FIM to switch to FIM4

## Changes
- `aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/*_inundation.sql`:
  - changed interpoldated_stage_ft to hand_stage_ft
  - changed fim_configuration to branch
- `aws_loosa/lambdas/functions/viz_fim_data_prep/data_sql/*_inundation.sql`: 
  - Using FIM4 crosswalk DB table get values and non lake reaches above threshold
- `aws_loosa/lambdas/functions/viz_fim_data_prep/lambda_function.py`:
  - Updated logic to be able to use step function distributed map. Writes out all hydro ids to be processed in an S3
- `aws_loosa/lambdas/functions/viz_fim_huc_processing/lambda_function.py`:
  - Updated logic to use branches for FIM4
  - Added more error handling
- `pro_projects/db_pipeline/*_inundation_*.mapx`:
  - Updated fields and aliases for FIM4

<br/><br/>

## v3.0.2 - 2022-1-05 - [PR #44](https://github.com/NOAA-OWP/hydrovis-visualization/pull/44)

This merge fixes some bugs that had to do with v2.10.8. Main fix was the pipeline using mapx instead of aprx.
Also fixed small bug when shapefile folder exists

## Changes
- `aws_loosa/ec2/processes/base/aws_egis_process.py`:
  - Updated pro project location to use mapx instead of aprx
- `aws_loosa/ec2/utils/shared_funcs.py`: 
  - Updated to remove existing shapefile folder before trying to create a new one

<br/><br/>

## v3.0.1 - 2022-12-07 - [PR #39](https://github.com/NOAA-OWP/hydrovis-visualization/pull/39)

This merge updates the Flow-Based and Stage-Based CatFIM map files with additional metadata attributes requested by the field users. These additional attributes are pulled from WRDS and allow users to better understand why some sites are not mapped in Stage-Based, a primary reason being unacceptable altitude accuracy or datum method codes.

## Changes
- `/pro_projects/db_pipeline/flow_based_catfim.mapx`:
  - Updated map document to accommodate new schema with additional attributes
- `/pro_projects/db_pipeline/stage_based_catfim.mapx`: 
  - Updated map document to accommodate new schema with additional attributes
  - Updated map document to load in the interval maps (in between AHPS thresholds), however these have been queried out using a definition query until such time as Hydrovis wishes to deliver the service with the intervals included. A follow up PR will be made to this end.
- `util_scripts/service_metadata.ipynb:`
  - Updated service description for Flow-Based CatFIM
  - Updated service description for Stage-Based CatFIM

<br/><br/>

## v3.0.0 - 2022-10-19 - [PR #25](https://github.com/NOAA-OWP/hydrovis-visualization/pull/25)

Updates field names and adds new layer to FIM Performance Service.

### Changes include:
- `/pro_projects/db_pipeline/fim_performance.mapx` Updated field names/aliases according to WPOD feedback. It also has a new sublayer, fim_performance_catchments, which communicates FIM prediction skill summarized by HAND catchments, symbolized by MCC on a white to green scale to distinguish it from the other layers which use red to blue for CSI.
- `util_scripts/service_metadata.ipynb`: Updates service description.

<br/><br/>

## v2.10.8 - 2022-12-27 - [PR #38](https://github.com/NOAA-OWP/hydrovis-visualization/pull/38)

Added Hawaii and Puerto Rico streamflow services

### Added:
- Hawaii streamflow sql and mapx files
- Puerto Rico streamflow sql and mapx file

### Changes:
`util_scripts\service_metadata.ipynb`: Updated HI and PRVI streamflow descriptions


<br/><br/>

## v2.10.7 - 2022-12-27 - [PR #40](https://github.com/NOAA-OWP/hydrovis-visualization/pull/40)

Map and metadata consistency updates

### Changes include:
- Add update frequency to descriptions (e.g "Updated hourly", "Updated every 6 hours", etc)
- Removed NWM version in description since this could change in future.
- Changed all "ref_time" fields to be "reference_time" for consistency.
- Added valid_time and reference_time to ana services
- Updated feature_id_str field to be feature_id. I just updated the sql in the mapx file to select the data as "select feature_id_str AS feature_id".
- Updated hydro_id_str field to be hydro_id. I just updated the sql in the mapx file to select the data as "select hydro_id_str AS hydro_id".
- Updated map names to follow the same naming convention. For example "NWM Medium-Range Peak Flow Arrival Time Forecast"
- Updated layer names to follow the same naming convention. For example "3 Days - Est. Annual Exceedance Probability"
- Updated feature size variability across services for consistency. Fixes peak flow services size issue
- Updated and cleaned display filter across services for consistency

<br/><br/>

## v2.10.6 - 2022-12-07 - [PR #37](https://github.com/NOAA-OWP/hydrovis-visualization/pull/37)

Fixed typo issues in the publishing process

This is collection of minor fixes to address issues with the 11/14 Production Deploy, per vlab ticket: https://vlab.noaa.gov/redmine/issues/110053

### Changes include:
Added empty rows to hi and prvi inundation service, in the event of no inundation, so that Ops service monitor works
Various field, layer name, display filter and alias fixes

<br/><br/>

## v2.10.5 - 2022-11-02 - [PR #31](https://github.com/NOAA-OWP/hydrovis-visualization/pull/31)

Fixed typo issues in the publishing process

### Changes
`aws_loosa\ec2\processes\base\aws_egis_process.py`: Fixed some typo errors in the publishing process

<br/><br/>

## v2.10.4 - 2022-11-02 - [PR #30](https://github.com/NOAA-OWP/hydrovis-visualization/pull/30)

Fixed feather issues for the EC2 pipeline services. Now exporting as a zip shapefile instead of feather

### Changes
`aws_loosa\ec2\utils\shared_funcs.py`: Exporting as a zip shapefile instead of feather

<br/><br/>

## v2.10.3 - 2022-11-02 - [PR #28](https://github.com/NOAA-OWP/hydrovis-visualization/pull/28)

Updated `service_metadata.ipynb` given Fernando Salas' feedback regarding Flow-Based and Stage-Based threshold descriptions.

### Changes
`service_metadata.ipynb`: Updated Flow-Based CatFIM and Stage-Based CatFIM service descriptions.

<br/><br/>

## v2.10.2 - 2022-10-26 - [PR #27](https://github.com/NOAA-OWP/hydrovis-visualization/pull/27)

Couple minor tweaks

### Fixes
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/rfc_max_stage.sql`: Changed RFC Max Stage to use reference / run time when applying the issued time filter, in order to work with past events.
- `/util_scripts/service_metadata.ipynb`: Service metadata notebook updates.

<br/><br/>

## v2.10.1 - 2022-10-25 - [PR #26](https://github.com/NOAA-OWP/hydrovis-visualization/pull/26)

Additional step function stability enhancements. Major updates include archiving data in feather format and updating the update_egis_data function

### Additions
- `/aws_loosa/lambdas/functions/viz_update_egis_data`: Converted lambda to image based for new feather archiving strategy
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/*_inundation.sql`: Fixed inundation sql for reference time
- `/aws_loosa/ec2/utils/shared_funcs.py`: EC2 services now archive feather in S3

### Fixes
- `/pro_projects/db_pipeline/ana_streamflow.mapx`: Not all streams were rendering before.

<br/><br/>

## v2.10.0 - 2022-10-12 - [PR #19](https://github.com/NOAA-OWP/hydrovis-visualization/pull/19)

Adds files to implement the srf_rate_of_change service

### Additions
- `/pro_projects/db_pipeline/srf_rate_of_change.mapx`: The MAPX file for the service.
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/srf_rate_of_change.sql`: The SQL file for the service.

### Fixes
- `/pro_projects/db_pipeline/ana_streamflow.mapx`: Not all streams were rendering before.

<br/><br/>


## v2.9.1 - 2022-10-12 - [PR #23](https://github.com/NOAA-OWP/hydrovis-visualization/pull/23)

### Fixes and Tweaks to Raster Step Function:
- ANA_max_flows fix for interim ana_past_hour solution for Shawn's rate of change service
- ANA past 14 day inundation fixes (step function name length issue) + service metadata table fixes (notebook)
- Additional step function name shortening.
- Keep ana 14 day max flows files for 30 days instead of 3
- Changing update egis data function to only do db caching in TI and Dev
- Service metadata updates: disable all raster services, peak flow arrival time, ana_streamflow. Fixes to ana and ana 14 day.

<br/><br/>

## v2.9.0 - 2022-10-06 - [PR #22](https://github.com/NOAA-OWP/hydrovis-visualization/pull/22)

### Major updates to step functions:
- Addition of raster processing and optimizing within the step function
- Addition of nested state machines for huc processing
- 
### Minor updates:
- Implementation of file format, window, and step to create a list of input files for a service from a reference time
- Moving some larger python dependency lambdas to containers instead of functions with layers
- HUC processing now used geopandas to merge polygons, convert to 3857 spatial reference, and gets fields ready

### Modifications:
- `create_s3_connection_files.py`: Updated workflow to create a single S3 connection file for the processing outputs folder
- `update_data_stores_and_sd_files.py`: Updated workflow to update tables in the map
- `all fim service sql files`: Removed postgis transforming spatial references
- `lambda functions`: Added capabilities to handle raster service data input
- `container based lambdas`: HUC processing, raster process, and raster optimizing are now all container based lambdas to accomodate larger python dependencies

### Additions:
- `raster lambda`: raster processing and raster optimizing lambdas
- `raster service python files`: python scripts in the raster lambda that process gridded data into rasters
- `raster mapx`: mapx files for new accumulated precipitation services

<br/><br/>

## v2.8.2 - 2022-09-29 - [PR #21](https://github.com/NOAA-OWP/hydrovis-visualization/pull/21)

Automation of service configuring such as minx/max instances, Feature Access, OGC extension enabling, and sharing status

### Modifications:
- `update_data_stores_and_sd_files.py`: Updated workflow to configure step function based services
- `aws_egis_process.py`: Updated workflow to configure EC2 based services
- `lambda_function.py`: Updated for sharing based on DB properties or type of environment

<br/><br/>

## v2.8.1 - 2022-09-20 - [PR #20](https://github.com/NOAA-OWP/hydrovis-visualization/pull/20)

Minor fixes & change of global streamflow filter to 0.01 for now.

### Modifications:
- `/pro_projects/db_pipeline/ana_past_14day_max_high_flow_magnitude.mapx`: Fixed max flows alias
- `/pro_projects/db_pipeline/mrf_max_high_flow_magnitude.mapx`: Fixed max flows alias
- `/aws_loosa/lambdas/functions/viz_initialize_pipeline/lambda_handler.py`: Changed global streamflow filter.

<br/><br/>

## v2.8.0 - 2022-09-14 - [PR #13](https://github.com/NOAA-OWP/hydrovis-visualization/pull/13)

Switches over from using APRX files to MAPX (JSON) files. These files are human-readable, diff-trackable, and store commonly-edited metadata such as field aliases and symbology colors. The service definition (SD) files used for publishing services is now created from the MAPX files, using an empty, baseline APRX file.

### Additions:
- `/pro_projects/db_pipeline/*.mapx`: The new MAPX (JSON) file for every service
- `/aws_loosa/ec2/utils/aprx_to_mapx.py`: Python script for converting APRX files to MAPX
- `/pro_projects/Blank_Project.aprx`: An empty APRX file used for the baseline into which each MAPX is imported when creating SD files.

### Deletions:
- `/pro_projects/db_pipeline/*.aprx`: Every pre-existing ArcGIS Pro Project file

### Modifications:
- `/aws_loosa/ec2/deploy/update_data_stores_and_sd_files.py`: SD file creation modified to originate from MAPX files, rather than APRX

<br/><br/>

## v2.7.0 - 2022-09-13 - [PR #17](https://github.com/NOAA-OWP/hydrovis-visualization/pull/17)

This PR adds SQL and pro project files to implement the MRF Peak Flow Arrival Time service for CONUS (3-day and 10-day leyers).
Additions:
aws_loosa\lambdas\functions\viz_db_postprocess_sql\services\mrf_peak_flow_arrival_time.sql
pro_projects\db_pipeline\mrf_peak_flow_arrival_time.aprx

A preview of the service can be found here:
[10-Day Peak Flow Arrival Time](https://maps-testing.water.noaa.gov/server/rest/services/NWM/mrf_peak_flow_arrival_time/MapServer)

<br/><br/>

## v2.6.0 - 2022-09-08 - [PR #16](https://github.com/NOAA-OWP/hydrovis-visualization/pull/16)

Adds files to implement the three (3) Short-Range Peak Flow Arrival Time services for CONUS (18-Hour), and Hawaii and PRVI (48-Hour)

## Additions
- `/pro_projects/db_pipeline/srf_peak_flow_arrival_time.aprx`: The ArcGIS Pro project for the 18-Hour Peak Flow Arrival Time (CONUS) service.
- `/pro_projects/db_pipeline/srf_peak_flow_arrival_time_hi.aprx`: The ArcGIS Pro project for the 48-Hour Peak Flow Arrival Time (Hawaii) service.
- `/pro_projects/db_pipeline/srf_peak_flow_arrival_time_prvi.aprx`: The ArcGIS Pro project for the 48-Hour Peak Flow Arrival Time (PRVI) service.
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/srf_peak_flow_arrival_time.sql`: The SQL file for the Peak Flow Arrival Time (CONUS) service.
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/srf_peak_flow_arrival_time_hi.sql`: The SQL file for the Peak Flow Arrival Time (Hawaii) service.
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/srf_peak_flow_arrival_time_prvi.sql`: The SQL file for the Peak Flow Arrival Time (PRVI) service.

<br/><br/>

## v2.5.0 - 2022-09-08 - [PR #9](https://github.com/NOAA-OWP/hydrovis-visualization/pull/9)

Adds files to implement the Streamflow Analysis (ana_streamflow) service

## Additions
- `/pro_projects/db_pipeline/ana_streamflow.aprx`: The ArcGIS Pro project for the Streamflow Analysis service.
- `/aws_loosa/lambdas/functions/viz_db_postprocess_sql/services/ana_streamflow.sql`: The SQL file for the Streamflow Analysis service.

<br/><br/>

## v2.4.0 - 2022-07-28 - [PR #10](https://github.com/NOAA-OWP/hydrovis-visualization/pull/10)

This branch includes an ArcGIS Pro Project for NWM AEP FIM.

## Additions
- `/pro_projects/db_pipeline/nwm_aep_fim.aprx`: The ArcGIS Pro project for the NWM AEP FIM service.

<br/><br/>

## v2.3.2 - 2022-08-31 - [PR #11](https://github.com/NOAA-OWP/hydrovis-visualization/pull/11)

More fixes to the major step function update, notably:

- db_ingest function now uses Google Cloud instead of S3 a) when an S3 file reports missing, and 2) for past event runs older than 1 month.
- Slimmed down HUC task list from the fim data prep function to be smaller (ANA 14 day FIM was too large of a return object)
- Removed shapefile caching from ANA 14 day FIM (exceeding 2GB shapefile limit, punting this to better archive strategy currently being discussed with WPOD)
- Some other misc. fixes.

<br/><br/>

## v2.3.1 - 2022-08-18 - [PR #7](https://github.com/NOAA-OWP/hydrovis-visualization/pull/7)

This PR includes a variety of bug fixes and minor tweaks to the large Step Function enhancement.

The only notable change here is that the viz_update_egis_data lambda function now caches a shapefile to S3 as well as writing data to a table in the archive schema.


<br/><br/>

## v2.3.0 - 2022-08-01 - [PR #5](https://github.com/NOAA-OWP/hydrovis-visualization/pull/5)

This is a major update to the entire hydrovis viz db-pipeline, based on a collaboration of work between Corey and I on the old owp-viz-services-aws vlab repo (step_function branch). I won't detail everything here for the sake of brevity (almost every non pro-project file changed in some capacity), but that repo has a more detailed record of edits / commits.

This Update Includes:
- Implementation of viz_pipeline step function to manage viz pipelines (numerous benefits notably increased stability)
- Complete refactor of viz lambda functions to support step function, and new viz_classes file in the the shared functions layer
- Inundation services are now part of the db_pipeline and serverless
- Inundation services are now vector-based, which means metadata is in the extent layers without additional services / layers
- Ability to run past reference times by specifying a reference_time in the initialize pipeline function (resulting tables show up in the archive schema)
- db-pipeline service data is now automatically cached in the archive schema of the database for 30 days
- db_dumps_to_s3 script to automate db dump process for deployments

<br/><br/>


## v2.2.0 - 2022-07-28 - [PR #3](https://github.com/NOAA-OWP/hydrovis-visualization/pull/3)

This branch includes an ArcGIS Pro Project for FIM Performance.

## Additions
- `/pro_projects/db_pipeline/fim_performance.aprx`: Pro Project.

<br/><br/>

## v2.1.0 - 2022-07-28 - [PR #2](https://github.com/NOAA-OWP/hydrovis-visualization/pull/2)

This branch includes an ArcGIS Pro Project for Flow-Based CatFIM. It also includes a new file to set line endings.

## Additions
- `/pro_projects/db_pipeline/flow_based_catfim.aprx`: The ArcGIS Pro project for the Flow-Based CatFIM service.
- `/.gitattributes`: A text file that includes line endings config. I just copied this from the Inundation Mapping repository.

<br/><br/>

## v2.0.0 - 2022-07-27 - [PR #1](https://github.com/NOAA-OWP/hydrovis-visualization/pull/1)

`Repository Baseline` In order to have a good base for the repository going forward, a new changelog has been added as well as updates to general README files.

## Additions

- `CHANGELOG.md`:  Used to track changes across versions.
- `aws_loosa`
    - `README.md`: 
       - Added a new readme to describe why differing workflows are used
       
## Changes
- `README.md`: Updated language and new references to new folders
