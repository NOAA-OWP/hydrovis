from typing import Generator

from fastapi import Depends
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from src.rnr.app.core.cache import get_settings
from src.rnr.app.core.settings import Settings

Base = declarative_base()


def get_db(
    settings: Settings = Depends(get_settings),
) -> Generator[Session, None, None]:
    """A function to get the DB connection using SQLAlchemy

    Parameters
    ----------
    settings: Settings
    - The BaseSettings config object

    Yields
    ------
    Session
    - The database session
    """
    engine = create_engine(settings.sqlalchemy_database_url)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
