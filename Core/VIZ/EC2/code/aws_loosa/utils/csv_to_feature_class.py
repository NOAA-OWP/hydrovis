# This is a simple script to save a feature class from a csv file, with shape data represented as WKT.
import pandas as pd
from geopandas import GeoDataFrame
from shapely import wkt
from arcgis.features import GeoAccessor

def convert_csv_to_feature_class(csv_file, feature_class, geometry_column_name='geom', crs="EPSG:3857"):
    df = pd.read_csv(csv_file)
    gdf = GeoDataFrame(df, crs=crs, geometry=df[geometry_column_name].apply(wkt.loads))
    gdf = gdf.drop(columns=['geom'])
    sedf = GeoAccessor.from_geodataframe(gdf)

    sedf.spatial.to_featureclass(feature_class)
    return

########################################################################################################################################
if __name__ == '__main__':
    csv = r"C:\Users\Administrator\Downloads\ana_past_14day_max_inundation.csv"
    fc = r"C:\Users\Administrator\Downloads\test2.gdb\ana_inun_14d" #This can be picky on names, use simple names
    convert_csv_to_feature_class(csv, fc)