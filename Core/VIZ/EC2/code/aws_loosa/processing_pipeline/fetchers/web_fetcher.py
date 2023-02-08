import datetime as dt
from dateutil import parser as date_parser, tz
import os
import requests
import time

from aws_loosa.processing_pipeline.fetchers.data_fetcher import DataFetcher

from requests.adapters import HTTPAdapter
import ssl


class SSLContextAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        context = ssl.create_default_context()
        kwargs['ssl_context'] = context
        context.load_default_certs()  # this loads the OS defaults on Windows
        return super(SSLContextAdapter, self).init_poolmanager(*args, **kwargs)


class WebFetcher(DataFetcher):
    CHUNK_SIZE = 25 * 1024 * 1024  # 25 MB
    CONTENT_LENGTH_HEADER = 'Content-Length'
    LAST_MODIFIED_HEADER = 'Last-Modified'
    SLEEP_BETWEEN_TRIES = 10
    TOKEN = ""

    def get_token(self):
        MAX_ATTEMPTS = 2
        error_obj = None

        if 'url' not in self.token_key:
            raise Exception('Please provide the "url" in the token dictionary')
        url = self.token_key['url']

        if 'data' not in self.token_key:
            raise Exception('Please provide the "data" in the token dictionary')

        if 'username' not in self.token_key['data']:
            raise Exception('Please provide the "username" in the token data dictionary')
        username = self.token_key['data']['username']

        if 'password' not in self.token_key['data']:
            raise Exception('Please provide the "password" in the token data dictionary')
        password = self.token_key['data']['password']

        expiration = self.token_key['data']['expiration'] if 'expiration' in self.token_key['data'] else "60"
        client = self.token_key['data']['client'] if 'client' in self.token_key['data'] else "requestip"
        referer = self.token_key['data']['referer'] if 'referer' in self.token_key['data'] else ""

        data = {
            'username': username,
            'password': password,
            'expiration': expiration,  #: Token timeout in minutes; defaults to 60.
            'client': client,
            'referer': referer,
            'f': 'json'
        }
        for attempt in range(MAX_ATTEMPTS):
            try:
                # Request the token
                session = requests.Session()
                adapter = SSLContextAdapter()
                session.mount(url, adapter)
                r = session.post(url, data=data)
                json_response = r.json()
                # Validate result
                if json_response is None or "token" not in json_response:
                    if json_response is None:
                        raise Exception("Failed to get token for unknown reason.")
                    else:
                        raise Exception("Failed to get token: {0}.".format(json_response['messages']))
                else:
                    return json_response['token']  # SUCCESS
            except Exception as e:
                error_obj = e
        # If reaches this point, max attempts were reached without succeeding
        raise Exception(
            'The following error occurred while attempting to get a token:\n{}'
            .format(str(error_obj))
        )

    def fetch_data(self, src, dest, timeout=None):
        """ Retrieve data from an web server
        Args:
            src(str): the uri to a specific web endpoint from where data should be fetched
            dest(str): the destination where the fetched data should be stored
        """
        if timeout is None:
            timeout = self.TIMEOUT

        response = None
        try:
            try:
                if self.token_key:
                    self.TOKEN = self.get_token()
                    src += f"&token={self.TOKEN}"
                session = requests.Session()
                adapter = SSLContextAdapter()
                session.mount(src, adapter)
                response = session.get(src, timeout=timeout, stream=True)
            except requests.exceptions.ConnectionError:
                try:
                    response = requests.get(src, timeout=timeout, verify=False)
                except requests.exceptions.ConnectionError:
                    raise Exception("Failed to establish a connection with {}.".format(src))
            except requests.exceptions.Timeout:
                raise Exception("Connection timed out to {}.".format(src))
            if response.status_code == 404:
                raise Exception("Data not found at {}.".format(src))
            elif response.status_code != 200:
                raise Exception(f'Web server response returned with a non-200 error code ({response.status_code})')

            self._log.debug('Headers for %s: %s', src, response.headers)

            if self.LAST_MODIFIED_HEADER in response.headers:
                last_modified = response.headers[self.LAST_MODIFIED_HEADER]
                if last_modified:
                    try:
                        last_modified_obj = date_parser.parse(last_modified)
                        utcnow = dt.datetime.utcnow().replace(tzinfo=tz.tz.tzutc())
                        time_since_modified = utcnow - last_modified_obj
                        if time_since_modified < dt.timedelta(seconds=10):
                            self._log.warning(
                                "The data at %s is likely being uploaded at the moment. Waiting %d seconds before "
                                "attempting to fetch again.",
                                src, self.SLEEP_BETWEEN_TRIES
                            )
                            time.sleep(self.SLEEP_BETWEEN_TRIES)
                            return self.fetch_data(src, dest)
                    except ValueError:
                        pass

            if self.CONTENT_LENGTH_HEADER in response.headers:
                src_size = int(response.headers[self.CONTENT_LENGTH_HEADER])
            else:
                src_size = 0

            # Write content to file
            start = time.time()
            with open(dest, 'wb') as download_file:
                for chunk in response.iter_content(chunk_size=self.CHUNK_SIZE):
                    if self._stop_event and self._stop_event.is_set():
                        return

                    if chunk:
                        download_file.write(chunk)

            self._log.debug("File fetched in %d seconds", time.time() - start)

            # Get size of the downloaded file
            dest_size = os.path.getsize(dest)
            successful = dest_size >= src_size

            if not successful:
                raise Exception('Data was lost in the process of fetching from {}: {} != {} bytes'.format(
                    src, src_size, dest_size
                ))
        finally:
            if response:
                response.close()

    def verify_data(self, src, timeout=None):
        """ Verify that data exists on a web server
        Args:
            src(str): the uri to data on a web server
        """
        if timeout is None:
            timeout = self.TIMEOUT

        response = None
        try:
            response = requests.head(src, timeout=timeout)
            if response.status_code == 404:
                raise Exception("Data not found at {}.".format(src))
            elif response.status_code != 200:
                raise Exception(f'Web server response returned with a non-200 error code ({response.status_code})')
        except requests.exceptions.ConnectionError:
            raise Exception("Failed to establish a connection with {}.".format(src))
        finally:
            if response:
                response.close()
