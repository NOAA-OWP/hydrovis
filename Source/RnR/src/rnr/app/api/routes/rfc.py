from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from src.rnr.app.api.client.hfsubset import async_subset, subset
from src.rnr.app.api.database import get_db
from src.rnr.app.api.services.rfc import RFCReaderService
from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings
from src.rnr.app.core.utils import AsyncRateLimiter
from src.rnr.app.schemas import RFCDatabaseEntries, Subset, SubsetLocations

router = APIRouter()


class Message(BaseModel):
    message: str = "Creating Hydrofabric Subsets in the background. Use /api/v1/rfc/build_rfc_hydrofabric_subset/{comid} to see if your LID has been processed"


@router.get("/", response_model=RFCDatabaseEntries)
async def read_rfc_domain_data(db: Session = Depends(get_db)) -> RFCDatabaseEntries:
    """Reads RFC domain data from the database

    Parameters
    ----------
    db: Session
        The database session from the localhost

    Returns
    -------
    RFCDatabaseEntries
        An object with many RFCDatabaseEntry points
    """
    return RFCReaderService.get_rfc_data(db)


@router.get("/{lid}", response_model=RFCDatabaseEntries)
async def read_single_rfc_domain_data(
    lid: str, db: Session = Depends(get_db)
) -> RFCDatabaseEntries:
    """Reads RFC domain data from the database

    Parameters
    ----------
    db: Session
        The database session from the localhost

    Returns
    -------
    RFCDatabaseEntries
        An object with many RFCDatabaseEntry points
    """
    return RFCReaderService.get_rfc_data(db, identifier=lid)


@router.post(
    "/build_rfc_hydrofabric_subset/{feature_id}", response_model=SubsetLocations
)
def build_single_rfc_location(
    feature_id: str, settings: Annotated[Settings, Depends(get_settings)]
) -> SubsetLocations:
    """Reads RFC domain data from the database

    Parameters
    ----------
    db: Session
        The database session from the localhost

    Returns
    -------
    RFCDatabaseEntries
        An object with many RFCDatabaseEntry points
    """
    response = subset(feature_id, settings.base_subset_url)
    subsets = [Subset(**response)]
    print(subsets)
    subset_locations = SubsetLocations(subset_locations=subsets)
    return subset_locations


@router.post("/build_rfc_hydrofabric_subsets/", response_model=Message)
async def build_rfc_locations(
    background_tasks: BackgroundTasks,
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> SubsetLocations:
    rfc_entries = RFCReaderService.get_rfc_data(
        db
    ).entries  # An RFCDatabaseEntries obj is always returned

    limiter = AsyncRateLimiter(
        rate_limit=15, time_period=1
    )  # Setting a Rate Limit for Async Requests at 15 stations per second

    async def limited_process(entry):
        async with limiter:
            if entry.feature_id is not None:
                return await async_subset(entry.feature_id, settings.base_subset_url)
            else:
                print(
                    f"{entry.nws_lid} does not have an attached feature ID. Cannot route"
                )

    [background_tasks.add_task(limited_process, rfc_entry) for rfc_entry in rfc_entries]
    return Message()
