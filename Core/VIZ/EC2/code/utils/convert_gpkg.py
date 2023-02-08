import geopandas
import os
import csv

fim_version = "3_0_28_1"
fim_configuration = "fr"

fields = ['HydroID', 'geometry']
rename = {
    'HydroID': 'hydro_id'
}

catchments_gpkgs = f"/dev_fim_share/foss_fim/previous_fim/fim_{fim_version}_{fim_configuration}"

gpks_filename = "gw_catchments_reaches_filtered_addedAttributes_crosswalked.gpkg"

huc2s = {}
for catchment in os.listdir(catchments_gpkgs):
    try:
        int(catchment)
        if catchment[:2] not in huc2s:
            huc2s[catchment[:2]] = []

        huc2s[catchment[:2]].append(catchment)
    except Exception as e:
        print(e)

print("Processing Catchments")
for huc2, catchments in huc2s.items():

    huc2_csv_output = f"/home/corey.krewson/huc2_{huc2}_fim_catchments_{fim_version}_{fim_configuration}.csv"
    huc2_started = False

    for catchment in catchments:
        #gpks_filename = f"catchments_{catchments}.gpkg"
        catchments_file = os.path.join(catchments_gpkgs, catchment, gpks_filename)

        if not huc2_started:
            print(f"Creating Catchments GeoDataFrame to {huc2} ({catchments_file})")
            gdf_catchments = geopandas.read_file(catchments_file)
            gdf_catchments = gdf_catchments[fields]
            gdf_catchments = gdf_catchments.to_crs("EPSG:3857")
            huc2_started = True
        else:
            print(f"Merging Catchments GeoDataFrame to {huc2} ({catchments_file})")
            gdf = geopandas.read_file(catchments_file)
            gdf = gdf[fields]
            gdf = gdf.to_crs("EPSG:3857")
            gdf_catchments = gdf_catchments.append(gdf)

    gdf_catchments = gdf_catchments[fields]
    gdf_catchments = gdf_catchments[~gdf_catchments['HydroID'].duplicated(keep='first')]
    gdf_catchments = gdf_catchments.rename(columns=rename)
    gdf_catchments['fim_version'] = fim_version
    print(f"Writing Catchments GeoDataFrame to {huc2_csv_output}")
    gdf_catchments.to_csv(huc2_csv_output, index=False)
