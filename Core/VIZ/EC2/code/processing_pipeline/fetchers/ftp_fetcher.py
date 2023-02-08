import ftplib
import os
from requests.compat import urlparse
import time

from processing_pipeline.fetchers.data_fetcher import DataFetcher


class FtpFetcher(DataFetcher):
    def fetch_data(self, src, dest, timeout=None):
        """ Retrieve a file from an ftp server
        Args:
            src(str): the uri to a specific file on a FTP server
            dest(str): the destination path to where the src file will be transferred
        """
        uriparts = urlparse(src)
        host = uriparts.netloc
        path = uriparts.path

        ftp = None
        try:
            ftp = ftplib.FTP(host, timeout=(timeout or self.TIMEOUT))
            ftp.login(user=self.access_key, passwd=self.secret_key)
            fetch_cmd = 'RETR {0}'.format(path)
            start = time.time()
            with open(dest, 'wb') as dest_file:
                ftp.retrbinary(fetch_cmd, dest_file.write)

            self._log.debug("File fetched in %d seconds", time.time() - start)
        except ftplib.error_perm as exc:
            if '550' in str(exc):
                raise Exception("Data not found at {}".format(src))
        finally:
            if ftp:
                ftp.quit()

    def verify_data(self, src, timeout=None):
        """ Verify that a file exists on an FTP server
        Args:
            src(str): the absolute path to a specific file on the local filesystem
        """
        uriparts = urlparse(src)
        host = uriparts.netloc
        path = uriparts.path
        dpath, fname = os.path.split(path)

        if dpath == '/':
            dpath = ''

        ftp = None
        try:
            ftp = ftplib.FTP(host, timeout=(timeout or self.TIMEOUT))
            ftp.login(user=self.access_key, passwd=self.secret_key)
            files = ftp.nlst(dpath)
            if fname in files:
                return
            else:
                raise Exception("Data not found at {}".format(src))
        finally:
            if ftp:
                ftp.quit()
