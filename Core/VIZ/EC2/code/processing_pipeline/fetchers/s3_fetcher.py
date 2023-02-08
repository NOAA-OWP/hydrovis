from requests.compat import urlparse, urlunparse
import boto3
import botocore


from processing_pipeline.fetchers.data_fetcher import DataFetcher


class S3Fetcher(DataFetcher):
    DEFAULT_TIMEOUT = 15
    CHUNK_SIZE = 25 * 1024 * 1024  # 25 MB
    CONTENT_LENGTH_HEADER = 'Content-Length'
    LAST_MODIFIED_HEADER = 'Last-Modified'

    def fetch_data(self, src, dest, timeout=None):
        """ Retrieve data from an web server
        Args:
            src(str): the uri to a specific web endpoint from where data should be fetched
            dest(str): the destination where the fetched data should be stored

            Example:
                fetcher = S3Fetcher()
                src = 's3-http://nwcal-rgw.nwc.nws.noaa.gov:8080/replace-and-route/nwc.20181210/medium_range/'
                      'wrf_hydro_t01.medium_range.channel_rt.f000.conus.nc'
                dest = '/path/to/transferred/object.nc'
                fetcher.fetch_data(src, dest)
        """
        if timeout is None:
            timeout = self.DEFAULT_TIMEOUT
        try:
            uriparts = urlparse(src)
            scheme = uriparts.scheme.replace('s3-', '')
            host = uriparts.netloc
            path = uriparts.path
            path_parts = path.split('/')
            bucket = path_parts[1]
            object_key = '/'.join(path_parts[2:])

            s3_endpoint = urlunparse((scheme, host, '', '', '', ''))

            res = boto3.resource(
                's3',
                endpoint_url=s3_endpoint,
                aws_access_key_id=self.access_key,
                aws_secret_access_key=self.secret_key
            )
            res.Bucket(bucket).download_file(object_key, dest)
        except botocore.exceptions.ClientError as exc:
            if exc.response['Error']['Code'] == '404':
                raise Exception("Data not found at {}.".format(src))
            else:
                raise  # pragma: no cover

    def verify_data(self, src, timeout=None):
        """ Verifies data exists in web server
        Args:
            src(str): the uri to a specific web endpoint from where data should be fetched

            Example:
                fetcher = S3Fetcher()
                src = 's3-http://nwcal-rgw.nwc.nws.noaa.gov:8080/replace-and-route/nwc.20181210/medium_range/'
                      'wrf_hydro_t01.medium_range.channel_rt.f000.conus.nc'
                fetcher.fetch_data(src, dest)
        """
        if timeout is None:
            timeout = self.DEFAULT_TIMEOUT
        try:
            uriparts = urlparse(src)
            scheme = uriparts.scheme.replace('s3-', '')
            host = uriparts.netloc
            path = uriparts.path
            path_parts = path.split('/')
            bucket = path_parts[1]
            object_key = '/'.join(path_parts[2:])

            s3_endpoint = urlunparse((scheme, host, '', '', '', ''))

            res = boto3.resource(
                's3',
                endpoint_url=s3_endpoint,
                aws_access_key_id=self.access_key,
                aws_secret_access_key=self.secret_key
            )
            res.Object(bucket, object_key).load()
        except botocore.exceptions.ClientError as exc:
            if exc.response['Error']['Code'] == '404':
                raise Exception("Data not found at {}.".format(src))
            else:
                raise  # pragma: no cover
