import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from src.rnr.app.core.cache import get_settings

settings = get_settings()

def setup_logger(name: str, log_file: str, level=logging.INFO):
    """Function to setup as many loggers as you want"""
    
    # Get logger - if it exists already, return it
    logger = logging.getLogger(name)
    
    # If this logger already has handlers, return it as is
    if logger.hasHandlers():
        return logger

    # Create logs directory if it doesn't exist
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

    # Create handlers
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)

    file_handler = RotatingFileHandler(
        log_dir / log_file, maxBytes=10 * 1024 * 1024, backupCount=5
    )
    file_handler.setFormatter(formatter)

    # Set level
    logger.setLevel(level)

    # Add handlers to logger
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)

    return logger
