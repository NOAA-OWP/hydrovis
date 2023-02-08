"""
@author: shawn.crawley
@created: 2019-1-31
"""
import os
from platform import system as system_name
import subprocess as sp
import tempfile

from requests.compat import urlparse

from processing_pipeline.fetchers.data_fetcher import DataFetcher


class ScpFetcher(DataFetcher):
    """
    Class used to either fetch data or verify that data exists over SCP.
    """
    TIMEOUT1 = 'Server unexpectedly closed network connection'
    TIMEOUT2 = 'Network error: Software caused connection abort'
    NOTFOUND_MESSAGE = 'no such file or directory'
    NO_SECRET_KEY = ("A private_key (in the form of a password or the path to "
                     "a private ssh key) must be specified on the dataset.")
    NO_ACCESS_KEY = "An access_key (username) must be specified on the dataset."
    VERIFY_UNSUPPORTED_ON_UNIX = ("Verifying that data exists through SSH is "
                                  "not yet supported on unix machines.")

    def fetch_data(self, src, dest, timeout=None):
        """ Retrieve a file from an remote server using SCP
        Args:
            src(str): a URI in the format "host:/path/to/file"
            dest(str): the path to where the src file will be transferred
        """
        PSCP_DIR = os.environ.get('PSCP_DIR')
        if not PSCP_DIR:
            raise EnvironmentError("You must set the PSCP_DIR environment variable")  # pragma: no cover

        if not self.access_key:
            raise Exception(self.NO_ACCESS_KEY)

        if not self.secret_key:
            raise Exception(self.NO_SECRET_KEY)

        cwd = os.getcwd()
        os.chdir(PSCP_DIR)
        args = []

        if system_name().lower() == 'windows':
            args += ['pscp', '-batch']
        else:
            args += ['scp', '-B']

        args += ['-l', self.access_key]

        if os.path.isfile(self.secret_key):
            args += ['-i', self.secret_key]
        else:
            args += ['-pw', self.secret_key]

        args += [src, dest]

        try:
            sp.check_output(args, stderr=sp.STDOUT, timeout=timeout, encoding='utf8')
        except sp.CalledProcessError as err:
            if self.TIMEOUT1 in err.output or self.TIMEOUT2 in err.output:
                raise Exception(self.TIMEOUT_TEXT.format(src))
            if self.NOTFOUND_MESSAGE in err.output:
                raise Exception(self.NOT_FOUND_TEXT.format(src))
            raise Exception(err.output)
        finally:
            os.chdir(cwd)

    def verify_data(self, src, timeout=None):
        """ Verify that a file exists on a remote server using SCP
        Args:
            src(str): a URI in the format "host:/path/to/file"
        """
        if system_name().lower() != 'windows':
            raise NotImplementedError(self.VERIFY_UNSUPPORTED_ON_UNIX)
        if not self.access_key:
            raise Exception(self.NO_ACCESS_KEY)
        if not self.secret_key:
            raise Exception(self.NO_SECRET_KEY)

        uriparts = urlparse(src)
        directory = os.path.dirname(uriparts.path)
        fname = os.path.basename(uriparts.path)
        command = 'ls %s' % directory
        args = ['putty', '-ssh']

        # Add secret key args
        if os.path.isfile(self.secret_key):
            args += ['-i', self.secret_key]
        else:
            args += ['-pw', self.secret_key]

        # Create command file and add the flag and its path to args
        open_fileobj, command_path = tempfile.mkstemp()
        os.close(open_fileobj)
        with open(command_path, 'w') as command_file:
            command_file.write(command)
        args += ['-m', command_path]

        # Create temp directory for log path, and the flag and its path to args
        log_path = os.path.join(tempfile.mkdtemp(), 'putty.log')
        args += ['-sessionlog', log_path]

        # Add "username@host" to args
        args.append('{}@{}'.format(self.access_key, uriparts.scheme))

        try:
            sp.check_output(args, stderr=sp.STDOUT)
            with open(log_path, 'r') as log_file:
                for line in log_file.readlines():
                    if line.strip() == fname:
                        # Return if file was found
                        return

                # Only reaches this point if file was not found
                raise Exception(self.NOT_FOUND_TEXT.format(src))

        except sp.CalledProcessError as err:
            raise Exception(err.output)
        finally:
            os.remove(log_path)
            os.remove(command_path)
