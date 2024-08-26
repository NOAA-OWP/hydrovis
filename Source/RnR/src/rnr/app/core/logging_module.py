import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from src.rnr.app.core.cache import get_settings

settings = get_settings()

def setup_logger(name: str, log_file: str, level=logging.INFO):
    """Function to setup as many loggers as you want"""

    # Create logs directory if it doesn't exist
    log_dir = Path(settings.log_path)
    log_dir.mkdir(parents=True, exist_ok=True)

    formatter = logging.Formatter('%(asctime)s | %(name)s | %(levelname)s | %(message)s')

    # Create handlers
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)

    file_handler = RotatingFileHandler(log_dir / log_file, maxBytes=10*1024*1024, backupCount=5)
    file_handler.setFormatter(formatter)

    # Create logger and set level
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Add handlers to logger
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)

    return logger
