import os
from csv import DictReader
from datetime import datetime

from fastapi import Request

from src.rnr.frontend.core import get_settings

settings = get_settings()


class CSVSearchService:
    """
    Service class for handling search of the CSV files.

    Methods
    -------
    search_csv_data()
        Takes input parameters and returns a dataset of all matching forecasts.
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
                                    "measurement": file_contents[key],
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
