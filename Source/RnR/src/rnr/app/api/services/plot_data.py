import os, sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

from pprint import pprint

def get_fid_data(output_dir: Path, fid: str, start_date: datetime, end_date: datetime) -> tuple[np.ndarray, np.ndarray]:
    """Reads a folder and gets the flow data for a lid

    Parameters
    ----------
    output_dir: Path
        the path to the output directory
    
    fid: str
        the feature ID to retrieve data for
    
    start_date: datetime
        the earliest date to retrieve data for
    
    end_date: datetime
        the latest date to retrieve data for
    
    Returns
    -------

    """
    list_ds = list(output_dir.glob("*.nc"))
    sorted_ds = sorted(list_ds, key=lambda x: os.path.getctime(x))
    print(sorted_ds)

    flow_array = []
    time_delta = []
    for idx, file in enumerate(sorted_ds):
        print(file)
        file_time = file.stem.split("_")[-1]
        try:
            dt = datetime.strptime(file_time, "%Y%m%d%H%M")
        except:
            dt = None
        if dt:
            if dt >= start_date and dt <= end_date:
                ds = xr.open_dataset(file, engine="netcdf4")
                flow_array.append(ds.sel(feature_id=fid).flow.values[0])
                time_delta.append(file_time)
    
    datetime_series = pd.to_datetime(time_delta, format='%Y%m%d%H%M')

    return flow_array, datetime_series