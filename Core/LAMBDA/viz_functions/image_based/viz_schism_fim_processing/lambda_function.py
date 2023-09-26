################################
#
# SCHISM FIM Workflow
# 
# This script takes a SCHISM netCDF file and generates
# a FIM tif for the provided raster tile along the coast.
#
# Author: Laura Keys, laura.keys@noaa.gov
#
################################
import boto3
import datetime as dt
import geopandas as gpd
import fiona
import numpy as np
import rasterio
import rasterio.mask
import re
import rioxarray as rxr
import os
import s3fs
import tempfile
import xarray as xr

from shutil import rmtree
from scipy.interpolate import griddata
from rasterio import features
from rasterio.session import AWSSession
from shapely.geometry import box
from time import sleep
from rasterio.io import MemoryFile

# DO NOT LEAVE THIS COMMENTED!!!!!!!
from viz_classes import database
# database = {}

DEM_RESOLUTION = 30
GRID_SIZE = DEM_RESOLUTION / 111000 # calc degrees, assume 111km/degree
INPUTS_BUCKET = os.environ['INPUTS_BUCKET']
INPUTS_PREFIX = os.environ['INPUTS_PREFIX']
AWS_SESSION = AWSSession()
S3 = boto3.client('s3')
DOMAINS = ['atlgulf', 'pacific', 'hawaii', 'puertorico']
NO_DATA = np.nan
METERS_TO_FT = 3.281


def lambda_handler(event, context):
    print("Executing lambda handler...")
    step = event['step']
    fim_config = event['args']['fim_config']['name']

    if step == 'get_domain_tile_basenames':
        domain = [d for d in DOMAINS if d in fim_config][0]
        domain_tile_basenames = get_domain_tile_basenames(domain)
        return {
            "domain_tile_basenames": domain_tile_basenames
        }

    if step != 'iteration': 
        raise Exception(f'Step "{step}" is invalid.')

    tile_basename = event['tile_basename']
    reference_time = event['args']['reference_time']
    sql_rename_dict = event['args']['sql_rename_dict']
    fim_config = event['args']['fim_config']['name']
    product = event['args']['product']['product']
    target_table = event['args']['fim_config']['target_table']
    fim_config_preprocessing = event['args']['fim_config'].get('preprocess', {})
    preprocessing_output_file_format = fim_config_preprocessing.get('output_file')
    preprocessing_output_file_bucket = fim_config_preprocessing.get('output_file_bucket')
    max_elevs_file_bucket = event['args']['fim_config'].get('max_file_bucket', preprocessing_output_file_bucket)
    max_elevs_file = event['args']['fim_config'].get('max_file', preprocessing_output_file_format)

    output_bucket = event['args']['product']['raster_outputs']['output_bucket']
    output_workspaces = event['args']['product']['raster_outputs']['output_raster_workspaces']
    output_workspace = next(list(workspace.values())[0] for workspace in output_workspaces if list(workspace.keys())[0] == fim_config)

    schism_fim_s3_uri = f's3://{max_elevs_file_bucket}/{max_elevs_file}'

    reference_date = dt.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    
    print(f"Processing the {fim_config} fim config")

    depth_key = create_fim_by_tile(tile_basename, schism_fim_s3_uri, product, fim_config, reference_date, target_table, output_bucket, output_workspace)
    
    return {
        "output_raster": depth_key,
        "output_bucket": output_bucket
    }

def get_domain_tile_basenames(domain):
    prefix = f'{INPUTS_PREFIX}/dems/{domain}/tiles/'
    paginator = S3.get_paginator('list_objects')
    operation_parameters = {'Bucket': INPUTS_BUCKET,
                            'Prefix': prefix}
    page_iterator = paginator.paginate(**operation_parameters)
    valid_ids = []
    for page in page_iterator:
        objects = page['Contents']
        for obj in objects:
            key = obj['Key']
            if key.endswith('.tif'):
                valid_ids.append(key.split('/')[-1])

    return valid_ids

def create_fim_by_tile(tile_basename, schism_fim_s3_uri, product, fim_config, reference_date, target_table, output_bucket, output_workspace):
    domain = [d for d in DOMAINS if d in schism_fim_s3_uri][0]
    full_ref_time = reference_date.strftime("%Y-%m-%d %H:%M:%S UTC")

    target_table_schema = target_table.split(".")[0]
    target_table = target_table.split(".")[1]

    depth_key = f'{output_workspace}/tif/{tile_basename}'
    dem_filename = f's3://{INPUTS_BUCKET}/{INPUTS_PREFIX}/dems/{domain}/tiles/{tile_basename}'

    print(f'Processing Schism FIM for {tile_basename}...')
    
    dem_obj = None
    with rasterio.Env(AWS_SESSION):
        dem_obj = rasterio.open(dem_filename)

    try:
        # limit the schism data to the tile bounds
        clipped_npds = clip_to_bounds(schism_fim_s3_uri, dem_obj.bounds)
        
        if len(clipped_npds.x) == 0:
            print(f"!! No forecast points in netCDF in tile {tile_basename}")
            raise Exception

        print(f".. {len(clipped_npds.x)} forecast points in tile {tile_basename}")
        # interpolate the schism data
        interp_grid_memfile = interpolate(clipped_npds, GRID_SIZE)

        # subtract dem from schism data 
        # (includes code to match extent/resolution)
        wse_grid = wse_to_depth(interp_grid_memfile, dem_obj)
        if wse_grid is None:
            print("!! No overlap between raster and DEM")
            raise Exception

        # apply masks
        final_grid_memfile = mask_fim(wse_grid, domain)
    except Exception as e:
        print(e)
        print("Issue encountered (see above). Creating empty tile...")
        final_grid_memfile = create_empty_tile(dem_obj)

    print("Converting depth to binary fim...")
    # translate all > 0 depth values to 1 for wet (everything else [dry] already 0)
    binary_fim_memfile = fim_to_binary(final_grid_memfile)

    print(f"Uploading depth grid to AWS at s3://{output_bucket}/{depth_key}")
    S3.upload_fileobj(
        final_grid_memfile,
        output_bucket,
        depth_key
    )

    attributes = {
        'huc8': tile_basename,
        'reference_time': full_ref_time
    }

    polygon_df = raster_to_polygon_dataframe(binary_fim_memfile, attributes)

    if polygon_df.empty:
        print("Raster to polygon yielded no features.")
    else:
        print("Writing polygons to PostGIS database...")
        attempts = 3
        process_db = database(db_type="viz")
        polygon_df.to_crs(3857, inplace=True)
        polygon_df.set_crs('epsg:3857', inplace=True)
        polygon_df.rename_geometry('geom', inplace=True)
        for attempt in range(attempts):
            try:
                polygon_df.to_postgis(target_table, con=process_db.engine, schema=target_table_schema, if_exists='append')
                break
            except Exception as e:
                if attempt == attempts - 1:
                    raise Exception(f"Failed to add SCHISM FIM polygons to DB for tile {tile_basename} of {fim_config} for {full_ref_time}: ({e})")
                else:
                    sleep(1)
        process_db.engine.dispose()

    print(f"Successfully processed SCHISM FIM for tile {tile_basename} of {fim_config} for {full_ref_time}")
    return depth_key

#
# Clips SCHISM forecast points to fit some shapefile bounds
#
def clip_to_bounds(schism_fim_s3_uri, bounds):
    print("Clipping SCHISM max_elevs domain to new tile domain...")

    fs = s3fs.S3FileSystem()
    print(f'...Opening {schism_fim_s3_uri}...')
    with fs.open(schism_fim_s3_uri, 'rb') as f:
        with xr.open_dataset(f) as n:
            n_ = check_names(n)
            n_clip = n_.where(
                ((n_.x < bounds[2]) & #x_max
                (n_.x > bounds[0]) & #x_min
                (n_.y < bounds[3]) & #y_max
                (n_.y > bounds[1])), #y_min
                    NO_DATA)

    n_clip = n_clip.dropna('node', how="any")
    
    return n_clip

def check_names(f):
    try:
        f = f.rename({'SCHISM_hgrid_node_x':'x',
            'SCHISM_hgrid_node_y':'y',
            'elevation':'elev'})
        print("...Renamed variables in netcdf.")
    except:
        print("...No variables to rename in netcdf. Good!") 
    try:
        f = f.rename_dims({'nSCHISM_hgrid_node':'node'})
        print("...Renamed dim in netcdf.")
    except:
        print("...No dimension to rename in netcdf. Good!") 

    return f

def interpolate(numpy_ds, grid_size):
    print('Interpolating max_elevs grid...')
    # time series netcdf needs to have x, y, and elev variables
    # ... SCHISM files operationally might use "elevation",
    # "SCHISM_hgrid_node_x" and "SCHISM_hgrid_node_y", so
    # renmame those variables because xarray and rasterio-based
    # functionality require x and y names for matching projections,
    # extents, and resolution
    n = check_names(numpy_ds)
    
    if len(n.elev.dims) == 1:
        el = n.elev # SCHISM data should also include a depth variable
    else:
        el = n.elev[0]

    # locations of schism forecast points
    coords = np.column_stack((n.x, n.y))

    # get bounding box of forecast points 
    x_min = np.min(n.x)
    x_max = np.max(n.x)
    y_min = np.min(n.y)
    y_max = np.max(n.y)

    # create grid of evenly-spaced locations to interpolate over
    print('...Creating grid...')
    xx, yy = np.meshgrid(np.arange(x_min, x_max, grid_size), \
        np.arange(y_min, y_max, grid_size)) 

    print(f"...Number of SCHISM forecast points: {len(coords)}")

    # interpolation
    print("...Interpolating...")
    # interpolate over forecast points' elevation data onto the new xx-yy grid
    # .. cubic is also an option for cubic spline, vs barycentric linear
    # .. or nearest, for nearest neighbor, but that's slower (better for depth?)
    interp_grid = griddata(coords, el, (xx, yy), method="linear")

    # reverse order rows are stored in to match with descending y / lat values
    interp_grid = np.flip(interp_grid, 0)

    # write out interpolated raster to file or to a memory file for later use
    interp_memfile = MemoryFile()
    with interp_memfile.open(
        height=interp_grid.shape[0],
        width=interp_grid.shape[1],
        count=1,
        compress='lzw',
        dtype=interp_grid.dtype,
        driver="GTiff",
        crs="epsg:4326",
        transform=rasterio.transform.from_origin(
            x_min, y_max, grid_size, grid_size)
    ) as src:
        # write single-band raster
        src.write(interp_grid, 1)

    return interp_memfile

def wse_to_depth(interp_grid_memfile, dem):
    # clip the interpolated rst and dem to match bounding boxes
    dem_bounds = None
    rst_bounds = None
    with interp_grid_memfile.open() as rst:
        rst_bounds = rst.bounds
        dem_bounds = dem.bounds
        # get overlapping boundaries
        x_min = max(rst_bounds[0], dem_bounds[0]) # max of left values
        y_min = max(rst_bounds[1], dem_bounds[1]) # max of bottom values
        x_max = min(rst_bounds[2], dem_bounds[2]) # min of right values
        y_max = min(rst_bounds[3], dem_bounds[3]) # min of top values

        # create a clipping box of the overlapping boundaries
        feature = box(x_min, y_min, x_max, y_max)

        # clip the interp raster and topobathy dem to be same bounds
        try:
            rst_masked, rst_trans = rasterio.mask.mask(rst, [feature],
                crop=True,
                #nodata=0)
                nodata=NO_DATA)
            dem_masked, dem_trans = rasterio.mask.mask(dem, [feature],
                crop=True,
                #nodata=0)
                nodata=NO_DATA)
        except:
            # no overlapping area for the raster and dem
            return None

    # write out rst_masked with updated metadata
    # (can write to memory file instead)
    #
    # ... writing these to a file or memfile lets us use them as rasterio
    # DatasetReader later, which makes it easier to match their extents and
    # resolution perfectly to allow us to subtract correctly
    temp_rst_memfile = MemoryFile()
    with temp_rst_memfile.open(
        height=rst_masked.shape[1],
        width=rst_masked.shape[2],
        count=1,
        compress='lzw',
        dtype=rst_masked.dtype,
        driver="GTiff",
        crs="epsg:4326",
        transform=rst_trans
    ) as rst_src:
        # write single-band raster
        rst_src.write(rst_masked[0], 1)

    # write out dem with updated metadata
    temp_dem_memfile = MemoryFile()
    with temp_dem_memfile.open(
        height=dem_masked.shape[1],
        width=dem_masked.shape[2],
        count=1,
        compress='lzw',
        dtype=dem_masked.dtype,
        driver="GTiff",
        crs="epsg:4326",
        transform=dem_trans
    ) as dem_src:
        # write single-band raster
        dem_src.write(dem_masked[0], 1)

    # match resolution and coordinates of dem to the interpolation
    # .. even if the extent and resolution are the same, it's good to do
    # this to be absolutely certain before trying to do raster math
    with rxr.open_rasterio(temp_rst_memfile) as rst_masked:
        with rxr.open_rasterio(temp_dem_memfile) as dem_masked:
            # create dem with projection and resolution that matches interp rst
            matching_dem = dem_masked.rio.reproject_match(rst_masked)
            # make sure coordinates of dem match rst
            matching_dem = matching_dem.assign_coords({
                    'x':rst_masked.x,
                    'y':rst_masked.y
            })

    # calculate WSE depth
    wse_depth = rst_masked - matching_dem
    wse_depth = wse_depth * METERS_TO_FT
    wse_depth = wse_depth.round()

    wse_memfile = MemoryFile()
    with wse_memfile.open( 
        height=wse_depth.shape[1],
        width=wse_depth.shape[2],
        count=1,
        dtype=wse_depth.dtype,
        compress='lzw',
        driver="GTiff",
        crs="epsg:4326",
        transform=rasterio.transform.from_origin(rst_bounds[0], rst_bounds[3], GRID_SIZE, GRID_SIZE)
    ) as wse_src:
        # write single-band raster
        wse_src.write(wse_depth[0], 1)

    return wse_memfile

def fim_to_binary(wse_memfile):
    with wse_memfile.open() as wse_rst:
        interp_grid = wse_rst.read(1)

    print("+++ Translating to binary fim")
    interp_grid[interp_grid > 0] = 1

    # need interpolation in rasterio DatasetReader format for easy masking
    # steps, so need to save as file or memory file because it's a
    # numpy array right here
    fim_memfile = MemoryFile()
    with fim_memfile.open( 
        height=interp_grid.shape[0],
        width=interp_grid.shape[1],
        count=1,
        dtype=interp_grid.dtype,
        compress='lzw',
        driver="GTiff",
        crs="epsg:4326",
        transform=wse_rst.transform
    ) as src:
        # write single-band raster
        src.write(interp_grid, 1)
    
    return fim_memfile 

# Mask class that correctly handles masking inside or outside a specified layer
class Mask:

    def __init__(self, fpath, m):
        self.fpath = fpath
        self.mask_type = m

        # default behavior is "exterior" mask: remove everything outside a shape
        self.invert = False
        self.crop = True

        # mask out everything inside a shape and return outside areas
        if m == "interior":
            self.invert = True
            self.crop = False

    def mask(self, rst):
        # get all the masking shapefile coordinates
        with fiona.Env(session=AWS_SESSION):
            with fiona.open(self.fpath, "r") as shapefile:
                geoms = [feature["geometry"] for feature in shapefile]

        out_image, out_transform = rasterio.mask.mask(
            rst, geoms, crop=self.crop, invert=self.invert, nodata=NO_DATA)
        
        return out_image, out_transform

def mask_fim(input_fim, domain):
    out_meta = {}
    masks_prefix = f'{INPUTS_PREFIX}/masks/{domain}'

    result = S3.list_objects(Bucket=INPUTS_BUCKET, Prefix=masks_prefix)
    mask_prefixes = result.get('Contents')
    mask_uris = [f"zip+s3://{INPUTS_BUCKET}/{m['Key']}" for m in mask_prefixes]

    # list of mask locations and "interior" or "exterior" (see Mask Class)
    mask_list = [Mask(uri, re.search('[inex]{2}terior', uri)[0]) for uri in mask_uris]

    for mask_number, mask in enumerate(mask_list, 1):
        print(f'...Applying mask: {mask.fpath}...')
        
        # open the latest intermediate file and mask out the next mask
        # ... need rst in rasterio DatasetReader format, so need to save
        # as file or memory file, because the rasterio mask function does not
        # return out_image in a format we can directly reuse!
        with input_fim.open() as rst:
            out_image, out_transform = mask.mask(rst)

        # update raster metadata in case it was cropped
        # (or not filled in yet)
        out_meta.update({
            "driver": "GTiff",
            "height":out_image.shape[1],
            "width":out_image.shape[2],
            "compress": 'lzw',
            "crs":"epsg:4326",
            "count":1,
            "dtype":out_image.dtype,
            "transform":out_transform
        })
        
        input_fim = MemoryFile()
        # write out latest intermediate mask
        # .. needs to be written as file or memory file so we can use it as a
        # rasterio DatasetReader for next mask
        # xxx specify location

        with input_fim.open(**out_meta) as src:
            src.write(out_image[0], 1)

    final_memfile = MemoryFile()
    print(f"** Writing out final raster to MemoryFile **")
    with final_memfile.open(**out_meta) as dest:
        # Set every cell less than 0 to NO_DATA value
        out_image[out_image < 0] = NO_DATA
        dest.write(out_image[0], 1)

    return final_memfile

def raster_to_polygon_dataframe(input_raster_memfile, attributes):
    gpd_polygonized_raster = gpd.GeoDataFrame()
    with input_raster_memfile.open() as src:
        image = src.read(1).astype('float32')
        results = (
            {'properties': attributes, 'geometry': s} for i, (s, v) 
            in enumerate(rasterio.features.shapes(image, mask=image > 0, transform=src.transform))
        )
        geoms = list(results)
        if geoms:
            gpd_polygonized_raster  = gpd.GeoDataFrame.from_features(geoms, crs='4326')

    return gpd_polygonized_raster

def create_empty_tile(dem_memfile):
    dem = dem_memfile.read(1)
    dem[dem != 0] = 0

    memfile = MemoryFile()
    with memfile.open(
        height=dem_memfile.shape[0],
        width=dem_memfile.shape[1],
        count=1,
        compress='lzw',
        dtype=dem.dtype,
        driver="GTiff",
        crs="epsg:4326",
        transform=dem_memfile.transform
    ) as src:
        # write single-band raster
        src.write(dem, 1)
    
    return memfile
