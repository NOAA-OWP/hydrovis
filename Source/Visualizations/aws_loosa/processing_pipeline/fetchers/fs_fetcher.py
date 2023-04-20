import shutil
import time
import os

from aws_loosa.processing_pipeline.fetchers.data_fetcher import DataFetcher


class FilesystemFetcher(DataFetcher):
    def fetch_data(self, src, dest, timeout=None):
        """ Transfer a file from one location on the local filesystem to another
        Args:
            src(str): the absolute path to a specific file on the local filesystem
            dest(str): the destination path to where the src file will be transferred
        """
        start = time.time()
        try:
            shutil.copyfile(src, dest)
            self._log.debug("Data fetched in %d seconds", time.time() - start)
        except IOError:
            raise Exception("Data not found.")  # pragma: no cover

    def verify_data(self, src, timeout=None):
        """ Verify that a path exists on the local filesystem
        Args:
            src(str): the absolute path to a specific file on the local filesystem
        """
        if not os.path.isfile(src):
            raise Exception("Data not found.")
