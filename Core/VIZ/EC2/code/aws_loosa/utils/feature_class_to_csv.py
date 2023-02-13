# This is a simple script to save a feature class as a csv file, with shape data converted to WKT.
# Just change the paths accordingly.
# You can also replace "SHAPE@WKT" with any "token" described in the arcpy SearchCursor class documentation (json, centroids, area, length, etc.):
# ToDo: Put this in a function so it can be used in other scripts
# https://pro.arcgis.com/en/pro-app/latest/arcpy/data-access/searchcursor-class.htm

import arcpy, csv

##### Inputs #####
fc = r"C:\Users\tyler.schrag\Desktop\data\mrf_max_inundation.gdb\mrf_inun_10day"
outfile = r"C:\Users\tyler.schrag\Desktop\ida_mrf_ten_day_fim.csv"
shape_representation = "SHAPE@WKT"
##################

fields = arcpy.ListFields(fc)
field_names = [field.name for field in fields]
field_names = [shape_representation if x.lower() == "shape" else x for x in field_names]

with open(outfile,'w',newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(field_names)
    with arcpy.da.SearchCursor(fc, field_names) as cursor:
    	for row in cursor:
            field_vals = [row[x] for x in range(0,len(field_names))]
            w.writerow(field_vals)