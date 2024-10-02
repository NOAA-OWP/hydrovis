from typing import Optional

from sqlalchemy.orm import Session

from src.rnr.app.api.crud import get_rfc_entries, get_rfc_entry
from src.rnr.app.schemas import RFCDatabaseEntries, RFCDatabaseEntry


class RFCReaderService:
    """
    Service class for reading River Forecast Center (RFC) data from the database.

    This class provides static methods to interact with the database and retrieve
    RFC informational data. It encapsulates the logic for querying the database,
    processing the results, and creating RFCDatabaseEntry objects.

    Methods
    -------
    get_rfc_data(db_session: Session, identifier: Optional[str] = None) -> RFCDatabaseEntries
        Get RFC data from the database.
    """

    @staticmethod
    def get_rfc_data(
        db_session: Session, identifier: Optional[str] = None
    ) -> RFCDatabaseEntries:
        """A service helper function for getting RFC data from the database.

        Parameters
        ----------
        db_session : Session
            The database connection.
        identifier : str, optional
            The identifier to fetch a specific RFC entry.

        Returns
        -------
        RFCDatabaseEntries
            The schema for describing many RFCDatabaseEntry objects.
        """

        if identifier is not None:
            results = [get_rfc_entry(db_session, identifier)]
        else:
            results = get_rfc_entries(db_session)

        entries = [RFCDatabaseEntry.model_validate(_result) for _result in results]
        return RFCDatabaseEntries(entries=entries)
