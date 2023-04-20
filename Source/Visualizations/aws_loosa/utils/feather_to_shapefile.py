import geopandas
import argparse
import time
 
parser = argparse.ArgumentParser()
parser.add_argument("feather_file", help="file path to the feather file")
parser.add_argument("output_shapefile", help="file path to the shapefile")

args = parser.parse_args()
feather_file = args.feather_file
output_shapefile = args.output_shapefile

print(f"Loading {feather_file}")
gdf = geopandas.read_feather(feather_file)

if not output_shapefile.endswith(".shp"):
    output_shapefile = f"{output_shapefile}.shp"
    
start = time.time()
print(f"Exporting to {output_shapefile}")
gdf.to_file(output_shapefile, index=False)
print(f"Shapefile created in {round((time.time()-start), 2)} seconds")