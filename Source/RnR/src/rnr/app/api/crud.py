from typing import List, Optional

from sqlalchemy.orm import Session

from src.rnr.app.models import RFCForecast


def get_rfc_entry(db: Session, identifier: str) -> Optional[RFCForecast]:
    """Using an ORM for getting a single RFC location

    Parameters
    ----------
    db: Session
    - The database session

    identifier: str
    - The nws lid identifier

    Returns
    -------
    Optional[RFCForecast]
    - The ORM object
    """
    return db.query(RFCForecast).filter(RFCForecast.nws_lid == identifier).first()


def get_rfc_entries(db: Session) -> List[RFCForecast]:
    """Using an ORM for getting a many RFC locations

    Parameters
    ----------
    db: Session
    - The database session

    Returns
    -------
    List[RFCForecast]
    - The List of many ORM objects
    """
    return db.query(RFCForecast).all()
