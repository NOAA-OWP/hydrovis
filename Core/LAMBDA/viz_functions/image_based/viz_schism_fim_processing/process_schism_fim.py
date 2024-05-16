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
import gc
import geopandas as gpd
import fiona
import numpy as np
import rasterio
import rasterio.mask
import rioxarray as rxr
import os
import s3fs
import xarray as xr
import json
import sys

# from fiona.model import to_dict
from rasterio.session import AWSSession
from rasterio.io import MemoryFile
from scipy.interpolate import griddata
from shapely.geometry import box
from time import sleep, time

# DO NOT LEAVE THIS COMMENTED!!!!!!!
from viz_classes import database
# database = {}

DEM_RESOLUTION = 30
GRID_SIZE = DEM_RESOLUTION / 111000 # calc degrees, assume 111km/degree
INPUTS_BUCKET = os.environ['INPUTS_BUCKET']
INPUTS_PREFIX = os.environ['INPUTS_PREFIX']
AWS_SESSION = AWSSession()
S3 = boto3.client('s3')
DOMAINS = ['atlgulf', 'pacific', 'hi', 'prvi']
NO_DATA = np.nan
METERS_TO_FT = 3.281

def main(event):
    main_start = time()
    fim_config = event['fim_config']
    target_table = fim_config['target_table']
    tile_keys = event['tile_keys']
    reference_time = event['reference_time']
    output_bucket = event['output_bucket']
    output_workspaces = event['output_workspaces']
    
    config_name = fim_config['name']
    output_workspace = next(list(workspace.values())[0] for workspace in output_workspaces if list(workspace.keys())[0] == config_name)
    domain = [d for d in DOMAINS if d in config_name][0]
    target_table_schema = target_table.split(".")[0]
    target_table = target_table.split(".")[1]

    print(f"Processing {config_name} for {reference_time}...")
    
    mask_geoms_by_group = get_mask_geoms_by_group(domain)
    fcst_points = get_fcst_point_ds(fim_config)
    process_db = database(db_type="viz")
    run_times = []
    main_end = time()
    print(f'Top-level processing (i.e. data from network to memory) time: {main_end - main_start} seconds')
    
    for tile_key in tile_keys:
        gc.collect()
        start = time()
        final_grid_memfile, polygon_df = create_fim_by_tile(tile_key, fcst_points, mask_geoms_by_group)
        end = time()
        run_times.append(end - start)
        depth_key = f"{output_workspace}/tif/{tile_key.split('/')[-1]}"
        print(f"Uploading depth grid to AWS at s3://{output_bucket}/{depth_key}")
        start = time()
        S3.upload_fileobj(
            final_grid_memfile,
            output_bucket,
            depth_key
        )
        end = time()
        print(f"Upload depth to S3 time: {end-start} seconds")

        start = time()
        if polygon_df.empty:
            print("Raster to polygon yielded no features.")
        else:
            print("Writing polygons to PostGIS database...")
            attempts = 3
            polygon_df.to_crs(3857, inplace=True)
            polygon_df.set_crs('epsg:3857', inplace=True)
            polygon_df.rename_geometry('geom', inplace=True)
            for attempt in range(attempts):
                try:
                    polygon_df.to_postgis(target_table, con=process_db.engine, schema=target_table_schema, if_exists='append')
                    break
                except Exception as e:
                    if attempt == attempts - 1:
                        raise Exception(f"Failed to add SCHISM FIM polygons to DB for {tile_key} of {config_name}: ({e})")
                    else:
                        sleep(1)
        end = time()
        print(f"Polygon to DB time: {end-start} seconds")
    process_db.engine.dispose()
    print(f'Tile processing times (in seconds): {run_times}')
    return {
        "success": True
    }

def get_mask_geoms_by_group(domain):
    print(f'Getting mask groups for {domain} domain...')
    mask_groups = {}
    masks_prefix = f'{INPUTS_PREFIX}/masks/{domain}/'
    result = S3.list_objects(Bucket=INPUTS_BUCKET, Prefix=masks_prefix)
    mask_prefixes = result.get('Contents')
    for group_key in ['interior', 'exterior']:
        print(f'... Getting {group_key} masks... ')
        mask_uris = [f"zip+s3://{INPUTS_BUCKET}/{m['Key']}" for m in mask_prefixes if group_key in m['Key']]
        geoms = []
        for uri in mask_uris:
            with fiona.open(uri, "r") as shapefile:
                geoms += [feature["geometry"] for feature in shapefile]
                # geoms += [to_dict(feature["geometry"]) for feature in shapefile]
        mask_groups[group_key] = geoms
    
    return mask_groups

def get_fcst_point_ds(fim_config):
    fim_config_preprocessing = fim_config.get('preprocess', {})
    preprocessing_output_file_format = fim_config_preprocessing.get('output_file')
    preprocessing_output_file_bucket = fim_config_preprocessing.get('output_file_bucket')
    max_elevs_file_bucket = fim_config.get('max_file_bucket', preprocessing_output_file_bucket)
    max_elevs_file = fim_config.get('max_file', preprocessing_output_file_format)
    schism_fim_s3_uri = f's3://{max_elevs_file_bucket}/{max_elevs_file}'

    print(f'Getting forecast points from NWM max_elevs file at {max_elevs_file}')
    # Get Forecast Points as in-memory xarray Dataset
    fcst_point_ds = None
    try:
        fs = s3fs.S3FileSystem()
        with fs.open(schism_fim_s3_uri, 'rb') as f:
            print("...File opened, converting to xarray Dataset...")
            with xr.load_dataset(f) as raw_ds:
                print("...Dataset created.")
                fcst_point_ds = check_names(raw_ds)
    except Exception as e:
        print(f"WARNING: {e}")
        pass

    return fcst_point_ds

def create_fim_by_tile(tile_key, fcst_points, mask_geoms_by_group):
    print(f'Processing tile {tile_key}...')
    tile_uri = f's3://{INPUTS_BUCKET}/{tile_key}'
    start = time()
    print(f'Fetching {tile_uri}...')
    dem_obj = rasterio.open(tile_uri)
    end = time()
    print(f"Tile fetch time: {end-start} seconds")

    try:
        # limit the schism data to the tile bounds
        start = time()
        clipped_npds = clip_to_bounds(fcst_points, dem_obj.bounds)
        end = time()
        print(f"Forecast points clip time: {end-start} seconds")
        
        if len(clipped_npds.x) == 0:
            print(f"!! No NWM total_water forecast points in tile {os.path.basename(tile_key)}")
            raise Exception
        print(f".. {len(clipped_npds.x)} forecast points in tile {os.path.basename(tile_key)}")
        
        # interpolate the schism data
        start = time()
        interp_grid_memfile = interpolate(clipped_npds, GRID_SIZE)
        del clipped_npds
        end = time()
        print(f"Interpolation time: {end-start} seconds")

        # subtract dem from schism data 
        # (includes code to match extent/resolution)
        start = time()
        wse_grid = wse_to_depth(interp_grid_memfile, dem_obj)
        del interp_grid_memfile
        end = time()
        print(f"WSE to Depth time: {end-start} seconds")
        if wse_grid is None:
            print("!! No overlap between raster and DEM")
            raise Exception

        # apply masks
        start = time()
        final_grid_memfile = mask_fim(wse_grid, mask_geoms_by_group)
        del wse_grid
        end = time()
        print(f"Apply masks time: {end-start} seconds")
    except Exception as e:
        print(e)
        print("Issue encountered (see above). Creating empty tile...")
        final_grid_memfile = create_empty_tile(dem_obj)

    dem_obj.close()
    print("Converting depth to binary fim...")
    # translate all > 0 depth values to 1 for wet (everything else [dry] already 0)
    start = time()
    binary_fim_memfile = fim_to_binary(final_grid_memfile)
    end = time()
    print(f"FIM to Binary time: {end-start} seconds")
    start = time()
    polygon_df = raster_to_polygon_dataframe(binary_fim_memfile, {})
    end = time()
    print(f"Raster to polygon DF time: {end-start} seconds")

    print(f"Successfully processed tile {os.path.basename(tile_key)}")
    return final_grid_memfile, polygon_df

#
# Clips SCHISM forecast points to fit some shapefile bounds
#
def clip_to_bounds(fcst_points, bounds):
    print("Clipping SCHISM max_elevs domain to new tile domain...")

    fcst_points_clipped = fcst_points.where(
        ((fcst_points.x < bounds[2]) & #x_max
        (fcst_points.x > bounds[0]) & #x_min
        (fcst_points.y < bounds[3]) & #y_max
        (fcst_points.y > bounds[1])), #y_min
        NO_DATA
    )
    
    fcst_points_clipped = fcst_points_clipped.dropna('node', how="any")
    
    return fcst_points_clipped

def check_names(f):
    # time series netcdf needs to have x, y, and elev variables
    # ... SCHISM files operationally might use "elevation",
    # "SCHISM_hgrid_node_x" and "SCHISM_hgrid_node_y", so
    # renmame those variables because xarray and rasterio-based
    # functionality require x and y names for matching projections,
    # extents, and resolution
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

    # get bounding box of forecast points 
    x_min = np.min(numpy_ds.x)
    x_max = np.max(numpy_ds.x)
    y_min = np.min(numpy_ds.y)
    y_max = np.max(numpy_ds.y)

    print("...Creating grid and interpolating...")
    # interpolate over forecast points' elevation data onto the new xx-yy grid
    # .. cubic is also an option for cubic spline, vs barycentric linear
    # .. or nearest, for nearest neighbor, but that's slower (better for depth?)

    # reverse order rows are stored in to match with descending y / lat values
    interp_grid = np.flip(
        griddata(
            np.column_stack((numpy_ds.x, numpy_ds.y)), 
            numpy_ds.elev if len(numpy_ds.elev.dims) == 1 else numpy_ds.elev[0],
            tuple(
                np.meshgrid(
                    np.arange(x_min, x_max, grid_size),
                    np.arange(y_min, y_max, grid_size)
                )
            ), 
            method="linear"
        ),
        0
    )

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

    print("Translating to binary fim")
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

def mask_fim(input_fim, mask_geoms_by_group):
    out_meta = {}

    for group, geoms in mask_geoms_by_group.items():
        gc.collect()
        if not geoms: continue
        print(f'... Applying {group} masks...')
        
        # open the latest intermediate file and mask out the next mask
        # ... need rst in rasterio DatasetReader format, so need to save
        # as file or memory file, because the rasterio mask function does not
        # return out_image in a format we can directly reuse!
        start = time()
        with input_fim.open() as rst:
            out_image, out_transform = rasterio.mask.mask(
                rst, 
                geoms, 
                crop=(group != 'interior'), 
                invert=(group == 'interior'), 
                nodata=NO_DATA
            )
        end = time()
        print(f'Apply single mask time: {end - start} seconds')

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

        start = time()
        with input_fim.open(**out_meta) as src:
            src.write(out_image[0], 1)
        end = time()
        print(f'Write mask output (numpy array) to memory file time: {end - start} seconds')

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

if __name__ == "__main__":
    main(json.loads(sys.argv[1]))
