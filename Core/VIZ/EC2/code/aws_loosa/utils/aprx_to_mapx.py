import sys
import os
import arcpy

def aprx_to_mapx(aprx_fpath, mapx_fpath=None, map_index=0):
    aprx = arcpy.mp.ArcGISProject(aprx_fpath)
    if not mapx_fpath:
        mapx_fpath = fpath.replace('.aprx', '.mapx')
    
    aprx.listMaps()[map_index].exportToMAPX(mapx_fpath)

if __name__ == "__main__":
    mapx_or_aprx_dpath = sys.argv[1]
    mapx_or_aprx_fpaths = [os.path.join(mapx_or_aprx_dpath, file) for file in os.listdir(mapx_or_aprx_dpath)]
    for fpath in mapx_or_aprx_fpaths:
        if fpath.endswith('.aprx'):
            print(f"Converting {fpath} to .mapx file...")
            aprx_to_mapx(fpath)
            os.remove(fpath)
