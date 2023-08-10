import os
import shutil
import boto3
import OptimizeRasters

from osgeo import gdal

s3 = boto3.client('s3')
s3_resource = boto3.resource('s3')


def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will download a inundation
        tif and convert it to mrf. The mrf will then be uploaded to S3

        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    if 'step' in event and event['step'] == 'create_vrt':
        run_create_vrt(event)
    else:
        run_optimize_raster(event)

def create_optimized_rasters(inundation_raster):
    args = {
        'input': os.path.dirname(inundation_raster),    # input path. eg. c:/input/mydata
        'output': '/tmp/or',  # processed output path. eg. c:/output/mydata
        'subs': 'false',    # Do we included subfolders?
        'config': 'TIF_to_MRF.xml'  # eg. r'c:/Image_Mgmt_Workflows/OptimizeRasters/Templates/Imagery_to_MRF_LERC.xml'  # noqa
    }
    rpt = OptimizeRasters.Report(OptimizeRasters.Base())
    writeToPath = '/tmp/or'
    if not os.path.exists(writeToPath):
        os.mkdir(writeToPath)
    ORJobFile = os.path.join(writeToPath, '{}{}'.format(rpt.getUniqueFileName(), rpt.CJOB_EXT))
    rpt.init(ORJobFile)
    for key in args.keys():
        rpt.addHeader(key, args[key])   # add necessary headers.
    rpt.addFile(inundation_raster)  # eg. c:/input/mydata/readme.txt
    # please note, when adding files into the job file, it's important that all entries should have the same parent folder. In this case, it's (c:/input/mydata/)  # noqa
    rpt.write()  # create the OR job/.orjob file.
    args['input'] = ORJobFile      # input now points to the newly created OptimizeRasters Job file.
    app = OptimizeRasters.Application(args)  # The args{} can contain any valid cmd-line argument name without the prefix '-'  # noqa
    # app.registerMessageCallback(messages)   # Optional. If messages need to be brought back onto the caller's side.
    if (not app.init()):
        return False
    app.run()  # Do processing..
    rpt = app.getReport()   # Get report/log status
    isSuccess = False
    if (rpt and
            not rpt.hasFailures()):  # If log has no failures, consider the processing as successful.
        isSuccess = True
    print('Results> {}'.format(str(isSuccess)))

    return writeToPath

def run_optimize_raster(event):
    # Parse the event to get the necessary arguments
    input_raster_bucket = event['output_bucket']
    input_raster_key = event['output_raster']

    output_raster_bucket = input_raster_bucket
    output_raster_key = input_raster_key.replace("/tif/", "/mrf/")
    output_raster_prefix = os.path.dirname(output_raster_key)

    print(f"Converting {input_raster_key} into {output_raster_key}")
    file_name = os.path.basename(input_raster_key).split(".")[0]
    local_raster = f'/tmp/{os.path.basename(input_raster_key)}'

    # Download the tif to a local file
    print(f"Downloading {input_raster_key}")
    s3.download_file(input_raster_bucket, input_raster_key, local_raster)

    # Run ESRI code to convert a tif to an mrf
    print("Creating optimized raster")
    mrf_dir = create_optimized_rasters(local_raster)
    
    try:
        os.remove(local_raster)
    except:
        print("Failed to remove local raster file.")

    # Loop through the mrf files (4) and upload them to S3
    mrf_files = os.listdir(mrf_dir)
    for mrf_file in mrf_files:
        if file_name in mrf_file:
            local_file_path = os.path.join(mrf_dir, mrf_file)
            S3_file_path = os.path.join(output_raster_prefix, mrf_file)
            print(f"Writing {S3_file_path} to {output_raster_bucket}")
            s3.upload_file(local_file_path, output_raster_bucket, S3_file_path,
                           ExtraArgs={'ServerSideEncryption': 'aws:kms'})
    
    try:
        shutil.rmtree(mrf_dir)
    except:
        print("Failed to remove mrf_dir")

    print(
        f"Successfully processed mrf for {input_raster_key}"
    )

def run_create_vrt(event):
    fim_config = event['args']['fim_config']['name']
    output_bucket = event['args']['product']['raster_outputs']['output_bucket']
    output_workspaces = event['args']['product']['raster_outputs']['output_raster_workspaces']
    output_workspace = next(list(workspace.values())[0] for workspace in output_workspaces if list(workspace.keys())[0] == fim_config)

    # We only create two VRTs (one in the mrf folder and another in the tif folder)
    # because we only want one in the mrf folder, but for it to be moved to the 
    # publish folder it has to also exist in the tif folder since the tif folder
    # is used as the basis for what gets copied over in the viz_update_egis_data lambda
    create_vrt(output_bucket, f'{output_workspace}/tif/', '.tif')
    create_vrt(output_bucket, f'{output_workspace}/mrf/', '.mrf')

def create_vrt(output_bucket, output_workspace, extension):
    s3_client = boto3.client('s3')
    paginator = s3_client.get_paginator('list_objects')
    operation_parameters = {'Bucket': output_bucket,
                            'Prefix': output_workspace,
                            'Delimiter': '/'}
    page_iterator = paginator.paginate(**operation_parameters)
    vrt_files = []
    page_count = 0
    for page in page_iterator:
        page_count += 1
        objects = page['Contents']
        for obj in objects:
            key = obj['Key']
            if key.endswith(extension):
                vrt_files.append(f'/vsis3/{output_bucket}/{key}')

    out_vrt = f'/vsis3/{output_bucket}/{output_workspace}_dataset.vrt'
    print(f"Building VRT from {len(vrt_files)} files and writing to {out_vrt}...")
    vrt_options = gdal.BuildVRTOptions(VRTNodata=0)
    gdal.BuildVRT(out_vrt, vrt_files, options=vrt_options)
