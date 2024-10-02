from sqlalchemy import Boolean, Column, DateTime, Float, Integer, String
from sqlalchemy.orm import mapped_column

from src.rnr.app.api.database import Base


class RFCForecast(Base):
    """
    A SQLAlchemy model to describe the data contained within a single RFC
    (River Forecast Center) forecast entry.

    This class represents various attributes related to the forecast, location,
    and flood status.

    Attributes
    ----------
    nws_lid : str
        Primary key, National Weather Service Location Identifier.
    pe : str
        Physical element type.
    ts : str
        Time series type.
    issued_time : datetime
        Time the forecast was issued.
    generation_time : datetime
        Time the forecast was generated.
    forecast_trend : str
        Trend of the forecast.
    is_record_forecast : bool
        Whether this is a record forecast.
    initial_value_timestep : datetime
        Timestamp of the initial value.
    initial_value : float
        Initial forecast value.
    initial_status : str
        Initial status of the forecast.
    initial_flood_value_timestep : datetime
        Timestamp of the initial flood value.
    initial_flood_value : float
        Initial flood value.
    initial_flood_status : str
        Initial flood status.
    min_value_timestep : datetime
        Timestamp of the minimum value.
    min_value : float
        Minimum forecast value.
    min_status : str
        Status at minimum value.
    max_value_timestep : datetime
        Timestamp of the maximum value.
    max_value : float
        Maximum forecast value.
    max_status : str
        Status at maximum value.
    usgs_site_code : str
        USGS site code.
    feature_id : int
        Feature identifier.
    nws_name : str
        Name given by National Weather Service.
    usgs_name : str
        Name given by USGS.
    producer : str
        Producer of the forecast.
    issuer : str
        Issuer of the forecast.
    geom : str
        Geometry information.
    action_threshold : float
        Threshold for action level.
    minor_threshold : float
        Threshold for minor flooding.
    moderate_threshold : float
        Threshold for moderate flooding.
    major_threshold : float
        Threshold for major flooding.
    record_threshold : float
        Threshold for record flooding.
    units : str
        Units of measurement.
    hydrograph_link : str
        Link to the hydrograph.
    hefs_link : str
        Link to HEFS (Hydrologic Ensemble Forecast Service).
    update_time : datetime
        Time of last update.

    Notes
    -----
    This model is mapped to the 'rfc_max_forecast_copy' table in the 'rnr' schema.
    """

    __tablename__ = "rfc_max_forecast_copy"
    __table_args__ = {"schema": "rnr"}
    nws_lid = mapped_column(String, primary_key=True)
    pe = Column(String, nullable=False)
    ts = Column(String, nullable=False)
    issued_time = Column(DateTime, nullable=False)
    generation_time = Column(DateTime, nullable=False)
    forecast_trend = Column(String, nullable=False)
    is_record_forecast = Column(Boolean, nullable=False)
    initial_value_timestep = Column(DateTime, nullable=False)
    initial_value = Column(Float, nullable=False)
    initial_status = Column(String, nullable=False)
    initial_flood_value_timestep = Column(DateTime, nullable=False)
    initial_flood_value = Column(Float, nullable=False)
    initial_flood_status = Column(String, nullable=False)
    min_value_timestep = Column(DateTime, nullable=False)
    min_value = Column(Float, nullable=False)
    min_status = Column(String, nullable=False)
    max_value_timestep = Column(DateTime, nullable=False)
    max_value = Column(Float, nullable=False)
    max_status = Column(String, nullable=False)
    usgs_site_code = Column(String)
    feature_id = Column(Integer)
    nws_name = Column(String, nullable=False)
    usgs_name = Column(String)
    producer = Column(String, nullable=False)
    issuer = Column(String, nullable=False)
    geom = Column(String, nullable=False)
    action_threshold = Column(Float)
    minor_threshold = Column(Float)
    moderate_threshold = Column(Float)
    major_threshold = Column(Float)
    record_threshold = Column(Float)
    units = Column(String, nullable=False)
    hydrograph_link = Column(String, nullable=False)
    hefs_link = Column(String, nullable=False)
    update_time = Column(DateTime, nullable=False)
