################################
#
# SCHISM FIM Workflow
# 
# This script takes a SCHISM netCDF file and generates
# a FIM tif for the specified HUC8s along the coast.
#
# Author: Laura Keys, laura.keys@noaa.gov
#
################################
import boto3
import datetime as dt
import geopandas as gp
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
from rasterio.io import MemoryFile
from rasterio.merge import merge
from rasterio.session import AWSSession
from shapely.geometry import box
from time import sleep

from viz_classes import database

DEM_RESOLUTION = 30
GRID_SIZE = DEM_RESOLUTION / 111000 # calc degrees, assume 111km/degree
INPUTS_BUCKET = os.environ['INPUTS_BUCKET']
INPUTS_PREFIX = os.environ['INPUTS_PREFIX']
MAX_VALS_BUCKET = os.environ['MAX_VALS_BUCKET']
OUTPUTS_BUCKET = os.environ['OUTPUTS_BUCKET']
OUTPUTS_PREFIX = os.environ['OUTPUTS_PREFIX']
AWS_SESSION = AWSSession()
S3 = boto3.client('s3')
DOMAINS = ['atlgulf', 'pacific', 'hawaii', 'puertorico']
NO_DATA = np.nan
METERS_TO_FT = 3.281


def lambda_handler(event, context):
    step = event['step']
    reference_time = event['args']['reference_time']
    sql_rename_dict = event['args']['sql_rename_dict']
    fim_config = event['args']['fim_config']['name']
    product = event['args']['product']['product']
    target_table = event['args']['fim_config']['target_table']
    max_elevs_file_bucket = event['args']['fim_config']['max_elevs_file_bucket']
    max_elevs_file = event['args']['fim_config']['max_elevs_file']
    schism_fim_s3_uri = f's3://{max_elevs_file_bucket}/{max_elevs_file}'

    reference_date = dt.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    
    print(f"Processing the {fim_config} fim config")
        
    if step == 'setup':
        temp_folder = tempfile.gettempdir()
        local_csv_fpath = os.path.join(temp_folder, 'hucs.csv')
        S3.download_file(INPUTS_BUCKET, f'{INPUTS_PREFIX}/hucs/hucs.csv', local_csv_fpath)
        with open(local_csv_fpath, 'r') as f:
            hucs = f.read().strip().split('\n')[1:]
        engine = database(db_type="viz").engine
        engine.execute(f'DROP TABLE IF EXISTS {target_table};')
        engine.dispose()
        return hucs
    elif step == 'iteration':
        huc = event['huc']
        depth_key = create_fim_by_huc(huc, schism_fim_s3_uri, product, fim_config, reference_date, target_table)
        return {
            'output_bucket': OUTPUTS_BUCKET,
            'output_key': depth_key
        }

def create_fim_by_huc(huc, schism_fim_s3_uri, product, fim_config, reference_date, target_table):
    domain = [d for d in DOMAINS if d in schism_fim_s3_uri][0]
    full_ref_time = reference_date.strftime("%Y-%m-%D %H:%M:%S UTC")
    ref_date_str = reference_date.strftime("%Y%m%D")
    hour = reference_date.strftime("%H")

    target_table_schema = target_table.split(".")[0]
    target_table = target_table.split(".")[1]

    depth_key = f'{OUTPUTS_PREFIX}/{product}/{fim_config}/{ref_date_str}/{hour}/workspace/tif/{huc}.tif'
    dem_filename = f's3://{INPUTS_BUCKET}/{INPUTS_PREFIX}/dems/{domain}/{huc}.tif'
    coastal_hucs = f'zip+s3://{INPUTS_BUCKET}/{INPUTS_PREFIX}/hucs/coastal_huc8s_wgs1984.zip'
    masks_root = f'zip+s3://{INPUTS_BUCKET}/{INPUTS_PREFIX}/masks'
    temp_folder = tempfile.mkdtemp()
    bounds = None

    print("Executing lambda handler...")
    print(f"Writing tempfiles to {temp_folder}")

    with fiona.Env(session=AWS_SESSION):
        with fiona.open(coastal_hucs, "r") as shapefile:
            for feature in shapefile:
                if feature['properties']['huc8_str'] == huc:
                    bounds = feature['geometry']
                    break

    if not bounds:
        raise Exception(f'HUC {huc} not found in file {coastal_hucs}')
    
    print(f'Processing Schism FIM for HUC {huc}...')
    # limit the schism data to only the relevant HUC8
    clipped_npds = clip_to_extent(schism_fim_s3_uri, bounds, temp_folder)
    if len(clipped_npds.x) == 0:
        print(f"!! No forecast points in netCDF in HUC {huc}")
        return
    else:
        print(f".. {len(clipped_npds.x)} forecast points in HUC {huc}")

    # interpolate the schism data
    interp_grid_file = interpolate(clipped_npds, GRID_SIZE, temp_folder)

    # subtract dem from schism data 
    # (includes code to match extent/resolution)
    wse_grid = wse_to_depth(interp_grid_file, dem_filename, temp_folder)
    if wse_grid == "":
        print("!! No overlap between raster and DEM")
        return

    # apply masks
    masked_grid = mask_fim(wse_grid, masks_root, domain, temp_folder)
    
    print(f"Uploading depth grid to AWS at s3://{OUTPUTS_BUCKET}/{depth_key}")
    S3.upload_file(masked_grid, OUTPUTS_BUCKET, depth_key)

    # translate all > 0 depth values to 1 for wet (everything else [dry] already 0)
    binary_fim = fim_to_binary(masked_grid, temp_folder)
    
    # We shouldn't need to clip since the raster is already at the HUC level
    # clipped_result = clip_to_shape(binary_fim, bounds)

    update_time = dt.datetime.now().strftime('%y-%m-%d %H:%M%S UTC')

    attributes = {
        'huc8': huc,
        'ref_time': full_ref_time,
        'update_time': update_time
    }

    polygon_df = raster_to_polygon_dataframe(binary_fim, attributes)


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
                    raise Exception(f"Failed to add SCHISM FIM polygons to DB for HUC {huc}: ({e})")
                else:
                    sleep(1)
        process_db.engine.dispose()
    
    print("Removing temp files...")
    rmtree(temp_folder)

    print(f"Successfully processed SCHISM FIM for HUC {huc} of {fim_config} for {ref_date_str}")
    return depth_key

#
# Clips SCHISM forecast points to fit some shapefile bounds
#
def clip_to_extent(schism_fim_s3_uri, clip_bounds, temp_folder):
    print("++ Clipping SCHISM point domain to new domain ++")

    bounds = rasterio.features.bounds(clip_bounds)
    fs = s3fs.S3FileSystem()
    print(f'Opening {schism_fim_s3_uri}...')
    with fs.open(schism_fim_s3_uri, 'rb') as f:
        with xr.open_dataset(f) as n:
            n_ = check_names(n)
            n_clip = n_.where(
                ((n_.x < bounds[2]) & #x_max
                (n_.x > bounds[0]) & #x_min
                (n_.y < bounds[3]) & #y_max
                (n_.y > bounds[1])), #y_min
                    np.nan)

    n_clip = n_clip.dropna('node', how="any")
    
    return n_clip

def check_names(f):
    try:
        f = f.rename({'SCHISM_hgrid_node_x':'x',
            'SCHISM_hgrid_node_y':'y',
            'elevation':'elev'})
        print("..Renamed variables in netcdf.")
    except:
        print("..No variables to rename in netcdf. Good!") 
    try:
        f = f.rename_dims({'nSCHISM_hgrid_node':'node'})
        print("..Renamed dim in netcdf.")
    except:
        print("..No dimension to rename in netcdf. Good!") 

    return f

def interpolate(numpy_ds, grid_size, temp_folder):
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
    xx, yy = np.meshgrid(np.arange(x_min, x_max, grid_size), \
        np.arange(y_min, y_max, grid_size)) 

    print(f"** Number of SCHISM forecast points: {len(coords)}")

    # interpolation
    print("*** Interpolating ***")
    # interpolate over forecast points' elevation data onto the new xx-yy grid
    # .. cubic is also an option for cubic spline, vs barycentric linear
    # .. or nearest, for nearest neighbor, but that's slower (better for depth?)
    interp_grid = griddata(coords, el, (xx, yy), method="linear")

    # reverse order rows are stored in to match with descending y / lat values
    interp_grid = np.flip(interp_grid, 0)

    # write out interpolated raster to file or to a memory file for later use
    interp_file = os.path.join(temp_folder, 'interp_temp.tif') # xxx
    with rasterio.open(interp_file, 'w',
            height=interp_grid.shape[0],
            width=interp_grid.shape[1],
            count=1,
            compress='lzw',
            dtype=interp_grid.dtype,
            driver="GTiff",
            crs="epsg:4326",
            transform=rasterio.transform.from_origin(
                x_min, y_max, grid_size, grid_size)) as src:
        # write single-band raster
        src.write(interp_grid, 1)
    return interp_file

def wse_to_depth(interp_grid, dem_filename, temp_folder):
    # clip the interpolated rst and dem to match bounding boxes
    with rasterio.open(interp_grid) as rst:
        rst_bounds = rst.bounds
        with rasterio.Env(AWS_SESSION):
            with rasterio.open(dem_filename) as dem:
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
                        nodata=np.nan)
                    dem_masked, dem_trans = rasterio.mask.mask(dem, [feature],
                        crop=True,
                        #nodata=0)
                        nodata=np.nan)
                except:
                    # no overlapping area for the raster and dem
                    return ""

    # write out rst_masked with updated metadata
    # (can write to memory file instead)
    #
    # ... writing these to a file or memfile lets us use them as rasterio
    # DatasetReader later, which makes it easier to match their extents and
    # resolution perfectly to allow us to subtract correctly
    with rasterio.open(os.path.join(temp_folder, 'temprst.tif'), 'w', # xxx
            height=rst_masked.shape[1],
            width=rst_masked.shape[2],
            count=1,
            compress='lzw',
            dtype=rst_masked.dtype,
            driver="GTiff",
            crs="epsg:4326",
            transform=rst_trans) as src:
        # write single-band raster
        src.write(rst_masked[0], 1)

    # write out dem with updated metadata
    with rasterio.open(os.path.join(temp_folder, 'tempdem.tif'), 'w', #xxx
            height=dem_masked.shape[1],
            width=dem_masked.shape[2],
            count=1,
            compress='lzw',
            dtype=dem_masked.dtype,
            driver="GTiff",
            crs="epsg:4326",
            transform=dem_trans) as src:
        # write single-band raster
        src.write(dem_masked[0], 1)

    # match resolution and coordinates of dem to the interpolation
    # .. even if the extent and resolution are the same, it's good to do
    # this to be absolutely certain before trying to do raster math
    with rxr.open_rasterio(os.path.join(temp_folder, 'temprst.tif')) as rst_masked:
        with rxr.open_rasterio(os.path.join(temp_folder, 'tempdem.tif')) as dem_masked:
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
    wse_file = os.path.join(temp_folder, 'wse_temp.tif') #xxx
    wse_depth.rio.to_raster(wse_file)
    return wse_file

def fim_to_binary(wse_file, temp_folder):
    wse_rst = rasterio.open(wse_file)
    interp_grid = wse_rst.read(1)

    print("+++ Translating to binary fim")
    interp_grid[interp_grid > 0] = 1

    '''
    # example of memory file writing
    # write to memfile
    memfile = MemoryFile()
    with memfile.open(
        height=interp_grid.shape[0],
        width=interp_grid.shape[1],
        count=1,
        dtype=interp_grid.dtype,
        driver="GTiff",
        crs="epsg:4326",
        transform=rasterio.transform.from_origin(x_min, y_max, grid_size, grid_size)) as src:
        # write single-band raster
        src.write(interp_grid, 1)
    '''


    fim_file = os.path.join(temp_folder, 'fim_temp.tif') #xxx
    # need interpolation in rasterio DatasetReader format for easy masking
    # steps, so need to save as file or memory file because it's a
    # numpy array right here
    with rasterio.open(fim_file, 'w', 
            height=interp_grid.shape[0],
            width=interp_grid.shape[1],
            count=1,
            dtype=interp_grid.dtype,
            compress='lzw',
            driver="GTiff",
            crs="epsg:4326",
            transform=wse_rst.transform) as src:
        # write single-band raster
        src.write(interp_grid, 1)
    
    return fim_file 

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
        return

    def mask(self, rst):
        # get all the masking shapefile coordinates
        with fiona.Env(session=AWS_SESSION):
            with fiona.open(self.fpath, "r") as shapefile:
                geoms = [feature["geometry"] for feature in shapefile]

        out_image, out_transform = rasterio.mask.mask(
            rst, geoms, crop=self.crop, invert=self.invert, nodata=NO_DATA)
        return out_image, out_transform

def mask_fim(input_fim, masks_root, domain, temp_folder):
    out_meta = {}

    # list of mask locations and "interior" or "exterior" (see Mask Class)
    mask_list = [
        Mask(f'{masks_root}/mask_water_polygon_conus.zip', "interior"),
        Mask(f'{masks_root}/mask_nwm_lakes_conus.zip', "interior"),
        Mask(f'{masks_root}/mask_levee_protected_area_conus.zip', "interior"),
        Mask(f'{masks_root}/mask_schism_boundary_{domain}.zip', "exterior"),
        Mask(f'{masks_root}/mask_us_boundary.zip', "exterior")
    ]

    current_raster = input_fim
    for mask_number, mask in enumerate(mask_list, 1):
        print(f'** Applying mask: {mask.fpath} **')
        
        # open the latest intermediate file and mask out the next mask
        # ... need rst in rasterio DatasetReader format, so need to save
        # as file or memory file, because the rasterio mask function does not
        # return out_image in a format we can directly reuse!
        with rasterio.open(current_raster) as rst:
            out_image, out_transform = mask.mask(rst)

        # update raster metadata in case it was cropped
        # (or not filled in yet)
        out_meta.update({"driver": "GTiff",
            "height":out_image.shape[1],
            "width":out_image.shape[2],
            "compress": 'lzw',
            "crs":"epsg:4326",
            "count":1,
            "dtype":out_image.dtype,
            "transform":out_transform})
        
        current_raster = f'{temp_folder}/temp{mask_number}.tif'
        # write out latest intermediate mask
        # .. needs to be written as file or memory file so we can use it as a
        # rasterio DatasetReader for next mask
        # xxx specify location
        with rasterio.open(current_raster, 'w', **out_meta) as src:
            src.write(out_image[0], 1)

    # write over mosaiced raster with masked version
    final_filename = input_fim
    print(f"** Writing out final raster to {final_filename} **")
    with rasterio.open(final_filename, "w", **out_meta) as dest:
        # Set every cell less than 0 to NO_DATA value
        out_image[out_image < 0] = NO_DATA
        dest.write(out_image[0], 1)

    return final_filename

def clip_to_shape(current_raster, final_clip_bounds):
    # after all masks are applied, clip to HUC8 shape and save
    with rasterio.open(current_raster) as rst:
        try:
            out_image, out_transform = rasterio.mask.mask(
                #rst, [final_clip_bounds], crop=True, nodata=0)
                rst, [final_clip_bounds], crop=True, nodata=np.nan)
            out_meta = {"driver": "GTiff",
                "height":out_image.shape[1],
                "width":out_image.shape[2],
                "compress": 'lzw',
                "crs":"epsg:4326",
                "count":1,
                "dtype":out_image.dtype,
                "transform":out_transform}
        except:
            print(".. No overlap in clipping bounds and interpolation.")

    # overwrite input file
    final_filename = current_raster
    with rasterio.open(final_filename, "w", **out_meta) as dest:
        dest.write(out_image[0], 1)

    return final_filename

def raster_to_polygon_dataframe(input_raster, attributes):
    gpd_polygonized_raster = gp.GeoDataFrame()
    with rasterio.Env(AWS_SESSION):
        with rasterio.open(input_raster) as src:
            image = src.read(1).astype('float32')
            results = (
                {'properties': attributes, 'geometry': s} for i, (s, v) 
                in enumerate(rasterio.features.shapes(image, mask=image > 0, transform=src.transform))
            )
            geoms = list(results)
            if geoms:
                gpd_polygonized_raster  = gp.GeoDataFrame.from_features(geoms, crs='4326')
    
    return gpd_polygonized_raster

def mosaic_rasters(raster_s3_uris):
    temp_dir = tempfile.mkdtemp()
    temp_result_fpath = os.path.join(temp_dir, 'mosaic.tif')
    if len(raster_s3_uris) == 0:
        print("!! No FIM results to mosaic, returning empty string")
        return ""

    # fix a glitch in numpy and rasterio merge combo
    def pre121_max(old_data, new_data, old_nodata, new_nodata, **kwargs):
        mask = np.logical_and(~old_nodata, ~new_nodata)
        old_data[mask] = np.maximum(old_data[mask], new_data[mask])
        mask = np.logical_and(old_nodata, ~new_nodata)
        old_data[mask] = new_data[mask]

    # work around the glitch by setting nan values to 0 so we can do a max
    memfiles = []
    for uri in raster_s3_uris:
        print(f'Fetching from s3 to memory: {uri}')
        with rasterio.Env(AWS_SESSION):
            with rasterio.open(uri) as rst:
                data = rst.read()
                data = np.nan_to_num(data)
                meta = rst.profile
        memfile = MemoryFile()
        memfiles.append(memfile.open(**meta))
        memfiles[-1].write(data[0], 1)
        S3.delete_object(Bucket=OUTPUTS_BUCKET, Key=uri.split(OUTPUTS_BUCKET)[1][1:])
    merged_ras, merged_trans = merge(memfiles, method=pre121_max)
    for m in memfiles:
        m.close()
    # set the 0 values back to nan
    merged_ras[merged_ras==0] = np.nan
    merged_meta = {"driver": "GTiff",
        "height": merged_ras.shape[1],
        "width": merged_ras.shape[2],
        "compress": 'lzw',
        "crs": "epsg:4326",
        "count": 1,
        "dtype": merged_ras.dtype,
        "transform": merged_trans}

    print(f"+++ Writing out mosaic'd raster to {temp_result_fpath} +++")
    with rasterio.open(temp_result_fpath, "w", **merged_meta) as dest:
        dest.write(merged_ras[0], 1)
    
    return temp_result_fpath
