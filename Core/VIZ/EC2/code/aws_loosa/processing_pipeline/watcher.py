# -*- coding: utf-8 -*-
"""
Created on Tue Apr 5 10:12:00 2017

@author: Nathan.Swain, Shawn.Crawley
"""
import datetime as dt
import os
from queue import Empty
import time
from threading import Thread
import glob
import subprocess
import sys
from smtplib import SMTP

from aws_loosa.processing_pipeline.launcher import Launcher
from aws_loosa.processing_pipeline.logging import get_logger, INFO
from aws_loosa.processing_pipeline.signal import Signal
from aws_loosa.processing_pipeline.utils import UTCNOW, monitoring_consts as mon_consts
from aws_loosa.processing_pipeline.watch import Watch


class StopEventTriggered(Exception):
    pass


class Watcher():
    """
    Watches a DataSet for updates, downloads the files when available, and launches processing associated with the
    DataSet or it subset DataSets. Abstract Base Class.
    """
    CACHE_ALL = dt.timedelta(9999)
    END_AT_LATEST = dt.datetime(9999, 9, 9)
    DEFAULT_PING_INTERVAL = dt.timedelta(seconds=180)
    INITIAL_TIMEOUT = 2
    TIMEOUT_INCREMENT = 2
    TIMEOUT_THRESHOLD = 60  # maximum number of seconds to wait on fetch before assumed unavailable
    FAIL_THRESHOLD = 5  # number of failed fetch attempts before assumed unavailable
    DEFAULT_MAX_CONCURRENT_TRANSFERS = 5
    MAX_UNINTERRUPTED_SLEEP = 3
    HEARTBEAT_COUNTER = 20  # MAX_UNINTERRUPTED_SLEEP * HEARTBEAT_COUNTER = HEARTBEAT_INTERVAL
    CLEAN_BUFFER = 24  # Buffer number of concurrent dates with no data to check before stopping.
    SKIP_ERROR_MSG = "The skip argument must be a list of datetime.time objects or the path to a python file."

    def _has_connected_processes(self, dataset):
        truth = False
        if dataset in self._dataset_to_launchers_map:
            truth = len(self._dataset_to_launchers_map[dataset]) > 0

        return truth

    def __init__(self, a_dataset, a_name=None, a_ping_interval=None, watch_cap=1,
                 a_fetch_timeout=None, a_max_pull_workers=None, a_dataset_cache=None,
                 skip=None, a_log_directory=None, a_logstash_socket=None, a_log_level=INFO):
        """
        Constructor.

        Args:
            a_name(str): A unique name that identifies this Watcher instance (e.g. "short_range_forecast_watcher").
            a_dataset(DataSet): A DataSet object representing the data to be watched.
            a_ping_interval(datetime.timedelta): Interval at which to wait after an unsuccessful attempt to fetch data
                before trying again.
            a_max_pull_workers(int): Maximum number of workers to handle pull. Defaults to 20.
            a_dataset_cache(datetime.timedelta): Defines period of data to retain on disk in addition to the file set
                required for current processing.
            watch_cap(int): The maximum number of watches that can be happening at one time. Defaults to 1.
            skip(str|list<datetime.time|datetime.datetime>): A list of datetime.time or datetime.datetime objects or
                the path to a python file that will be tested against to determine if a watch should be skipped
            a_log_directory(str): Path to a directory where logs should be written.
            a_logstash_socket(str): Socket (e.g. <hostname>:<port>) of a logstash instance where logs should be sent.
            a_log_level(logging.LEVEL): Level at which to log. Either 'DEBUG', 'INFO', 'WARNING', 'ERROR', or
                'CRITICAL'.
        """
        if not a_name:
            import uuid
            a_name = str(uuid.uuid4())

        self.name = a_name.lower().replace(' ', '')
        self._log = get_logger(self, a_log_directory, a_logstash_socket, a_log_level)
        self._log.debug('Initializing Watcher "%s"...', self.name)

        self.base_dataset = a_dataset
        self.sub_datasets = []
        self.ping_interval = a_ping_interval
        self._launch_processing = Signal()
        self.max_fetchers = a_max_pull_workers or self.DEFAULT_MAX_CONCURRENT_TRANSFERS
        self._dataset_cache = a_dataset_cache
        self._current_watches = []
        self._dataset_to_launchers_map = {}
        self._stop_event = None
        self._watch_cap = watch_cap
        self.log_directory = a_log_directory if a_log_directory is not None else ''
        self._logstash_socket = a_logstash_socket
        self._log_level = a_log_level
        self.fetch_timeout = a_fetch_timeout or self.TIMEOUT_THRESHOLD
        self.skip = skip
        self._smtp_hostname = os.getenv('PIPELINE_SMTP_HOSTNAME')
        self._smtp_port = int(os.getenv('PIPELINE_SMTP_PORT', 25))
        self._alert_email = os.getenv('PIPELINE_ALERT_EMAIL')

        if self.skip:
            self._validate_skip(self.skip)

        if self.ping_interval is None:
            self.ping_interval = self.DEFAULT_PING_INTERVAL

    @classmethod
    def _validate_skip(cls, skip_val):
        if isinstance(skip_val, list):
            for item in skip_val:
                if not isinstance(item, (dt.datetime, dt.time)):
                    raise ValueError(f"{cls.SKIP_ERROR_MSG} One or more items in the provide list are not of type "
                                     "datetime.time")
        elif isinstance(skip_val, str):
            if not os.path.isfile(skip_val):
                raise ValueError(f"{cls.SKIP_ERROR_MSG} The path provided does not exist.")
        else:
            raise ValueError(cls.SKIP_ERROR_MSG)

    def should_skip_watch(self, watch_date):
        if isinstance(self.skip, list):
            for entry in self.skip:
                if isinstance(entry, dt.datetime):
                    if entry == watch_date:
                        return True
                elif isinstance(entry, dt.time):
                    if entry == watch_date.time():
                        return True
        elif isinstance(self.skip, str):
            try:
                subprocess.run([
                    sys.executable, self.skip, watch_date.strftime('%Y%m%dT%H%M%S'), str(self.name)
                ], check=True)
                return True
            except subprocess.CalledProcessError:
                pass

        return False

    def get_eligible_clean_datetime(self):
        """
        gets earlist datetime for cleaning files
        """
        # Identify earliest date of files needed by current processing (watch)
        earliest_active_watch_time = None
        for watch in self._current_watches:
            if not earliest_active_watch_time or watch.date < earliest_active_watch_time:
                earliest_active_watch_time = watch.date

        self._log.debug('Earliest datetime in current_watches: %s', earliest_active_watch_time)

        earliest_use_watch_time = earliest_active_watch_time - self.base_dataset.repeat

        if self._dataset_cache:
            cache_boundary_datetime = earliest_use_watch_time - self._dataset_cache

            while earliest_use_watch_time >= cache_boundary_datetime:
                earliest_use_watch_time -= self.base_dataset.repeat

        # Find earliest datetime horizon among the file sets to ensure we aren't
        # cleaning files that currently being polled or processed
        datetime_horizon = self.base_dataset.get_time_horizon(earliest_use_watch_time)
        if datetime_horizon < earliest_use_watch_time:
            earliest_use_watch_time = datetime_horizon

        return earliest_use_watch_time

    def _clean_stale_files(self):
        """
        Remove outdated files that are no longer needed for current or future processing.
        """
        if self._dataset_cache == self.CACHE_ALL:
            return

        eligible_clean_datetime = self.get_eligible_clean_datetime()

        if not self._dataset_cache:
            self._log.info("Clearing out all files from recently-completed watches...")
        else:
            self._log.info('Clearing out all files dating %s and earlier...', eligible_clean_datetime)

        total_files_removed = 0
        # Continue searching for files to remove until the clean buffer is exhausted
        clean_buffer = self.CLEAN_BUFFER
        while clean_buffer:
            # Get list of files from file set for current datetime
            files_to_remove = set()
            for uri in self.base_dataset.get_uris(datetime=eligible_clean_datetime):
                self.safely_delete_old_file_locks(uri, eligible_clean_datetime)
                files_to_remove = self.safely_check_old_files(uri, eligible_clean_datetime, files_to_remove)

            for uri in self.base_dataset.get_failover_uris(datetime=eligible_clean_datetime):
                self.safely_delete_old_file_locks(uri, eligible_clean_datetime)
                files_to_remove = self.safely_check_old_files(uri, eligible_clean_datetime, files_to_remove)

            # Attempt to remove files
            iter_files_removed = 0

            for fpath in files_to_remove:
                if os.path.isfile(fpath):
                    try:
                        os.remove(fpath)
                        self._log.debug('Cleaned file: %s', fpath)
                        iter_files_removed += 1
                        total_files_removed += 1
                    except Exception:
                        self._log.warning('File could not be removed while cleaning stale files: %s', fpath)
                        pass

            # Decrement the eligible datetime for cleaning
            if self.base_dataset.repeat:
                eligible_clean_datetime -= self.base_dataset.repeat
            else:
                break

            # If none of the files are successfully removed (i.e.: don't exist) for this date, decrement the buffer
            if iter_files_removed == 0:
                clean_buffer -= 1
            # If removed at least one file, reset the clean buffer
            else:
                clean_buffer = self.CLEAN_BUFFER

        if total_files_removed == 0:
            return

        # Remove empty directories
        for dirpath, dirnames, filenames in os.walk(self.base_dataset.transfers_dir, topdown=False):
            for dname in dirnames:
                try:
                    dpath = os.path.join(dirpath, dname)
                    flist = os.listdir(dpath)
                    if not flist:
                        os.rmdir(dpath)
                        self._log.debug('Removed empty directory: %s', dpath)
                except Exception:
                    pass

    def safely_delete_old_file_locks(self, uri, eligible_clean_datetime):
        """
        Checks for old uri lock files for the source uri and the destination uri that have been left behind by runs

        uri(str): raw uri for the eligible clean datetime
        eligible_clean_datetime(datetime): available datetime for cleaning
        """
        lock_file_src = f"{uri}_{self.base_dataset.name}.LOCK"
        if os.path.exists(lock_file_src):
            os.remove(lock_file_src)

        uri_transfer_path = self.base_dataset.get_transfer_destination_path(uri=uri, datetime=eligible_clean_datetime)
        lock_file_dest = f"{uri_transfer_path}_{self.base_dataset.name}.LOCK"
        if os.path.exists(lock_file_dest):
            os.remove(lock_file_dest)

    def safely_check_old_files(self, uri, eligible_clean_datetime, files_to_remove):
        """
        Add files to remove list if not other uri lock files exist (e.g. no other processes are using that file).
        Check source for datasets that arent tranferred that want to be deleted.

        uri(str): raw uri for the eligible clean datetime
        eligible_clean_datetime(datetime): available datetime for cleaning
        files_to_remove(set): set of files that are safe to remove.
        """
        if self.base_dataset.clean:
            if not glob.glob(f'{uri}*.LOCK'):
                if os.path.exists(uri):
                    files_to_remove.add(uri)

            uri_transfer_path = self.base_dataset.get_transfer_destination_path(
                uri=uri,
                datetime=eligible_clean_datetime
            )
            if not glob.glob(f'{uri_transfer_path}*.LOCK'):
                if os.path.exists(uri_transfer_path):
                    files_to_remove.add(uri_transfer_path)

        return files_to_remove

    def _start_new_watch(self, watch_date):
        """
        Start a new Watch by creating a new Watch instance with the provided date and adding it to the current watches
        list.
        """
        for watch in self._current_watches:
            if watch.representative_date == watch_date:
                # Exit without appending because this would add a duplicate
                return

        # No duplicate found so append watch
        if self.skip:
            iter_watch_date = watch_date
            while self.should_skip_watch(iter_watch_date):
                self._log.info(f"Watch for {iter_watch_date} being skipped due to pipeline configuration.")
                iter_watch_date += self.base_dataset.repeat
            watch_date = iter_watch_date

        new_watch = Watch(
            a_watcher=self,
            a_date=watch_date,
        )
        self._current_watches.append(new_watch)

        self._log.info(mon_consts.WATCH_BEGINS_TEXT, new_watch.pretty_date)

    def _reconcile_watches(self):
        """
        Reconcile the what is currently being watched.

        This is the ONLY "place" where self._current_watches should be modified
        outside of the initialize function.

        The next iterative Watch is added either if the current watch instance
        tracking list is empty, or if progress has been made on the latest Watch
        being watched and it has not yet met its tracking_capself.

        Watcher's whose dataset has a "window" should only watch a maximum of
        two datasets (i.e. the current/latest dataset and the next one). Without
        this restraint, the Watcher will get ahead of itself since its Watches
        can almost always find at least some retrospective data.
        """
        self._log.info("Reconciling current watches.")
        # Get the representative date of the latest watch, rather than just the date, since the Watch may have
        # done a "fallback" to use older data
        latest_representative_date = self._current_watches[-1].representative_date

        # If specific seed times are used, get next watch from seed times
        if self.base_dataset.seed_times:
            # Get index of current seed time with relation to all seed times
            seed_time_index = self.base_dataset.seed_times.index(latest_representative_date)

            # If the current seed time is the last seed time
            if seed_time_index >= len(self.base_dataset.seed_times) - 1:
                # add an hour so that it extends beyond the dataset end time and will cause the pipeline to stop
                next_watch_date = latest_representative_date + dt.timedelta(hours=1)
            else:
                # get next seed time to process
                next_watch_date = self.base_dataset.seed_times[seed_time_index + 1]
        else:
            next_watch_date = latest_representative_date + self.base_dataset.repeat

        # If processes lag behind and max_service_lag is set, watcher will skip timestamps to catch up to current time
        if self.base_dataset.max_service_lag:
            now = UTCNOW()
            current_time = self.base_dataset.round_datetime(now)
            if next_watch_date <= current_time - self.base_dataset.max_service_lag:
                raw_combined_datetime = dt.datetime.combine(current_time, self.base_dataset.repeat_ref_time)
                current_valid_datetime = self.base_dataset.round_datetime(raw_combined_datetime)
                next_watch_date = current_valid_datetime
                while next_watch_date <= current_time:
                    next_watch_date += self.base_dataset.repeat
                next_watch_date -= self.base_dataset.repeat

        remove_all_before_index = -1
        watch_complete = False
        for index, watch in enumerate(self._current_watches):
            # Once a watch has reached the reconcile phase, it is no longer considered fresh
            watch.is_fresh = False

            if watch.data_not_yet_expected:
                continue
            if watch.abandon:
                self._log.info(
                    "The Watch for %s will no longer be tracked because a later watch was successful.",
                    watch.pretty_representative_date
                )
                remove_all_before_index = index
                watch_complete = True
            elif watch.no_data_available:
                if self.base_dataset.fallback:
                    if watch.can_fallback:
                        self._log.info(
                            'The dataset is configured to "fallback" to check for data. Doing so now...'
                        )
                        watch.fallback()
                    else:
                        watch.reset()
            elif watch.all_launches_initiated:
                if watch.all_processing_complete:
                    missing_files = [info[watch.MISSING_FILES_KEY] for dataset, info in watch._datasets_info.items()]
                    missing_file_str = ",".join(missing_file for missing_file in missing_files)
                    if missing_file_str:
                        self._log.warning(
                            mon_consts.PROCESS_EXITED_MISSING_FILES_TEXT,
                            watch.pretty_representative_date,
                            watch.watcher.name,
                            missing_file_str
                        )
                    else:
                        self._log.info(
                            "The Watch for %s was successful and will no longer be tracked.",
                            watch.pretty_representative_date
                        )
                    remove_all_before_index = index
                    watch_complete = True

            if watch.data_is_past_expected and not watch.all_launches_initiated:
                if not watch.logged_expected:
                    if self.base_dataset.uris != self.base_dataset.failover_uris:
                        # Replace all unavailable uris with failover
                        self._log.warning(
                            "The data for %s is past expected and will now start using failover uris:\n%s",
                            watch.pretty_representative_date,
                            watch
                        )
                        watch._start_failover_uri()
                    watch.logged_expected = True
                    continue

                if watch.data_is_expired:
                    remove_all_before_index = index
                    message = "The Watch for %s expired and will no longer be tracked:\n%s" % (watch.pretty_representative_date, watch)
                    self._log.error(message)
                    watch_complete = True
                    self.send_email(message)

            if watch_complete:
                self.base_dataset.clean_temp_files(watch.date)
                case1 = self.base_dataset.end and watch.representative_date >= self.base_dataset.end
                case2 = self.base_dataset.end == self.END_AT_LATEST and next_watch_date + self.base_dataset.delay >= UTCNOW()  # noqa
                case3 = not self.base_dataset.repeat
                if case1 or case2 or case3:
                    self._clean_stale_files()
                    self._stop_event.set()
                    self._log.info(
                        "This DataSet's end time (%s) was reached. The Watcher will now terminate.",
                        self.base_dataset.end if self.base_dataset.end != self.END_AT_LATEST else 'latest'
                    )
                    return

        watches_should_be_removed = remove_all_before_index > -1

        if watches_should_be_removed:
            self._current_watches = self._current_watches[remove_all_before_index+1:]

            # Add more watches until the watch cap is met
            num_watched_datasets = len(self._current_watches)
            while num_watched_datasets < self._watch_cap:
                self._start_new_watch(next_watch_date)
                next_watch_date += self.base_dataset.repeat
                num_watched_datasets = len(self._current_watches)

            self._clean_stale_files()

    def send_email(self, message):
        if self._smtp_hostname and self._alert_email:
            subject = 'Subject: Pipeline Error Alert'
            body = f'The {self.name} pipeline threw the following ERROR:\n{message}'
            email_content = f'{subject}\n\n{body}'
            try:
                SMTP(self._smtp_hostname, self._smtp_port).sendmail('pipeline_bot', self._alert_email, email_content)
            except Exception as exc:
                message = "Watcher.send_email threw the following unexpected exception:\n%s" % exc
                self._log.error(message, exc_info=True)

    def connect(self, a_process_executable, a_process_dataset=None, a_process_switchboard_file=None,
                a_process_interval=None, a_process_interval_ref_time=None, a_process_timeout=None, a_process_args=None):
        """
        Connect to watcher to listen for files_ready signals.

        Args:
            a_process_executable(str): full path to a python executable to be called each time new files are ready.
                This script will be called with two arguments: the zero-hour date and time, and a list of files.
            a_process_dataset(FileSubset): a FileSubset object representing DataSet be used to trigger the provided
                process executable. It must be a subset of the watcher's base file set (self.base_dataset).
                If unspecified, it is assumed to be the watcher's base file set.
            a_kill_lag_processes(bool): True will remove processes that lag behind
        """
        # Validate
        if not os.path.exists(a_process_executable):
            # log issue and don't connect
            self._log.warning('Unable to connect process "%s", because the file does not exist', a_process_executable)
            return

        if a_process_dataset:
            is_subset = a_process_dataset.validate_is_subset_of(self.base_dataset)
            if not is_subset:
                raise ValueError("The provided DataSet must be a subset of the DataSet of the watcher to which this "
                                 "script is being connected to.")
            if a_process_dataset not in self.sub_datasets:
                self.sub_datasets.append(a_process_dataset)
            process_dataset = a_process_dataset
        else:
            process_dataset = self.base_dataset

        process_valid_times = None
        if a_process_interval:
            if a_process_interval_ref_time is None:
                a_process_interval_ref_time = process_dataset.repeat_ref_time
            else:
                raw_combined_datetime = dt.datetime.combine(UTCNOW(), a_process_interval_ref_time)
                a_process_interval_ref_time = process_dataset.round_datetime(raw_combined_datetime).time()
            process_valid_times = process_dataset.get_valid_timesteps(a_process_interval_ref_time, a_process_interval)
            for time_step in process_valid_times:
                if time_step not in process_dataset.valid_timesteps:
                    raise ValueError("The execution interval for the process must match or be a subset of the new "
                                     "data interval of its dataset.")

        # Instantiate and hold onto a copy of the process class
        ppl = Launcher(
            a_process_executable,
            process_dataset,
            a_process_timeout,
            a_process_switchboard_file,
            process_valid_times,
            a_process_args,
            self.log_directory,
            self._logstash_socket,
            self._log_level
        )

        if process_dataset not in self._dataset_to_launchers_map:
            self._dataset_to_launchers_map[process_dataset] = []

        self._dataset_to_launchers_map[process_dataset].append(ppl)

        # Connect the launch slot with the id of the dataset that it is to be associated with
        self._launch_processing.connect(ppl.launch, id(process_dataset))

    def initialize_watches(self):
        """
        Resets current watches and starts a new Watch using the first valid time derived from the supplied seed
        datetime.
        """
        self._current_watches = []
        first_valid_datetime = self.base_dataset.get_first_valid_datetime()
        self._start_new_watch(first_valid_datetime)

        # Start additional watches according to the _watch_cap specified
        next_valid_datetime = first_valid_datetime
        for i in range(1, self._watch_cap):
            next_valid_datetime += self.base_dataset.repeat
            self._start_new_watch(next_valid_datetime)

        self._log.debug('Watcher "%s" was successfully initialized.', self.name)

    def fetch(self, watch):
        """
        Pulls files that are ready to fetch if they haven't already been or are not already being fetched.

        Args:
            watch(Watch): The Watch instance that dictates which files should be fetched and launched
        """
        num_to_fetch = watch.prepare_for_fetching()

        # Start up workers
        if num_to_fetch > 0:
            self._log.info(
                mon_consts.ATTEMPTING_FETCH_TEXT,
                num_to_fetch,
                watch.pretty_date
            )
            for i in range(num_to_fetch):
                fetch_worker = Thread(
                    target=self.base_dataset.fetch_data,
                    args=(watch.fetch_queue, watch.result_queue, self._stop_event)
                )
                fetch_worker.setDaemon(True)
                fetch_worker.start()
        else:
            self._log.debug(
                "Maximum number of workers (%d) already reached. No additional locating/fetching will start at "
                "this time.",
                watch.num_fetching_resources
            )

    def check_fetch_results(self, watch):
        '''
        Checks the Watch's result_queue for completed downloads. Successful downloads are moved to the available list,
        and unsuccessful are re-added to the attemptable list.
        '''
        # If this is the first time results are being checked, wait 4 seconds, otherwise, wait 0.1
        timeout = 4 if watch.num_fetching_resources == 1 else 0.1
        num_results = 0
        num_success = 0

        self._log.debug("Waiting for %d seconds for a fetch result to arrive.", timeout)
        while True:
            try:
                fetch_result = watch.result_queue.get(block=True, timeout=timeout)
                num_results += 1
                timeout = 0.1

                self._check_for_stop_event()

                uri = fetch_result['uri']

                if fetch_result['success']:
                    num_success += 1
                    watch.move_to_available(uri)
                    watch.result_queue.task_done()
                    if watch.is_expecting_data:
                        watch.move_all_to_attemptable()
                else:
                    message = fetch_result['message']
                    latest_attempt_timeout = fetch_result['timeout']

                    failed_case1 = 'Data not found' in message
                    failed_case2 = message == 'File is being downloaded by another Watcher/Watch.'
                    failed_case3 = 'timed out' in message
                    failed_case4 = 'file lock' in message and 'could not be acquired' in message

                    if failed_case1:
                        self._log.info("A data resource was not found for %s", watch.pretty_date)
                        # If the data was not found, stop attempting to find anything for now
                        watch.mark_as_failed(uri)
                        watch.reset_queues()
                        watch.move_all_to_expected()
                        reached_min_failed_attempts = all(attempts >= self.FAIL_THRESHOLD for uri, attempts in watch.failed_resources_info.items())  # noqa
                        if not watch.failed_resources_info or not reached_min_failed_attempts:
                            watch.move_one_to_attemptable()
                    elif failed_case2 or failed_case4:
                        # If the data being located/fetched by another Watcher/Watch, make another attempt
                        watch.move_to_attemptable(uri, latest_attempt_timeout)
                        watch.result_queue.task_done()
                    elif failed_case3:
                        self._log.debug(
                            'Attempt to locate/fetch %s timed out at %d seconds.',
                            uri, latest_attempt_timeout
                        )
                        # If the attempt timed out, increase the timeout a bit depending
                        # on how many resources are "waiting in line". If there
                        # are a lot of resources waiting in line to be attempted, then
                        # only increase the timeout by a bit to let more through the line
                        # quicker. If none are waiting in line, then set the timeout to
                        # the max
                        if latest_attempt_timeout >= self.fetch_timeout:
                            self._log.warning(
                                "Max timeout ({} seconds) exceeded while attempting to fetch data at {}."
                                .format(self.fetch_timeout,
                                        uri))
                            watch.mark_as_failed(uri)
                            watch.reset_queues()
                            watch.move_all_to_expected()
                            reached_min_failed_attempts = all(attempts >= self.FAIL_THRESHOLD for uri, attempts in watch.failed_resources_info.items())  # noqa
                            if not watch.failed_resources_info or not reached_min_failed_attempts:
                                watch.move_one_to_attemptable()
                        else:
                            if watch.num_attemptable_resources >= self.max_fetchers:
                                new_timeout = latest_attempt_timeout + self.TIMEOUT_INCREMENT
                            else:
                                new_timeout = self.fetch_timeout
                            self._log.debug('Trying again with a timeout of %d seconds.', new_timeout)
                            watch.move_to_attemptable(uri, new_timeout)
                            watch.result_queue.task_done()
                    else:
                        self._log.warning('Attempt to fetch %s failed with the following error:\n%s', uri, message)
                        watch.mark_as_failed(uri)
                        if watch.data_is_available and not watch.fail_threshold_reached(uri):
                            watch.move_to_attemptable(uri, latest_attempt_timeout)
                            watch.result_queue.task_done()
                        else:
                            self._log.warning(f'More than {self.FAIL_THRESHOLD} failed attemts to fetch {uri} have '
                                              'been made.')
                            watch.reset_queues()
                            watch.move_all_to_expected()

            except Empty:
                if num_results == 0:
                    self._log.debug("No resource fetches finished being attempted at this time.")
                elif num_success > 0:
                    if watch.num_available_resources == watch.num_resources:
                        self._log.info(mon_consts.ALL_AVAILABLE_TEXT, watch.pretty_representative_date)
                    else:
                        self._log.info(mon_consts.RESOURCES_AVAILABLE_TEXT, watch.num_available_resources,
                                       watch.num_resources, watch.pretty_representative_date)
                break

    def launch_if_ready(self, watch):
        """
        Launch datasets if they are ready, i.e. all data is available
        """
        # Make copy of unlaunched_datasets, because it will be modified in the loop (i.e. moved to launched_datasets)
        unlaunched_datasets = list(watch.unlaunched_datasets)
        for dataset in unlaunched_datasets:
            if watch.ready_to_launch(dataset):
                # Create a file lock for each uri that will be used.
                # If a file is missing, returns False and watch will attempt file again
                self._log.info('Creating file locks and checking file existence')
                if self._has_connected_processes(dataset):
                    if watch.create_file_uri_lock(dataset):
                        self._launch_processing(
                            watch=watch,
                            identifier=id(dataset)
                        )
                        watch.move_to_launch_initiated(dataset)
                    else:
                        self._log.warning(f"URI file lock creation failed for {watch.pretty_representative_date}. "
                                          f"Retrying to get the following data: {watch._expected_resources}")
                else:
                    watch.move_to_launch_initiated(dataset)
                    watch.move_to_launched(dataset)
                    watch.processing_complete(dataset)

    def _start_watch_loop(self):
        """
        One iteration of the steps that are triggered each ping_interval (i.e. fetching data and launching processes
        for each watch).
        """
        self._log.info("Starting the watch loop for %s...", self.name)
        first_pass = True

        while True:
            self._check_for_stop_event()

            for watch in self._current_watches:
                self._check_for_stop_event()

                if watch.data_not_yet_expected:
                    self._log.debug(
                        "This watch for %s is still in the future. Skipping for now...",
                        watch.pretty_date
                    )
                    watch.move_all_to_expected()
                    # If this watch is in the future, all subsequent watches
                    # will be as well, so BREAK
                    break

                if watch.all_processes_launched:
                    self._log.debug(
                        "All datasets have already been launched for the watch for %s. Skipping...",
                        watch.pretty_date
                    )
                    # If this watch has finished processing, all subsequent
                    # watches are likely to be able to progress, so CONTINUE
                    continue

                self._check_for_stop_event()

                # ######################################## #
                # ########### "BUSINESS LOGIC" ########### #
                # ######################################## #
                if watch.all_data_available:
                    self.base_dataset.clean_temp_files(watch.date)
                else:
                    if first_pass:
                        self._log.debug("Moving one file to attemptable for initial attempt.")
                        watch.move_all_to_attemptable()

                    self._check_for_stop_event()

                    if watch.is_fetching_data:
                        self.check_fetch_results(watch)

                    self._check_for_stop_event()

                    if watch.has_attemptable_data:
                        self.fetch(watch)

                    self._check_for_stop_event()

                    if watch.is_fetching_data:
                        self.check_fetch_results(watch)

                self._check_for_stop_event()

                self.launch_if_ready(watch)

                self._check_for_stop_event()

            first_pass = False

            self._check_for_stop_event()

            # Do not reconcile the watches until they are done fetching
            if any(watch.has_attemptable_data or watch.is_fetching_data for watch in self._current_watches):
                continue

            self._reconcile_watches()

            self._check_for_stop_event()
            # Once watchers have been reconciled, all watches can be marked as their "first pass" again
            first_pass = True

            # Do not sleep yet if a watch is newly configured
            if any(watch.is_fresh for watch in self._current_watches):
                continue

            self._check_for_stop_event()

            earliest_watch = self._current_watches[0]
            self._log.info("Watch loop iteration complete.")
            if all(watch.data_not_yet_expected for watch in self._current_watches):
                sleep_seconds = earliest_watch.seconds_until_data_expected
                self._log.info("Sleeping for %d seconds until data is expected.", sleep_seconds)
                self._sleep(sleep_seconds)
            elif earliest_watch.all_launches_initiated and not earliest_watch.all_processing_complete:
                sleep_seconds = max(earliest_watch.seconds_until_data_expected, 3600)
                self._log.info("Sleeping until processing complete...")
                self._sleep(sleep_seconds, check_processing=True)
            elif earliest_watch.data_is_expired:
                pass
            else:
                self._log.info("Sleeping for %d seconds until next attempt.", self.ping_interval.total_seconds())
                self._sleep(self.ping_interval.total_seconds())

            self._log.info("Starting new watch loop iteration...")

    def watch(self, a_stop_event=None):
        """
        Start primary watch loop.

        Args:
            a_stop_event(threading.Event): Used to stop the watch loop when being run in a separate thread.
        """
        if self.base_dataset.repeat is None:
            raise ValueError('The a_repeat argument must be set for the DataSet associated with this watcher.')
        self._stop_event = a_stop_event
        self.initialize_watches()
        try:
            self._start_watch_loop()
        except KeyboardInterrupt:
            pass
        except StopEventTriggered:
            if a_stop_event:
                a_stop_event.set()
        except Exception as exc:
            message = "Watcher._start_watch_loop threw the following unexpected exception:\n%s" % exc
            self._log.error(message, exc_info=True)
            self.send_email(message)

        # Clean up on stop
        for dataset, launchers in self._dataset_to_launchers_map.items():
            for launcher in launchers:
                launcher.stop_processes()

    def _check_for_stop_event(self):
        if self._stop_event and self._stop_event.is_set():
            raise StopEventTriggered()

    def _sleep(self, seconds, check_processing=False):
        """
        Sleeps until specified time while checking for a set stop event or finished processing

        Args:
            wake_up_time(datetime.datetime): The datetime object representing when sleep should no longer occur.
        """
        if seconds > 0:
            wake_up_time = UTCNOW() + dt.timedelta(seconds=seconds)
            heartbeat_counter = 0
            while UTCNOW() < wake_up_time:
                self._check_for_stop_event()
                if check_processing:
                    if self._current_watches[0].all_processing_complete:
                        return
                heartbeat_counter += 1
                if heartbeat_counter == self.HEARTBEAT_COUNTER:
                    self._log.info("Heartbeat")
                    heartbeat_counter = 0
                time.sleep(min(abs((wake_up_time - UTCNOW()).total_seconds()), self.MAX_UNINTERRUPTED_SLEEP))
