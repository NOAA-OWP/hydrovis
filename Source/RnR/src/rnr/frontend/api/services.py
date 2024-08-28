import os, sys
from csv import DictReader
from datetime import datetime

from fastapi import Request
from src.rnr.frontend.core import get_settings

import xarray as xr

from pprint import pprint

settings = get_settings()


class DataSearchService:
    """
    Service class for handling search of the CSV and plot files.

    Methods
    -------
    search_csv_data()
        Takes input parameters and returns a dataset of all matching forecasts, including related CSV files.
    
    search_plot_data()
        Takes input parameters and returns a dataset of all matching forecasts, including related CSV and plot files.
    """

    @staticmethod
    async def search_csv_data(
        request: Request, lid: str, start_date: str, end_date: str
    ):
        """
        Returns a dataset of all matching forecasts.

        Parameters
        ----------
        request: Request
            A Request object passed in by the router.
        lid : str
            The Location ID.
        start_date : str
            The earliest date to search on, formatted as YYYY-MM-DD.
        end_date : str
            The latest date to search on, formatted as YYYY-MM-DD.

        Returns
        -------
        Dict
            A dictionary containing the search results, with each LID as a key.
        """

        csv_search_context = {
            key: request.query_params[key] for key in request.query_params
        }

        csv_search_context["errors"] = {}

        csv_search_context["lids"] = [
            f.name
            for f in os.scandir(os.path.normpath(settings.csv_docs_location))
            if f.is_dir()
        ]

        if lid != "" and lid not in csv_search_context["lids"]:
            csv_search_context["errors"]["lid"] = "Invalid LID"
            lid = ""

        try:
            csv_search_context["start_date"] = start_date
            csv_search_context["start_date_formatted"] = datetime.strptime(
                start_date, "%Y-%m-%d"
            ).strftime("%Y%m%d")
        except Exception:  # TODO make this more specific
            if start_date != "":
                csv_search_context["errors"]["start_date"] = "Invalid Start Date"
            csv_search_context["start_date"] = ""
            csv_search_context["start_date_formatted"] = ""

        try:
            csv_search_context["end_date"] = end_date
            csv_search_context["end_date_formatted"] = datetime.strptime(
                end_date, "%Y-%m-%d"
            ).strftime("%Y%m%d")
        except Exception:  # TODO make this more specific
            if end_date != "":
                csv_search_context["errors"]["end_date"] = "Invalid End Date"
            csv_search_context["end_date"] = ""
            csv_search_context["end_date_formatted"] = ""

        files_to_search = os.path.normpath(settings.csv_docs_location)
        if lid:
            files_to_search = os.path.join(files_to_search, lid)

        csv_search_context["forecast_results"] = {}

        for root, dirs, file in os.walk(files_to_search):
            for f in file:
                if (
                    ".csv" in f
                    and (
                        csv_search_context["start_date"] == ""
                        or f >= csv_search_context["start_date_formatted"] + "0000"
                    )
                    and (
                        csv_search_context["end_date"] == ""
                        or f <= csv_search_context["end_date_formatted"] + "2359"
                    )
                ):
                    with open(os.path.join(root, f), "r") as csv_data:
                        file_contents = list(DictReader(csv_data))[0]
                    file_object = {
                        "name": os.path.join(root, f),
                        "contents": file_contents,
                    }
                    if (
                        os.path.basename(root)
                        not in csv_search_context["forecast_results"]
                    ):
                        csv_search_context["forecast_results"][
                            os.path.basename(root)
                        ] = {"files": [file_object], "forecasts": {}}
                    else:
                        csv_search_context["forecast_results"][os.path.basename(root)][
                            "files"
                        ].append(file_object)
                    for key, value in file_contents.items():
                        if key != "feature_id":
                            try:
                                file_date = datetime.strptime(key, "%Y%m%d%H%M")
                            except Exception:  # TODO make this more specific
                                file_date = None
                            if file_date:
                                file_date_string = file_date.strftime("%Y%m%d")

                                forecast_data = {
                                    "time": file_date,
                                    "feature_id": file_contents["feature_id"],
                                    "flow_value": file_contents[key],
                                }
                                if (
                                    file_date_string
                                    not in csv_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"]
                                ):
                                    csv_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][file_date_string] = [forecast_data]
                                else:
                                    csv_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][file_date_string].append(
                                        forecast_data
                                    )

        return csv_search_context
    
    @staticmethod
    async def search_lids(
        request: Request
    ):
        """
        Returns a dataset of all available LIDS.

        Parameters
        ----------
        request: Request
            A Request object passed in by the router.
        """

        plot_lids = [
            f.name
            for f in os.scandir(os.path.normpath(settings.plots_location))
            if f.is_dir()
        ]
        troute_lids = [
            f.name
            for f in os.scandir(os.path.normpath(settings.rnr_output_path))
            if f.is_dir()
        ]
        lid_search_context = {"lids": sorted(list(set(plot_lids) | set(troute_lids)))}

        return lid_search_context
    
    @staticmethod
    async def search_plot_data(
        request: Request, lid: str, start_date: str, end_date: str
    ):
        """
        Returns a dataset of all matching forecasts, including related plot and NetCDF files.

        Parameters
        ----------
        request: Request
            A Request object passed in by the router.
        lid : str
            The Location ID.
        start_date : str
            The earliest date to search on, formatted as YYYY-MM-DD.
        end_date : str
            The latest date to search on, formatted as YYYY-MM-DD.

        Returns
        -------
        Dict
            A dictionary containing the search results, with each LID as a key.
        """

        plot_search_context = {
            key: request.query_params[key] for key in request.query_params
        }

        plot_search_context["lid"] = lid
        
        plot_search_context["errors"] = {}

        plot_lids = [
            f.name
            for f in os.scandir(os.path.normpath(settings.plots_location))
            if f.is_dir()
        ]
        troute_lids = [
            f.name
            for f in os.scandir(os.path.normpath(settings.rnr_output_path))
            if f.is_dir()
        ]
        plot_search_context["lids"] = sorted(list(set(plot_lids) | set(troute_lids)))
        
        if lid == "" or lid not in plot_search_context["lids"]:
            plot_search_context["errors"]["lid"] = "Invalid LID"
            return plot_search_context

        try:
            plot_search_context["start_date"] = start_date
            plot_search_context["start_date_formatted"] = datetime.strptime(
                start_date, "%Y-%m-%d"
            ).strftime("%Y%m%d")
        except Exception:  # TODO make this more specific
            if start_date != "":
                plot_search_context["errors"]["start_date"] = "Invalid Start Date"
            plot_search_context["start_date"] = ""
            plot_search_context["start_date_formatted"] = ""

        try:
            plot_search_context["end_date"] = end_date
            plot_search_context["end_date_formatted"] = datetime.strptime(
                end_date, "%Y-%m-%d"
            ).strftime("%Y%m%d")
        except Exception:  # TODO make this more specific
            if end_date != "":
                plot_search_context["errors"]["end_date"] = "Invalid End Date"
            plot_search_context["end_date"] = ""
            plot_search_context["end_date_formatted"] = ""
        
        plot_search_context["forecast_results"] = {}

        plot_files_to_search = os.path.normpath(settings.plots_location)
        troute_files_to_search = os.path.normpath(settings.rnr_output_path)
        if lid:
            plot_files_to_search = os.path.join(plot_files_to_search, lid)
            troute_files_to_search = os.path.join(troute_files_to_search, lid)

        for root, dirs, file in os.walk(plot_files_to_search):
            for f in file:
                if ".png" in f:
                    start_date_formatted = ".".join(f.split(".")[:-1]).split("_")[-2]
                    end_date_formatted = ".".join(f.split(".")[:-1]).split("_")[-1]
                    if (
                        plot_search_context["start_date"] == ""
                        or start_date_formatted >= plot_search_context["start_date_formatted"]
                        or end_date_formatted >= plot_search_context["start_date_formatted"]
                    ) and (
                        plot_search_context["end_date"] == ""
                        or start_date_formatted <= plot_search_context["end_date_formatted"]
                        or end_date_formatted <= plot_search_context["end_date_formatted"]
                    ):
                        png_object = {
                            "name": os.path.join(root, f),
                            "start_date": datetime.strptime(start_date_formatted,"%Y%m%d"),
                            "end_date": datetime.strptime(end_date_formatted,"%Y%m%d")
                        }
                        if (
                            os.path.basename(root)
                            not in plot_search_context["forecast_results"]
                        ):
                            plot_search_context["forecast_results"][
                                os.path.basename(root)
                            ] = {"png_files": [png_object], "nc_files": [], "forecasts": {}}
                        else:
                            plot_search_context["forecast_results"][os.path.basename(root)][
                                "png_files"
                            ].append(png_object)
        
        for root, dirs, file in os.walk(troute_files_to_search):
            for f in file:
                if ".nc" in f:
                    file_date_formatted = f.split(".")[1].replace('t','').replace('z','')
                    if (
                        plot_search_context["start_date"] == ""
                        or file_date_formatted >= plot_search_context["start_date_formatted"] + "0000"
                    ) and (
                        plot_search_context["end_date"] == ""
                        or file_date_formatted <= plot_search_context["end_date_formatted"] + "2359"
                    ):
                        nc_object = {
                            "name": os.path.join(root, f),
                        }
                        if (
                            os.path.basename(root)
                            not in plot_search_context["forecast_results"]
                        ):
                            plot_search_context["forecast_results"][
                                os.path.basename(root)
                            ] = {"png_files": [], "nc_files": [nc_object], "forecasts": {}}
                        else:
                            plot_search_context["forecast_results"][os.path.basename(root)][
                                "nc_files"
                            ].append(nc_object)
                        ds = xr.open_dataset(os.path.join(root, f), engine="netcdf4").copy(deep=True)
                        
                        for idx, flow_value in enumerate(ds.flow.values):
                            if flow_value != 0:
                                feature_id = ds.feature_id.values[idx]
                                forecast_day = file_date_formatted[:4] + '-' + file_date_formatted[4:6] + '-' + file_date_formatted[6:8]
                                forecast_data = {
                                    'time': datetime.strptime(file_date_formatted, "%Y%m%d%H%M%S"),
                                    'flow_value': float(flow_value)
                                }

                                if (
                                    str(feature_id)
                                    not in plot_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"]
                                ):
                                    plot_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][str(feature_id)]= {forecast_day: [forecast_data]}
                                elif (
                                    forecast_day
                                    not in plot_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][str(feature_id)]
                                ):
                                    plot_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][str(feature_id)][forecast_day] = [forecast_data]
                                else:
                                    plot_search_context["forecast_results"][
                                        os.path.basename(root)
                                    ]["forecasts"][str(feature_id)][forecast_day].append(
                                        forecast_data
                                    )

        return plot_search_context