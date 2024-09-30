import logging
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

from src.rise.app.core.cache import get_settings

settings = get_settings()


def setup_logger(name: str, log_file: str, level=logging.INFO):
    """
    Function to setup as many loggers as you want with date-based rotation

    Parameters
    ----------
    name : str
        Name of the logger
    log_file : str
        Name of the log file
    level : int, optional
        Logging level, by default logging.INFO

    Returns
    -------
    logging.Logger
        Configured logger instance

    Notes
    -----
    This function sets up a logger with both console and file handlers.
    The file handler rotates logs daily and keeps backups for 30 days.
    """

    log_dir = Path(settings.log_path)
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        file_dir = Path(__file__).resolve().parents[4]  # going to the root dir
        log_dir = Path(file_dir / "data/logs")
        log_dir.mkdir(parents=True, exist_ok=True)

    formatter = logging.Formatter(
        "%(asctime)s | %(name)s | %(levelname)s | %(message)s"
    )

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)

    file_handler = TimedRotatingFileHandler(
        log_dir / log_file,
        when="midnight",
        interval=1,
        backupCount=30,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    file_handler.suffix = "%Y-%m-%d"

    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)

    return logger
