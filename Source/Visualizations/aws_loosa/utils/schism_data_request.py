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
import xarray as xr

from scipy.interpolate import griddata
from rasterio.session import AWSSession
from shapely.geometry import box
from time import sleep
from rasterio.io import MemoryFile

DEM_RESOLUTION = 30
GRID_SIZE = DEM_RESOLUTION / 111000 # calc degrees, assume 111km/degree
INPUTS_BUCKET = os.environ['INPUTS_BUCKET']
INPUTS_PREFIX = os.environ['INPUTS_PREFIX']
AWS_SESSION = AWSSession()
S3 = boto3.client('s3')
DOMAINS = ['atlgulf', 'pacific', 'hawaii', 'puertorico']
NO_DATA = np.nan
METERS_TO_FT = 3.281


def main(event, output_directory):
    tile_basename = event['tile_basename']
    reference_time = event['reference_time']
    fim_config = event['fim_config']
    max_elevs_file_bucket = event['max_file_bucket']
    max_elevs_file = event['max_file']

    if os.path.exists(os.path.join(output_directory, tile_basename.replace('.tif', '_wse.tif'))):
        return

    print(f"Processing {tile_basename} of {fim_config} for {reference_time}...")
    schism_fim_s3_uri = f's3://{max_elevs_file_bucket}/{max_elevs_file}'
    domain = [d for d in DOMAINS if d in schism_fim_s3_uri][0]
    
    max_elevs_fname = os.path.basename(max_elevs_file)
    max_elevs_fpath = os.path.join(output_directory, max_elevs_fname)
    if not os.path.exists(max_elevs_fpath):
        print('Downloading max_elevs_file from S3...')
        S3.download_file(max_elevs_file_bucket, max_elevs_file, max_elevs_fpath)
    
    dem_fname = tile_basename.replace('.tif', '_dem.tif')
    dem_fpath = os.path.join(output_directory, dem_fname)
    if not os.path.exists(dem_fpath):
        print('Downloading dem from S3...')
        S3.download_file(INPUTS_BUCKET, f'{INPUTS_PREFIX}/dems/{domain}/{tile_basename}', dem_fpath)

    inmem_depth_raster = create_fim_by_tile(domain, dem_fpath, max_elevs_fpath, output_directory)

    with inmem_depth_raster.open() as inmem:
        inmem_obj = inmem.read()
        with rasterio.open(
            os.path.join(output_directory, tile_basename.replace('.tif', '_depth.tif')), 
            'w',
            driver='GTiff',
            height=inmem.shape[0],
            width=inmem.shape[1],
            count=1,
            dtype=inmem_obj.dtype,
            compress='lzw',
            crs="epsg:4326",
            transform=inmem.transform
        ) as f:
            f.write(inmem_obj[0], 1)
    
    print(f"... Done!")

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

def create_fim_by_tile(domain, dem_fpath, max_elevs_fpath, output_directory):
    dem_fname = os.path.basename(dem_fpath)
    dem_obj = rasterio.open(dem_fpath)

    try:
        # limit the schism data to the tile bounds
        clipped_npds = clip_to_bounds(max_elevs_fpath, dem_obj.bounds)
        
        if len(clipped_npds.x) == 0:
            print(f"!! No forecast points in netCDF in tile {dem_fname}")
            raise Exception

        print(f".. {len(clipped_npds.x)} forecast points in tile {dem_fname}")
        # interpolate the schism data
        interp_grid_memfile = interpolate(clipped_npds, GRID_SIZE)

        # subtract dem from schism data 
        # (includes code to match extent/resolution)
        wse_grid = wse_to_depth(interp_grid_memfile, dem_obj, output_directory, dem_fname)
        if wse_grid is None:
            print("!! No overlap between raster and DEM")
            raise Exception

        # apply masks
        final_grid_memfile = mask_fim(wse_grid, domain)
    except Exception as e:
        print(e)
        print("Issue encountered (see above). Creating empty tile...")
        final_grid_memfile = create_empty_tile(dem_obj)

    try:
        dem_obj.close()
    except:
        pass
    
    return final_grid_memfile

#
# Clips SCHISM forecast points to fit some shapefile bounds
#
def clip_to_bounds(max_elevs_fpath, bounds):
    print("Clipping SCHISM max_elevs domain to new tile domain...")

    fs = s3fs.S3FileSystem()
    print(f'...Opening {max_elevs_fpath}...')
    with xr.open_dataset(max_elevs_fpath) as n:
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

def wse_to_depth(interp_grid_memfile, dem, output_directory, dem_fname):
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
    

    with temp_rst_memfile.open() as inmem:
        inmem_obj = inmem.read()
        with rasterio.open(
            os.path.join(output_directory, dem_fname.replace('_dem.tif', '_wse.tif')), 
            'w',
            driver='GTiff',
            height=inmem.shape[0],
            width=inmem.shape[1],
            count=1,
            dtype=inmem_obj.dtype,
            compress='lzw',
            crs="epsg:4326",
            transform=inmem.transform
        ) as f:
            f.write(inmem_obj[0], 1)

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
        driver="GTiff",
        compress='lzw',
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

def setup_db_table(db_fim_table, viz_db, sql_replace=None):
    """
        Sets up the necessary tables in a postgis data for later ingest from the huc processing functions

        Args:
            configuration(str): product configuration for the product being ran (i.e. srf, srf_hi, etc)
            reference_time(str): Reference time of the data being ran
            sql_replace(dict): An optional dictionary by which to use to create a new table if needed
    """
    index_name = f"idx_{db_fim_table.split('.')[-1:].pop()}_hydro_id"
    db_schema = db_fim_table.split('.')[0]

    print(f"Setting up {db_fim_table}")
        
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()

         # See if the target table exists #TODO: Ensure table exists would make a good helper function
        cur.execute(f"SELECT EXISTS (SELECT FROM pg_tables WHERE schemaname = '{db_fim_table.split('.')[0]}' AND tablename = '{db_fim_table.split('.')[1]}');")
        table_exists = cur.fetchone()[0]
        
        # If the target table doesn't exist, create one basd on the sql_replace dict.
        if not table_exists:
            print(f"--> {db_fim_table} does not exist. Creating now.")
            original_table = list(sql_replace.keys())[list(sql_replace.values()).index(db_fim_table)] #ToDo: error handling if not in list
            cur.execute(f"DROP TABLE IF EXISTS {db_fim_table}; CREATE TABLE {db_fim_table} (LIKE {original_table})")
            connection.commit()

        # Drop the existing index on the target table
        print("Dropping target table index (if exists).")
        SQL = f"DROP INDEX IF EXISTS {db_schema}.{index_name};"
        cur.execute(SQL)

        # Truncate all records.
        print("Truncating target table.")
        SQL = f"TRUNCATE TABLE {db_fim_table};"
        cur.execute(SQL)
        connection.commit()
    
    return db_fim_table


if __name__ == "__main__":
    os.environ['AWS_PROFILE'] = 'prod'
    os.environ['INPUTS_BUCKET'] = 'hydrovis-prod-deployment-us-east-1'
    os.environ['INPUTS_PREFIX'] = 'schism_fim'

    TEMPLATE_EVENT = {
        "reference_time": "%Y-%m-%d %H:00:00",
        "fim_config": "ana_coastal_inundation_{domain}",
        "max_file_bucket": "hydrovis-prod-fim-us-east-1",
        "max_file": "max_elevs/analysis_assim_coastal_{domain}/%Y%m%d/ana_coastal_{domain}_%H_max_elevs.nc",
        "tile_basename": "<<<placeholder>>>"
    }

    root_output_directory = 'C:\\Users\\shawn.crawley\\Desktop\\fim_request_dec11'
    start_dt = dt.datetime(2023, 12, 11, 00)
    end_dt = dt.datetime(2023, 12, 11, 23)
    delta = dt.timedelta(hours=1)
    iter_props = [
        {
            'domain': 'atlgulf',
            'basenames': [
                '08070202.tif',
                '03120001.tif'
            ]
        },
        {
            'domain': 'pacific',
            'basenames': [
                '17100203.tif'
            ]
        }
    ]

    iter_dt = start_dt

    while iter_dt <= end_dt:
        for props in iter_props:
            output_directory = os.path.join(root_output_directory, iter_dt.strftime('%Y%m%d%H'), props['domain'])
            os.makedirs(output_directory, exist_ok=True)
            for basename in props['basenames']:
                event = TEMPLATE_EVENT.copy()
                event['reference_time'] = iter_dt.strftime(TEMPLATE_EVENT['reference_time'])
                event['fim_config'] = TEMPLATE_EVENT['fim_config'].format(domain=props['domain'])
                event['max_file'] = iter_dt.strftime(TEMPLATE_EVENT['max_file']).format(domain=props['domain'])
                event['tile_basename'] = basename
                main(event, output_directory)
        iter_dt += delta