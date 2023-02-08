# -*- coding: utf-8 -*-
"""
Created on Mar 28, 2017

@author: Nathan.Swain, Shawn.Crawley, Corey.Krewson
"""
from collections import namedtuple
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
import datetime as dt
import isodate
import ast
import _strptime  # Fixes issue with calling dt.datetime.strptime in thread # noqa

import filelock
from requests.compat import urlparse

from processing_pipeline import fetchers
from aws_loosa.processing_pipeline.logging import get_logger
from aws_loosa.processing_pipeline.utils import UTCNOW
from aws_loosa.processing_pipeline.utils.mixins import FileHandlerMixin
from aws_loosa.processing_pipeline.cli import consts


class DataSet(FileHandlerMixin):
    """
    Defines a dataset.

    The URI strings can contain tokens in the format of "{{token_key:token_value}}".

    Examples:

    dataset = DataSet(
        a_uris=['C:\\nwm.{{datetime:%Y%m%d}}\\short_range\\nwm.t{{datetime:%H}}z.short_range.channel_rt.{{range:1,16,2,%03d}}.conus.nc{{variable:zipext}}']
        variables={
            'zipext': '.zip'
        }
    )

    uris = dataset.get_uris(datetime.now())
    """
    BEGINNING_TOKEN_DELIMITER = '{{'
    ENDING_TOKEN_DELIMETER = '}}'
    TK_DATETIME = 'datetime'
    TK_RANGE = 'range'
    TK_VARIABLE = 'variable'
    TK_DATETIME_RANGE = 'datetime_range'
    VALID_TOKEN_KEYWORDS = (TK_DATETIME, TK_RANGE, TK_VARIABLE, TK_DATETIME_RANGE)
    TIME_GRANULARITY_MAP = {
        '%Y': dt.timedelta(days=361),
        '%m': dt.timedelta(days=28),
        '%d': dt.timedelta(days=1),
        '%H': dt.timedelta(hours=1),
        '%M': dt.timedelta(minutes=1),
        '%S': dt.timedelta(seconds=1)
    }
    LOCK_EXTENSION = 'lock'
    TEMP_EXTENSION = 'temp'
    S3 = 's3-http'
    HTTP = 'http'
    FTP = 'ftp'
    ALWAYS_TRANSFER = [FTP, HTTP]
    TRANSFER_ALL = 'all'
    TRANSFER_NONE = 'none'
    TRANSFER_REMOTE = 'remote'
    TRANSFER_OPTIONS = [TRANSFER_ALL, TRANSFER_NONE, TRANSFER_REMOTE, '<path to conditional check script>']
    INVALID_TRANSFER_OPTION_ERROR = 'The "transfer" attribute for datasets must be one of the following: {}'.format(
        ', '.join(TRANSFER_OPTIONS)
    )
    INVALID_RANGE_TOKEN_MESSAGE = (
        'Token "%s" is incorrectly formatted. '
        'Usage: {{range:[<range_min>,]<range_max>[,<range_step>][,<number_format>]}} '
        'where <range_min>, <range_max>, and <range_step> are all integers, '
        'and <number_format> is a string of the format "%%0<int>d" where <int> '
        'specifies the number of leading 0s to pad the range number with.'
    )
    INVALID_DATETIME_RANGE_TOKEN_MESSAGE = (
        'Token "%s" is incorrectly formatted. '
        'Usage: {{datetime_range:<range_min>,<range_max>,<range_step>[,<datetime_format>]}} '
        'where <range_min> and <range_max> are either "current|current(+|-)<iso_8601_duration>]" or a iso 8601 '
        'datetime, <range_step> is an iso 8601 duration and <datetime_format> is a python strptime directive '
        '(i.e. %%Y%%m%%d)'
    )
    MAX_PATH_CHARACTERS = 260
    MAX_PATH_BUFFER = 15

    def __init__(self, a_uris, a_failover_uris=None, a_name=None, a_base_dataset=None, a_repeat=None,
                 a_repeat_ref_time=None, a_window=None, a_window_step=None, a_variables=None, a_delay=None,
                 a_expiration=None, a_expect=None, a_fallback=None, a_transfer_data=None, a_transfers_dir=None,
                 a_transfer_format=None, a_clean_data=False, a_max_service_lag=None, a_start=None, a_end=None,
                 a_seed_times=None, a_credentials=None, a_log_directory=None, a_logstash_socket=None,
                 a_log_level='INFO', a_acceptable_uris_missing=None):
        """
        Constructor.

        Args:
            a_uris(str|list): a single string or a dict of main and failover strings representing the uri(s) of the
                data that make up the dataset
            a_name(str): a unique name for the dataset.
            a_base_dataset(DataSet): the DataSet instance that this instance is a subset of.
            a_repeat(datetime.timedelta): The frequency at which the dataset should be repeated
                (i.e. new data becomes available).
            a_repeat_ref_time(datetime.time): The time (HH:MM:SS) that defines the reference time from which the
                new_data_interval is calculated
            a_window(datetime.timedelta): The window representing the dataset, referenced backwards from now. The
                default is None, or just the current now time.
            a_window_step(datetime.timedelta): time interval to use when gathering the window of data. Optional,
                defaults to a_repeat.
            a_variables(dict): Dictionary where the keys are the variables to be used when expanding the DataSet and
                the values are lists of the values to be used in place of the variable
            a_delay(datetime.timedelta): The period of time, referenced to the current dataset's "official" time, after
                which any data is first expected to be available
            a_expiration(datetime.timedelta): The period of time, referenced to the current dataset's "official" time,
                after which data will be considered to be expired
            a_expect(datetime.timedelta): The period of time, referenced to the current dataset's "official" time,
                during which all data should be expected
            a_fallback(datetime.timedelta): If specified, this is the timestep used to fallback to a non-standard
                timestamped dataset in the case that the current timestamped dataset cannot be found.
            a_transfer_data(str): Indicates which data, if any, a watcher should transfer to a workable location on
                the host machine. Defaults to "all". Valid options are "all" (all data transferred), "none"
                (no data transferred), or "remote" (only non-local files should be transferred). In the latter case,
                ensure that the processing to occur on the dataset is read-only or that you do not mind if the files
                get modified in place.
            a_clean_data(str): Clean old data that has already been processed. Default to true
            a_transfers_dir(str): Absolute path to a directory in which transferred files should be stored. This
                directory and all of its parent directories will be created if any do not already exist.
            a_log_directory(str): Path to a directory where logs should be written.
            a_logstash_socket(str): Socket (e.g. <hostname>:<port>) of a logstash instance where logs should be sent.
            a_log_level(logging.LEVEL): Level at which to log. Either 'DEBUG', 'INFO', 'WARNING', 'ERROR', or
                'CRITICAL'.
            a_acceptable_uris_missing(str, int, or dict): Determines which uris are acceptable to be missing. If an
                int, determines the number of files that can be missing for the process to still get kicked off.
                If a dict, will determine specific files that are ok to be missing. If a str, represents a specific
                uri or a percentage of files.
        """
        if not a_name:
            import uuid
            a_name = str(uuid.uuid4())

        if not a_failover_uris:
            a_failover_uris = a_uris

        if isinstance(a_uris, str):
            a_uris = [a_uris]

        if isinstance(a_failover_uris, str):
            a_failover_uris = [a_failover_uris]

        self.name = a_name.lower().replace(' ', '')
        self._log = get_logger(self, a_log_directory, a_logstash_socket, a_log_level)
        self._log.debug('Initializing DataSet "%s"', self.name)

        # ############################### #
        # ADDITIONAL SETUP AND VALIDATION #
        # ############################### #
        if a_base_dataset:
            self.uris = a_uris if a_uris is not None else a_base_dataset.uris
            self.failover_uris = a_failover_uris if a_failover_uris is not None else a_base_dataset.failover_uris
            self.repeat = a_repeat if a_repeat is not None else a_base_dataset.repeat
            self.repeat_ref_time = a_repeat_ref_time if a_repeat_ref_time is not None else a_base_dataset.repeat_ref_time  # noqa
            self.delay = a_delay if a_delay is not None else a_base_dataset.delay
            self.fallback = a_fallback if a_fallback is not None else a_base_dataset.fallback
            self.expiration = a_expiration if a_expiration is not None else a_base_dataset.expiration
            self.expect = a_expect if a_expect is not None else a_base_dataset.expect
            self.window = a_window if a_window is not None else a_base_dataset.window
            self.variables = a_variables if a_variables is not None else a_base_dataset.variables
            self.window_step = a_window_step if a_window_step is not None else a_base_dataset.window_step
            self.transfer = a_transfer_data if a_transfer_data is not None else a_base_dataset.transfer
            self.clean = a_clean_data if a_clean_data is not None else a_base_dataset.clean
            self.transfers_dir = a_transfers_dir if a_transfers_dir is not None else a_base_dataset.transfers_dir
            self.max_service_lag = a_max_service_lag if a_max_service_lag is not None else a_base_dataset.max_service_lag  # noqa
            self.transfer_format = a_transfer_format if a_transfer_format is not None else a_base_dataset.transfer_format  # noqa
            self.max_service_lag = a_max_service_lag if a_max_service_lag is not None else a_base_dataset.max_service_lag  # noqa
            self.start = a_start if a_start is not None else a_base_dataset.start
            self.end = a_end if a_end is not None else a_base_dataset.end
            self.seed_times = a_seed_times if a_seed_times is not None else a_base_dataset.seed_times
            self.credentials = a_credentials if a_credentials is not None else a_base_dataset.credentials
            self.acceptable_uris_missing = a_acceptable_uris_missing if a_acceptable_uris_missing is not None else a_base_dataset.acceptable_uris_missing  # noqa
        else:
            self.uris = a_uris
            self.failover_uris = a_failover_uris
            self.repeat = a_repeat
            self.repeat_ref_time = a_repeat_ref_time
            self.delay = a_delay
            self.expiration = a_expiration
            self.expect = a_expect
            self.fallback = a_fallback
            self.window = a_window
            self.variables = a_variables
            self.window_step = a_window_step
            self.transfer = a_transfer_data
            self.clean = a_clean_data
            self.max_service_lag = a_max_service_lag
            self.transfers_dir = a_transfers_dir
            self.transfer_format = a_transfer_format
            self.start = a_start
            self.end = a_end
            self.seed_times = a_seed_times
            self.credentials = a_credentials
            self.acceptable_uris_missing = a_acceptable_uris_missing

        self._uri_metadata = self._process_uris(self.uris, self.variables)
        self._failover_uri_metadata = self._process_uris(self.failover_uris, self.variables)

        self._acceptable_primary_uris_missing_metadata = None
        self._acceptable_failover_uris_missing_metadata = None

        if isinstance(self.acceptable_uris_missing, dict) and self.acceptable_uris_missing:
            try:
                # Attempt to create list from repr object
                acceptable_missing_uris = ast.literal_eval(self.acceptable_uris_missing[consts.URI_PRIMARY])
            except ValueError:
                acceptable_missing_uris = self.acceptable_uris_missing[consts.URI_PRIMARY]
            self._acceptable_primary_uris_missing_metadata = self._process_uris(
                acceptable_missing_uris, self.variables
            )

        if self.transfer not in [None, self.TRANSFER_ALL, self.TRANSFER_NONE, self.TRANSFER_REMOTE]:
            if not os.path.exists(self.transfer):
                raise ValueError("The a_transfer_data argument must be one of the following: 'all', 'none', 'remote', "
                                 "or the path to a script for testing transfer condition.")
        elif not self.transfer:
            self.transfer = self.TRANSFER_ALL

        if self.start and self.end and self.start > self.end:
            raise ValueError("The end time is earlier than the start time.")

        if not self.transfers_dir:
            self.transfers_dir = tempfile.mkdtemp()
        else:
            if not os.path.exists(self.transfers_dir):
                os.makedirs(self.transfers_dir)

        # CONVERT NONE VALUES TO APPROPRIATE NONE-LIKE DATA VALUE #
        if self.delay is None:
            self.delay = dt.timedelta(hours=0)

        if self.repeat is None:
            self.repeat = dt.timedelta(hours=0)

        if self.expiration is None:
            self.expiration = self.repeat + self.delay

        if self.expect is None:
            self.expect = self.repeat + self.delay

        if self.window_step is None:
            self.window_step = self.repeat

        if self.fallback is None:
            self.fallback = dt.timedelta(0)

        if self.seed_times:
            # seed times come through as string so regex to get appropriate datetime object
            pattern = r"datetime.datetime\((.*), (.*), (.*), (.*), (.*)\)"
            datetime_seeds = []
            for seed_time in self.seed_times:
                match = re.findall(pattern, seed_time)
                year = int(match[0][0])
                month = int(match[0][1])
                day = int(match[0][2])
                hour = int(match[0][3])
                minute = int(match[0][4])
                datetime_seeds.append(dt.datetime(year, month, day, hour, minute))

            datetime_seeds.sort()
            self.start = datetime_seeds[0]
            self.end = datetime_seeds[-1]
            self.seed_times = datetime_seeds

        self.all_uris_static = all(self.TK_DATETIME not in uri for uri in self.uris)
        self.all_uris_time_varying = all(self.TK_DATETIME in uri for uri in self.uris)

        self.all_failover_uris_static = all(self.TK_DATETIME not in uri for uri in self.failover_uris)
        self.all_failover_uris_time_varying = all(self.TK_DATETIME in uri for uri in self.failover_uris)
        self.granular_time = self._get_granular_time()
        self._date_format = self._get_date_format(self.granular_time)

        if a_base_dataset:
            is_valid_subset = self.validate_is_subset_of(a_base_dataset)
            if not is_valid_subset:
                raise ValueError("{} is not a subset of {}".format(str(self.name), str(a_base_dataset.name)))

        if self.seed_times:
            self.valid_timesteps = None
        elif self.repeat:
            # Leave this here, as many above attributes must be set before performing this validation
            if self.repeat_ref_time is None:
                if self.start:
                    # Use the time of the provided start time, formatted with the dataset's date_format, as the
                    # repeat ref time
                    self.repeat_ref_time = self.round_datetime(self.start).time()
                else:
                    # Use the "NOW" time, formatted with the dataset's date_format, as the repeat ref time
                    self.repeat_ref_time = self.round_datetime(UTCNOW()).time()

            self.valid_timesteps = self.get_valid_timesteps(self.repeat_ref_time, self.repeat)
        else:
            self.valid_timesteps = None
            self.repeat_ref_time = self.round_datetime(UTCNOW()).time()

    # ############################ #
    # ######## PROPERTIES ######## #
    # ############################ #

    # ############################ #
    # ######## VALIDATORS ######## #
    # ############################ #

    @classmethod
    def _process_uris(cls, uris, variables=None):
        """
        Process the provided URIs

        "Process" refers to 1) validating the URIs and 2) organizing them and their metadata in a
        logical manner.

        Args:
            uris
        """
        metadata = namedtuple('URI_Metadata', 'tokens_by_uri, token_values_by_keyword')
        tokens_by_uri = {}
        token_values_by_keyword = {}
        for uri in uris:
            uri_tokens = cls._extract_tokens_from_string(string=uri)
            for token_key, token_vals in uri_tokens.items():
                if token_key not in token_values_by_keyword:
                    token_values_by_keyword[token_key] = set()

                if token_key == cls.TK_RANGE:
                    for token_val in token_vals:
                        cls._parse_range_token_value(token_val)
                        token_values_by_keyword[token_key].add(token_val)
                elif token_key == cls.TK_VARIABLE:
                    if not variables:
                        raise AttributeError('A URI of this dataset has the "variable" keyword, but no variables were '
                                             'provided to the dataset.')
                    else:
                        for token_val in token_vals:
                            if token_val not in variables:
                                raise AttributeError('A URI of this dataset has the "variable" token keyword, but the '
                                                     'specified variable was not provided to the dataset.')
                            token_values_by_keyword[token_key].add(token_val)
                elif token_key == cls.TK_DATETIME:
                    sorted_tokens_list = list()
                    for token_val in token_vals:
                        cls._parse_datetime_token_value(token_val)
                        if "reftime" in token_val:
                            sorted_tokens_list.insert(0, token_val)
                        else:
                            sorted_tokens_list.append(token_val)
                        token_values_by_keyword[token_key].add(token_val)

                    uri_tokens[token_key] = sorted_tokens_list
                elif token_key == cls.TK_DATETIME_RANGE:
                    for token_val in token_vals:
                        cls._parse_datetime_range_token_value(token_val)
                        token_values_by_keyword[token_key].add(token_val)

            tokens_by_uri[uri] = uri_tokens

        return metadata(tokens_by_uri, token_values_by_keyword)

    @staticmethod
    def parse_time(time_str):
        regex = re.compile(r'reftime.((?P<weeks>\d+?)W)?((?P<days>\d+?)D)?((?P<hours>\d+?)H)?((?P<minutes>\d+?)M)?'
                           r'((?P<seconds>\d+?)S)?')
        parts = regex.match(time_str)
        if not parts:
            raise Exception('Datetime logic incorrect. Use "reftime-XX" such as "reftime-3H"')
        parts = parts.groupdict()
        time_params = {}
        for (name, param) in parts.items():
            if param:
                time_params[name] = int(param)
        return dt.timedelta(**time_params)

    @classmethod
    def _parse_datetime_token_value(cls, token_val, datetime=None):
        if not datetime:
            datetime = dt.datetime.utcnow()

        try:
            if "reftime" in token_val:
                token_val_list = token_val.replace(" ", "").split(",")

                if len(token_val_list) != 2:
                    raise Exception("For datetime arithemtic, use <logic>, <datetime_format>. Such as reftime-3H,%H")

                datetime_logic = token_val_list[0]
                datetime_format = token_val_list[1]

                if "-" not in datetime_logic:
                    if "+" not in datetime_logic:
                        raise Exception("Must use '+' or '-' for datetime arithemtic Such as reftime-3H")

                token_val_diff_timedelta = cls.parse_time(datetime_logic)

                if "-" in datetime_logic:
                    new_datetime = datetime - token_val_diff_timedelta
                else:
                    new_datetime = datetime + token_val_diff_timedelta

                value = new_datetime.strftime(datetime_format)
                datetime = new_datetime
            else:
                value = datetime.strftime(token_val)

            return datetime, value

        except ValueError:
            raise ValueError('An invalid datetime format was found in the following token: {}. If using arithemtic, '
                             'only addition and subtraction allowed for arithmetic'.format(token_val))

    @classmethod
    def _get_granularity_from_timedelta(cls, timedelta):
        if timedelta < cls.TIME_GRANULARITY_MAP['%M']:
            granularity = cls.TIME_GRANULARITY_MAP['%S']
        elif timedelta < cls.TIME_GRANULARITY_MAP['%H']:
            granularity = cls.TIME_GRANULARITY_MAP['%M']
        elif timedelta < cls.TIME_GRANULARITY_MAP['%d']:
            granularity = cls.TIME_GRANULARITY_MAP['%H']
        elif timedelta < cls.TIME_GRANULARITY_MAP['%m']:
            granularity = cls.TIME_GRANULARITY_MAP['%d']
        elif timedelta < cls.TIME_GRANULARITY_MAP['%Y']:
            granularity = cls.TIME_GRANULARITY_MAP['%m']
        else:
            granularity = cls.TIME_GRANULARITY_MAP['%Y']

        return granularity

    @classmethod
    def _get_granularity_from_time(cls, time_obj):
        if time_obj.second != 0:
            granularity = cls.TIME_GRANULARITY_MAP['%S']
        elif time_obj.minute != 0:
            granularity = cls.TIME_GRANULARITY_MAP['%M']
        else:
            granularity = cls.TIME_GRANULARITY_MAP['%H']

        return granularity

    def _get_granular_time(self):
        """
        Gets the most granular time that is "relevant" to the provided list of URIs

        Some form of a variable, "real-time" datetime is often part of the data
        URI(s) of a dataset being monitored. This shows up in a data URI string
        as "{{datetime:<directives>}}" where <directives> is one or more Python
        strftime/strptime directives (i.e. "myfile-{{datetime:%Y%m%d}}.txt").
        In this case, it is important for the watcher/watch to "know" what the
        most granular time of the monitored dataset is and use it to rectify
        with the actual current time. In the above example, days is the most
        granular time. If there is no variable time component of the dataset,
        then this function defaults to using seconds as the most granular time.

        Returns:
            A datetime.timedelta object representing the most granular time of
            the dataset.
        """
        granular_time = dt.timedelta(days=1000)
        has_datetime = False
        for token_key, token_vals in self._uri_metadata.token_values_by_keyword.items():
            if token_key == self.TK_DATETIME:
                has_datetime = True
                for datetime_format in token_vals:
                    for format_piece, delta in list(self.TIME_GRANULARITY_MAP.items()):
                        if format_piece in datetime_format and delta < granular_time:
                            granular_time = delta

        if not has_datetime:
            if self.repeat_ref_time:
                granular_time = self._get_granularity_from_time(self.repeat_ref_time)
            elif self.start:
                granular_time = self._get_granularity_from_time(self.start)
            else:
                granular_time = self.TIME_GRANULARITY_MAP['%S']

        return granular_time

    def should_transfer_resource(self, uri, datetime):
        if self.transfer == self.TRANSFER_ALL:
            return True
        elif self.transfer == self.TRANSFER_REMOTE:
            if any(x in uri for x in self.ALWAYS_TRANSFER):
                return True
        elif os.path.exists(self.transfer):
            try:
                subprocess.run([sys.executable, self.transfer, uri, datetime.strftime('%Y%m%dT%H%M%S')], check=True)
                return True
            except subprocess.CalledProcessError:
                pass

        return False

    @classmethod
    def _get_date_format(cls, granular_time):
        date_format = ''
        inv_map = {v: k for k, v in list(cls.TIME_GRANULARITY_MAP.items())}
        for delta in sorted(list(inv_map.keys()), reverse=True):
            if granular_time <= delta:
                date_format += inv_map[delta]

        return date_format

    def validate_is_subset_of(self, parent_dataset):
        """
        Validates that this DataSet instance (self) is a subset of the provided parent_dataset

        Args:
            parent_dataset(DataSet): A DataSet instance that the current DataSet instance (self) is thought to be a
                subset of

        Returns:
            bool: True if is self is a subset of parent_dataset. False otherwise.
        """
        dummy_time = UTCNOW()
        containing_uris = parent_dataset.get_uris(dummy_time)
        subset_uris = self.get_uris(dummy_time)
        for uri in subset_uris:
            if uri not in containing_uris:
                return False

        return True

    @classmethod
    def _extract_tokens_from_string(cls, string):
        """
        Extract tokens from the provided token string.

        Tokens show up in the following format: {{TOKEN:VALUE}} where TOKEN

        Args:
            string(str): the string from which tokens will be extracted.

        Returns:
            dict: tokens dictionary with keywords as the keys, and a set containing one or more token expressions as
                the values.
        """
        tokens_dict = {}
        # Split by BEGINNING_TOKEN_DELIMETER
        split_string = string.split(cls.BEGINNING_TOKEN_DELIMITER)

        # Identify tokens
        for token in split_string:
            # Token portions will contain the ENDING_TOKEN_DELIMETER, non-token portions are ignored.
            if cls.ENDING_TOKEN_DELIMETER not in token:
                # Skip this token and move onto the next...
                continue

            # Strip of ENDING_TOKEN_DELIMTER and remaining string
            token = token.split(cls.ENDING_TOKEN_DELIMETER)[0]

            # Split out the keyword and value of the token e.g. 'keyword:value'
            keyword, value = token.split(':', 1)

            # Validate keyword
            if keyword not in cls.VALID_TOKEN_KEYWORDS:
                # Skip this token and move onto the next...
                raise ValueError('The following token is invalid: "{{%s}}". Expected format: '
                                 '"{{token_keyword:token_value}}" where token_keyword is one of the following: '
                                 '%s' % (token, ', '.join(cls.VALID_TOKEN_KEYWORDS)))

            # Add the keyword
            if keyword not in tokens_dict:
                tokens_dict[keyword] = set()
            tokens_dict[keyword].add(value)

        return tokens_dict

    @staticmethod
    def _replace_token_in_string(string, token_key, token_value, new_value):
        """
        Replace all instances of a token (i.e.: {{token_key:token_value}} ) in a string with new_value.

        Args:
            string(str): a string that presumably has tokens that are to be replaced.
            token_key(str): the keyword portion of the token that is to be replaced.
            token_value(str): the value portion of the token that is to be replaced.
            new_value(str): the value that is replace every instance of the defined token in the provided string.

        Returns:
            str: the resulting string.
        """
        full_token = '{{%s:%s}}' % (token_key, token_value)
        return string.replace(full_token, new_value)

    @classmethod
    def _parse_datetime_range_token_value(cls, token):
        parts = token.split(',')
        num_parts = len(parts)

        if num_parts in [3, 4]:
            try:
                raw_min = parts[0].strip()
                raw_max = parts[1].strip()
                raw_step = parts[2].strip()
                if any(x in raw_min for x in ['+P', '-P', '+ P', '- P', 'current', 'start']):
                    range_min = raw_min
                else:
                    range_min = isodate.parse_datetime(raw_min)
                if any(x in raw_max for x in ['+P', '-P', '+ P', '- P', 'current']):
                    range_max = raw_max
                else:
                    range_max = isodate.parse_datetime(raw_max)
                range_step = isodate.parse_duration(raw_step)
                format = '%Y%m%d%H%M%S'
                if num_parts == 4:
                    format = parts[3]
            except Exception:
                raise ValueError(cls.INVALID_DATETIME_RANGE_TOKEN_MESSAGE % token)
        else:
            raise ValueError(cls.INVALID_DATETIME_RANGE_TOKEN_MESSAGE % token)

        return (range_min, range_max, range_step, format)

    @classmethod
    def _parse_range_token_value(cls, token):
        range_min = 0
        range_step = 1
        number_format = '%01d'

        parts = token.split(',')
        num_parts = len(parts)

        if num_parts == 1:
            range_max = parts[0]
        elif num_parts == 2:
            range_min, range_max = parts
        elif num_parts == 3:
            range_min, range_max, range_step = parts
        elif num_parts == 4:
            range_min, range_max, range_step, number_format = parts
        else:
            raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)

        try:
            range_min = int(range_min)
            range_max = int(range_max)
            range_step = int(range_step)
        except ValueError:
            raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)

        if len(number_format) != 4:
            raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)
        else:
            if not number_format.startswith('%0'):
                raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)

            if not number_format.endswith('d'):
                raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)

            try:
                int(number_format[2])
            except ValueError:
                raise ValueError(cls.INVALID_RANGE_TOKEN_MESSAGE % token)

        return (range_min, range_max, range_step, number_format)

    def _replace_all_tokens_in_string(self, string, tokens, datetime=None):
        """
        Replace tokens in the provided strings with their intended values, creating the full, "expanded" set.

        Keywords:

        * datetime - replaced with the date and/or time that is passed to get_uris. Accepts any valid strftime
            compatible string as the token. Example: {{datetime:%Y%m%d}}
        * range - expands the string into multiple strings, replacing this token with each iteration of the expanded
            range. The token is made up of 4 comma separated (no spaces) arguments: min, max, interval, format string.
            Example: {{range:1,16,2,%03d}}
        * variable - replaces with the value of the variable passed into get_uris that matches the name of the token.
            Example: {{variable:my_var}}. If a list or tuple is passed in for the variable, the string is expanded to
            multiple strings.

        Args:
            string(list): a string to expand.
            tokens(dict): a dictionary of tokens in that string.
            datetime(dict, optional): a python datetime object to be used to evaluate datetimes

        Returns:
            list: expanded strings with tokens evaluated.
        """
        if not datetime:
            datetime = UTCNOW()
        # process non-expanding tokens first (datetime)
        expanded_strings = [string]  # Default to token string in case there are no tokens

        # datetime
        if self.TK_DATETIME in tokens:
            # expand repeat into list of datetime objects
            dates = [datetime]
            temp_date = datetime

            if self.window:
                start_date = datetime - self.window
                while temp_date > start_date:
                    temp_date = temp_date - self.window_step
                    dates.append(temp_date)

            temp_strings = []
            for date in dates:
                for expanded_string in expanded_strings:
                    temp_date_string = expanded_string
                    # Replace all date tokens in the string
                    for token in tokens[self.TK_DATETIME]:
                        # Evaluate datetime expression
                        parsed_date, value = self._parse_datetime_token_value(token, date)
                        temp_date_string = self._replace_token_in_string(
                            temp_date_string, self.TK_DATETIME, token, value
                        )

                    temp_strings.append(temp_date_string)

            # Overwrite expanded strings
            if temp_strings:
                expanded_strings = temp_strings

        # variable
        if self.TK_VARIABLE in tokens:
            temp_strings = []
            for expanded_string in expanded_strings:
                partially_expanded_strings = [expanded_string]
                for token in tokens[self.TK_VARIABLE]:
                    temp_variable_strings = []

                    for pevs in partially_expanded_strings:
                        # Insert variable
                        value = self.variables[token]
                        if isinstance(value, list) or isinstance(value, tuple):
                            for val in value:
                                temp_variable_strings.append(
                                    self._replace_token_in_string(pevs, self.TK_VARIABLE, token, str(val))
                                )
                        else:
                            value = str(value)
                            temp_variable_strings.append(
                                self._replace_token_in_string(pevs, self.TK_VARIABLE, token, value)
                            )
                            partially_expanded_strings = temp_variable_strings

                    if temp_variable_strings:
                        partially_expanded_strings = temp_variable_strings

                temp_strings += partially_expanded_strings

            # Overwrite expanded strings
            if temp_strings:
                expanded_strings = temp_strings

        # range
        if self.TK_RANGE in tokens:
            temp_strings = []
            for expanded_string in expanded_strings:
                partial_expanded_range_strings = [expanded_string]

                for token_value in tokens[self.TK_RANGE]:
                    temp_range_strings = []
                    for pers in partial_expanded_range_strings:
                        range_min, range_max, range_step, number_format = self._parse_range_token_value(token_value)

                        for i in range(range_min, range_max, range_step):
                            value = number_format % i
                            temp_range_strings.append(
                                self._replace_token_in_string(pers, self.TK_RANGE, token_value, value)
                            )

                    if len(temp_range_strings) > 1:
                        partial_expanded_range_strings = temp_range_strings

                temp_strings += partial_expanded_range_strings

            # Overwrite expanded strings
            if temp_strings:
                expanded_strings = temp_strings

        if self.TK_DATETIME_RANGE in tokens:
            temp_strings = []
            for expanded_string in expanded_strings:
                partial_expanded_range_strings = [expanded_string]

                for token_value in tokens[self.TK_DATETIME_RANGE]:
                    temp_range_strings = []
                    for pers in partial_expanded_range_strings:
                        range_min, range_max, range_step, format = self._parse_datetime_range_token_value(token_value)
                        if isinstance(range_min, str):
                            if range_min == 'current':
                                range_min = datetime
                            elif '-' in range_min:
                                range_min = datetime - isodate.parse_duration(range_min.split('-')[1])
                            elif '+' in range_min:
                                range_min = datetime + isodate.parse_duration(range_min.split('+')[1])
                        if isinstance(range_max, str):
                            if range_max == 'current':
                                range_max = datetime
                            elif '-' in range_max:
                                range_max = datetime - isodate.parse_duration(range_max.split('-')[1])
                            elif '+' in range_max:
                                range_max = datetime + isodate.parse_duration(range_max.split('+')[1])

                        iter_date = range_min
                        while iter_date <= range_max:
                            value = iter_date.strftime(format)
                            temp_range_strings.append(
                                self._replace_token_in_string(pers, self.TK_DATETIME_RANGE, token_value, value)
                            )
                            iter_date += range_step

                    if temp_range_strings:
                        partial_expanded_range_strings = temp_range_strings

                temp_strings += partial_expanded_range_strings

            # Overwrite expanded strings
            if temp_strings:
                expanded_strings = temp_strings

        return expanded_strings

    def get_time_horizon(self, datetime):
        """
        Returns the earliest datetime considered for computing the dataset cooresponding with the given datetime.

        Args:
            datetime(datetime): a datetime object that will be used to derive the dataset.

        Returns:
            datetime: the earliest
        """

        if self.window:
            horizon = None
            delta = 0
            window_step = abs(self.window_step)
            window = abs(self.window)

            # repeat (and therfore window_step) are set to 0 for default so return window difference
            if not window_step:
                return datetime - self.window

            # Loop through and get multiples of window_step until greater than the window
            while not horizon:
                delta += 1
                step = window_step * delta
                if step >= window:
                    horizon = step

            datetime = datetime - horizon
            return datetime

        return datetime

    def get_uris(self, datetime=None):
        """
        Evaluates and expands the URIs for one realization of the dataset, given a datetime and variable values.

        Args:
            datetime(datetime): a datetime object that will be used to derive the dataset.
        Returns:
            list: expanded URIs list
        """
        all_uris = set()

        # Evaluate and expand uris
        for uri, tokens in self._uri_metadata.tokens_by_uri.items():
            all_uris.update(self._replace_all_tokens_in_string(uri, tokens, datetime))

        self._log.debug('All Filenames: %s', all_uris)
        return sorted(all_uris)

    def get_failover_uris(self, datetime=None):
        """
        Evaluates and expands the URIs for one realization of the dataset, given a datetime and variable values.

        Args:
            datetime(datetime): a datetime object that will be used to derive the dataset.
        Returns:
            list: expanded URIs list
        """
        all_uris = []

        # Evaluate and expand uris
        for uri, tokens in self._failover_uri_metadata.tokens_by_uri.items():
            all_uris += self._replace_all_tokens_in_string(uri, tokens, datetime)

        self._log.debug('All Filenames: %s', all_uris)
        return sorted(all_uris)

    def get_acceptable_missing_uris(self, datetime=None):
        """
        Evaluates and expands the URIs for one realization of the dataset, given a datetime and variable values.

        Args:
            datetime(datetime): a datetime object that will be used to derive the dataset.
        Returns:
            list: expanded URIs list
        """
        all_uris = []

        # Evaluate and expand uris
        if self._acceptable_primary_uris_missing_metadata:
            for uri, tokens in self._acceptable_primary_uris_missing_metadata.tokens_by_uri.items():
                all_uris += self._replace_all_tokens_in_string(uri, tokens, datetime)

        self._log.debug('All Filenames: %s', all_uris)
        return sorted(all_uris)

    def get_valid_timesteps(self, first_known_timestep, new_data_interval):
        valid_timesteps = set([first_known_timestep])
        iter_datetime = dt.datetime.combine(UTCNOW().date(), first_known_timestep)

        iter_datetime += new_data_interval
        while iter_datetime.time() != first_known_timestep:
            valid_timesteps.add(iter_datetime.time())
            iter_datetime += new_data_interval

        return valid_timesteps

    def round_datetime(self, datetime):
        formatted_datetime_string = datetime.strftime(self._date_format)
        formatted_combined_datetime = dt.datetime.strptime(formatted_datetime_string, self._date_format)

        return formatted_combined_datetime

    def get_first_valid_datetime(self):
        '''
        Gets the first valid datetime based on dataset's properties, where first implies future reference to the
        start_datetime
        '''
        all_uris_static = self.all_uris_static

        if self.start:
            start_datetime = self.start
            delay = dt.timedelta(0)
            compare_time = self.start
        else:
            now = UTCNOW()
            start_datetime = self.round_datetime(now)
            delay = self.delay
            if abs(start_datetime - now) <= dt.timedelta(minutes=1):
                compare_time = start_datetime
            else:
                compare_time = now

        raw_combined_datetime = dt.datetime.combine(start_datetime, self.repeat_ref_time)
        first_valid_datetime = self.round_datetime(raw_combined_datetime)

        if first_valid_datetime + delay < compare_time:
            while first_valid_datetime + delay < compare_time:
                first_valid_datetime += self.repeat
        elif first_valid_datetime + delay > compare_time:
            while first_valid_datetime + delay - self.repeat >= compare_time:
                first_valid_datetime -= self.repeat
        else:
            first_valid_datetime = start_datetime

        # In the case of no start time provided and time-varying uris, we don't want the first_valid_datetime
        # to be just ahead of the "start" datetime (UTCNOW), but we want the
        # first_valid_datetime to actually be a time that puts UTCNOW inside of
        # the fetch window (between delay and expiration)
        if not self.start and not all_uris_static:
            first_valid_datetime -= self.repeat

        return first_valid_datetime

    def _extract_and_validate_data_info(self, fetch_queue_item):
        uri = fetch_queue_item.get('uri', None)
        date = fetch_queue_item.get('date', None)
        timeout = fetch_queue_item.get('timeout', None)

        if None in [uri, date, timeout]:
            error_msg = ('A uri, date, and timeout must all be provided to fetch_queue item.')
            raise Exception(error_msg)

        return uri, date, timeout

    def _get_unique_transfer_destination_dirs(self, datetime=None):

        unique_destination_dirs = set()
        for uri in self.get_uris(datetime):
            unique_destination_dirs.add(os.path.dirname(self.get_transfer_destination_path(uri, datetime)))
        for uri in self.get_failover_uris(datetime):
            unique_destination_dirs.add(os.path.dirname(self.get_transfer_destination_path(uri, datetime)))
        return unique_destination_dirs

    def get_single_transfer_path(self, resource, datetime=None):

        if self.should_transfer_resource(resource, datetime):
            return self.get_transfer_destination_path(resource, datetime)
        else:
            uri_parts = urlparse(resource)
            scheme = uri_parts.scheme
            if len(scheme) in [0, 1]:
                return resource

        return None

    def get_all_transfer_paths(self, resource_list, datetime=None):
        all_transfer_paths = []

        for uri in resource_list:
            transfer_path = self.get_single_transfer_path(uri, datetime)
            if transfer_path:
                all_transfer_paths.append(transfer_path)

        return all_transfer_paths

    def uri_actually_static(self, uri, datetime):
        """Checks if a uri is actually static

        Returns:
            True if actually static, False otherwise.
        """
        for raw_uri in self.uris:
            tokens = self._uri_metadata.tokens_by_uri[raw_uri]
            expaneded_uris = self._replace_all_tokens_in_string(raw_uri, tokens, datetime)
            if uri in expaneded_uris:
                return self.TK_DATETIME not in raw_uri

        # If the uri cannot be found in the expanded raw_uris, assume its static
        return True

    def get_transfer_destination_path(self, uri=None, datetime=None):
        """
        Derive the directory or filename path within the transfers_dir of the given source uri.

        Args:
            uri(str): the uri of a specific resource of the dataset
            datetime(datetime.datetime): If included, the destination path will include a timestamped directory
                component.

        Returns:
            str: path within transfers_dir.
        """
        if datetime and uri and self.transfer_format:
            transfer_name = self.transfer_format
            if isinstance(self.transfer_format, dict):
                find = self.transfer_format['find']
                replace = self.transfer_format['replace']
                transfer_name = replace
                matches = re.search(find, uri)
                if matches:
                    replacement_parts = matches.groups()
                    replacement_indicies = set([int(x[1]) for x in re.findall(r'\$\d', replace)])
                    for index in replacement_indicies:
                        try:
                            transfer_name = transfer_name.replace(f'${index}', replacement_parts[index-1])
                        except IndexError:
                            pass

            transfer_name = datetime.strftime(transfer_name)
            transfer_destination_path = os.path.join(self.transfers_dir, transfer_name)
            return transfer_destination_path

        all_uris_time_varying = self.all_uris_time_varying or self.all_failover_uris_time_varying
        all_uris_static = self.all_uris_static or self.all_failover_uris_static

        if not uri:
            dpath = '/'
            fname = ''
            host = ''
        else:
            uri_parts = urlparse(uri)
            host = uri_parts.netloc.replace(':', '-')
            dpath, fname = os.path.split(uri_parts.path)
            fname += uri_parts.query

        if dpath.startswith('/') or dpath.startswith('\\'):
            dpath = dpath[1:]

        if '/' in dpath and platform.system() == 'Windows':
            dpath = dpath.replace('/', '\\')

        dname = re.sub(r'(\\|/)+', '-', dpath)
        dname = dname[1:] if dname.startswith('-') else dname

        # Recombine folder parts with the transfers_dir as the root
        transfer_destination_path = os.path.join(self.transfers_dir, host, dname, fname)
        if not all_uris_time_varying:
            # Handle prepend datetime in the path if specified
            if datetime:
                if all_uris_static or self.uri_actually_static(uri, datetime):
                    if self.repeat:
                        date_format = self._get_date_format(self._get_granularity_from_timedelta(self.repeat))
                    else:
                        date_format = self._date_format
                    datetime_str = datetime.strftime(date_format)
                    transfer_destination_path = os.path.join(self.transfers_dir, host, dname, datetime_str, fname)

        # Take care of invalid characters
        transfer_destination_path = transfer_destination_path. \
            replace('?', '').replace('=', '-'). \
            replace('&', '-').replace(';', '-'). \
            replace(',', '-')

        self._log.debug('Workspace Path: %s', transfer_destination_path)

        # truncate transfer_destination_path if too long
        effective_max_length = self.MAX_PATH_CHARACTERS-self.MAX_PATH_BUFFER
        if len(transfer_destination_path) > effective_max_length:
            truncated_path = transfer_destination_path[:effective_max_length]
            self._log.debug(
                'Truncating transfer_destination_path from %s to %s.', transfer_destination_path, truncated_path
            )
            transfer_destination_path = truncated_path

        return transfer_destination_path

    def write_transfer_paths_to_file(self, resource_list, datetime=None):
        """
        Write the list of transfer paths for this dataset to a temporary file
        """
        transfer_paths = self.get_all_transfer_paths(resource_list, datetime)
        transfer_paths_sorted = sorted(transfer_paths)
        transfer_paths_json = json.dumps(transfer_paths_sorted)

        with tempfile.NamedTemporaryFile(delete=False, mode='w') as temp:
            temp.write(transfer_paths_json)
            fpath = temp.name

        self._log.debug('List of transfer paths written to temporary file at "%s"', fpath)
        return fpath

    def clean_temp_files(self, datetime=None):
        """
        Clean temp and lock files from transfer_dirs per supplied datetime
        """
        if not datetime:
            datetime = UTCNOW()

        transfer_dirs = self._get_unique_transfer_destination_dirs(datetime)
        cleanup_extensions = [self.TEMP_EXTENSION, self.LOCK_EXTENSION]
        for transfers_dir in transfer_dirs:
            self._log.debug("Cleaning up temporary files in transfers_dir %s", transfers_dir)
            for dirpath, dirnames, filenames in os.walk(transfers_dir):
                for filename in filenames:
                    if any(filename.endswith(extension) for extension in cleanup_extensions):
                        full_path = os.path.join(dirpath, filename)
                        self._log.debug('Cleaning up temporary file "%s"', full_path)
                        try:
                            self._remove(full_path, retries=0)
                        except Exception:
                            self._log.warning('Unable to remove "%s" while cleaning temporary files.', full_path)

    def get_fetcher_class(self, uri):
        uri_parts = urlparse(uri)
        scheme = uri_parts.scheme
        if self.S3 in scheme:
            self._log.debug('Initiating a S3Fetcher.')
            fetcher_class = fetchers.S3Fetcher
        elif self.HTTP in scheme:
            self._log.debug('Initiating a WebFetcher.')
            fetcher_class = fetchers.WebFetcher
        elif self.FTP in scheme:
            self._log.debug('Initiating a FtpFetcher.')
            fetcher_class = fetchers.FtpFetcher
        elif len(scheme) in [0, 1]:
            self._log.debug('Initiating a FilesystemFetcher.')
            fetcher_class = fetchers.FilesystemFetcher
        else:
            self._log.debug('Initiating a ScpFetcher.')
            fetcher_class = fetchers.ScpFetcher

        return fetcher_class

    def fetch_data(self, fetch_queue, results_queue, stop_event):
        """
        Retrieve data in the dataset per a specific URI. Must be thread safe.

        Args:
            fetch_queue(Queue.Queue): a Queue where each item is a dictionary with info about what is to be fetched.
            results_queue(Queue.Queue): a Queue for the results of the fetch attempt.
            stop_event(threading.Event): Used to force stop the fetch for data when being run in a separate thread.
        """
        download_lock = None
        data_info = {}
        temp_destination = None
        destination = None
        lockfile_path = None
        try:
            if stop_event and stop_event.is_set():
                raise Exception("Fetch was forced to stop.")

            data_info = fetch_queue.get(timeout=1)
            (uri, date, timeout) = self._extract_and_validate_data_info(data_info)

            if not self.should_transfer_resource(uri, date):
                fetcher_class = self.get_fetcher_class(uri)
                fetcher = fetcher_class(logger=self._log, stop_event=stop_event, credentials=self.credentials)
                self._log.debug('Attempting to locate %s', uri)
                fetcher.verify_data(uri, timeout)
            else:
                destination = self.get_transfer_destination_path(uri=uri, datetime=date)
                overwrite = False
                if self.repeat and (self.all_uris_static or self.uri_actually_static(uri, date)):
                    next_iteration_destination = self.get_transfer_destination_path(uri=uri, datetime=(date + self.repeat))
                    if next_iteration_destination == destination:
                        overwrite = True

                download_directory = os.path.dirname(destination)
                self._makedirs(download_directory)

                # Acquire lockfile
                lockfile_path = '{}.{}'.format(destination, self.LOCK_EXTENSION)
                download_lock = filelock.FileLock(lockfile_path)
                download_lock.acquire(timeout=10)
                # Execution will only continue on from here if the lockfile is acquired

                if stop_event and stop_event.is_set():
                    raise Exception("Fetch was forced to stop.")

                if os.path.isfile(destination) and not overwrite:
                    # This means another Watcher/Watch successfully fetched the data
                    self._log.info('Data at %s already fetched to destination %s. Skipping...', uri, destination)
                    data_info['success'] = True
                    data_info['destination'] = destination
                    return

                temp_destination = '{}.{}'.format(destination, self.TEMP_EXTENSION)

                if os.path.isfile(temp_destination):
                    self._log.info('Another Watcher/Watch must have attempted the download and failed. Removing temp '
                                   'destination at %s...', temp_destination)
                    self._remove(temp_destination)

                fetcher_class = self.get_fetcher_class(uri)
                fetcher = fetcher_class(logger=self._log, stop_event=stop_event, credentials=self.credentials)

                self._log.info('Attempting to fetch %s', uri)
                fetcher.fetch_data(uri, temp_destination, timeout)
                if stop_event and stop_event.is_set():
                    raise Exception("Fetch was forced to stop.")
                self._rename(temp_destination, destination, force=overwrite)

            if stop_event and stop_event.is_set():
                raise Exception("Fetch was forced to stop.")

            self._log.info('Fetch successful.')
            data_info['success'] = True
            data_info['destination'] = destination

        except filelock.Timeout as exc:
            if os.path.exists(uri):
                data_info['success'] = True
                data_info['destination'] = destination
            else:
                data_info['success'] = False
                self._log.info(str(exc))
                data_info['message'] = str(exc)

        except Exception as exc:
            if data_info:
                data_info['success'] = False
                self._log.info(str(exc))
                data_info['message'] = str(exc)

            if destination and os.path.exists(destination):
                try:
                    self._remove(destination)
                    self._log.warning(f"File at {destination} was removed due to the following error encountered "
                                      "while fetching: {str(exc)}")
                except Exception:
                    self._log.warning('Unable to remove download file: %s', destination)
        finally:
            if temp_destination and os.path.exists(temp_destination):
                try:
                    self._remove(temp_destination)
                except Exception:
                    self._log.warning('Unable to remove temporary download file: %s', temp_destination)

            if download_lock:
                download_lock.release()
                try:
                    self._remove(lockfile_path)
                except Exception:
                    self._log.warning('Unable to remove lockfile: %s', lockfile_path)

            if data_info:
                results_queue.put(data_info)
                fetch_queue.task_done()
