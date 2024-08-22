import os
from datetime import datetime
from zipfile import ZipFile

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.templating import Jinja2Templates

from .services import CSVSearchService

frontend_router = APIRouter()

templates = Jinja2Templates(
    directory=os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "templates")
    )
)


@frontend_router.get("/csv/", response_class=HTMLResponse)
async def get_csv_data(
    request: Request,
    lid: str = "",
    start_date: str = datetime.now().strftime("%Y-%m-%d"),
    end_date: str = "",
):
    """A route to display/search the CSV data

    Parameters
    ----------
    request: Request
        The Request object from the browser.
    lid : str
        The Location ID.
    start_date : str
        The earliest date to search on, formatted as YYYY-MM-DD.
    end_date : str
        The latest date to search on, formatted as YYYY-MM-DD.

    Returns
    -------
    HTMLResponse
        A dataset formatted as HTML
    """
    context = await CSVSearchService.search_csv_data(request, lid, start_date, end_date)

    return templates.TemplateResponse(
        request=request, name="csv_data.html", context=context
    )


@frontend_router.get("/csv/download/", response_class=FileResponse)
async def get_csv_data_download(
    request: Request,
    lid: str = "",
    start_date: str = datetime.now().strftime("%Y-%m-%d"),
    end_date: str = "",
):
    """A route to download a CSV data result set as a zip file

    Parameters
    ----------
    request: Request
        The Request object from the browser.
    lid : str
        The Location ID.
    start_date : str
        The earliest date to search on, formatted as YYYY-MM-DD.
    end_date : str
        The latest date to search on, formatted as YYYY-MM-DD.

    Returns
    -------
    FileResponse
        A zip file containing all CSV files from the user's search
    """

    context = await CSVSearchService.search_csv_data(request, lid, start_date, end_date)

    if lid:
        zip_file_name = (
            "RNR_Forecasts_"
            + lid
            + "_"
            + datetime.now().strftime("%Y%m%d%H%M%S")
            + ".zip"
        )
    else:
        zip_file_name = (
            "RNR_Forecasts_" + datetime.now().strftime("%Y%m%d%H%M%S") + ".zip"
        )

    with ZipFile(zip_file_name, "w") as zip_file:
        for key in context["forecast_results"]:
            for file_object in context["forecast_results"][key]["files"]:
                zip_file.write(
                    file_object["name"],
                    os.path.join(key, os.path.basename(file_object["name"])),
                )

    return FileResponse(path=zip_file_name, filename=zip_file_name)
