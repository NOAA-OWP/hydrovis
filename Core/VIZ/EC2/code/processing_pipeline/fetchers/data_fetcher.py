from abc import abstractmethod
from processing_pipeline.utils.mixins import FileHandlerMixin
from processing_pipeline.logging import get_logger


class DataFetcher(FileHandlerMixin):
    TIMEOUT = 60
    ACCESS_KEY = 'access_key'
    SECRET_KEY = 'secret_key'
    TOKEN_KEY = 'token'
    TIMEOUT_TEXT = 'Connection timed out while fetching {}'
    NOT_FOUND_TEXT = 'Data not found at {}'

    def __init__(self, logger=None, stop_event=None, credentials=None):
        """ Initialize the DataFetcher instance
        Args:
            logger(logging.Logger): An instance of class logging.Logger that will be used to log messages
            stop_event(threading.Event): Used to force stop the data fetching when being run in a separate thread.
        """
        if logger:
            self._log = logger
        else:
            self._log = get_logger(self)

        self._stop_event = stop_event

        self.access_key = None
        self.secret_key = None
        self.token_key = None
        if credentials:
            if self.ACCESS_KEY in credentials:
                self.access_key = credentials[self.ACCESS_KEY]
            if self.SECRET_KEY in credentials:
                self.secret_key = credentials[self.SECRET_KEY]
            if self.TOKEN_KEY in credentials:
                self.token_key = credentials[self.TOKEN_KEY]

    @abstractmethod
    def fetch_data(self, src, dest, timeout=None):
        pass  # pragma: no cover

    @abstractmethod
    def verify_data(self, src, timeout=None):
        pass  # pragma: no cover
