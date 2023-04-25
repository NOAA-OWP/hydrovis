# -*- coding: utf-8 -*-
"""
Created on Wed May 03 12:36:07 2018

@author: Shawn.Crawley
"""
from queue import Queue
from aws_loosa.processing_pipeline.utils import UTCNOW, monitoring_consts as mon_consts
import os
import time
from math import ceil


class Watch(object):
    PROCESSING_COMPLETE_KEY = 'processing_complete'
    URIS_KEY = 'resources'
    MIN_URIS_KEY = 'minimum_resources'
    MISSING_FILES_KEY = 'missing_files'
    READY_TO_LAUNCH_KEY = 'ready_to_launch'

    def __init__(self, a_watcher, a_date):
        self.watcher = a_watcher
        self.date = a_date
        self.next_date = a_date + a_watcher.base_dataset.repeat
        self.representative_date = a_date
        self.expected_date = a_date + a_watcher.base_dataset.delay
        self.expiration_date = a_date + a_watcher.base_dataset.expiration
        self.expect_date = a_date + a_watcher.base_dataset.expect

        if a_watcher.base_dataset.fallback:
            fallback_date = a_date - self.watcher.base_dataset.repeat + self.watcher.base_dataset.fallback
            self._boundary_fallback_date = fallback_date
        else:
            self._boundary_fallback_date = a_date

        self._init_data_tracking()

    def _init_data_tracking(self):
        self.abandon = False
        self.is_fresh = True
        self.launch_initiated = False
        self.logged_expected = False
        self._all_resources = []  # Always contains static list of all uris
        self._all_failover_resources = []  # Always contains static list of all failover uris
        self._expected_resources = []  # Will start at 100% and decrease
        self._attemptable_resources = []  # Will start at 0% and fluctuate, never reaching 100%
        self._fetching_resources = []  # Will start at 0% and fluctuate, never reaching 100%
        self._available_resources = []  # Will eventually reach 100%
        self._minimal_resources = []
        self._failed_resources = []
        self.failed_resources_info = {}
        self.all_processing_complete = False

        self._datasets_info = {}
        self._unlaunched_datasets = []
        self._launch_initiated_datasets = []
        self._launched_datasets = []

        self._attemptable_queue = Queue()
        self._fetch_queue = Queue()
        self._result_queue = Queue()

        all_datasets = self.watcher.sub_datasets + [self.watcher.base_dataset]
        for dataset in all_datasets:
            uris = dataset.get_uris(datetime=self.date)

            if dataset == self.watcher.base_dataset:
                # Add the uris to expected, with the "latest" (reverse-alphabetical) first in the list
                for uri in uris:
                    self._all_resources.append(uri)
                    self.move_to_expected(uri)

            if isinstance(dataset.acceptable_uris_missing, int):
                min_resources = len(uris) - dataset.acceptable_uris_missing
            elif isinstance(dataset.acceptable_uris_missing, str):
                percentage = float(dataset.acceptable_uris_missing.replace("%", ""))
                min_resources = len(uris) - ceil(len(uris) * percentage / 100)
            else:
                acceptable_missing_uris = dataset.get_acceptable_missing_uris(datetime=self.date)
                min_resources = [res for res in uris if res not in acceptable_missing_uris]
                for uri in min_resources:
                    if uri not in self._minimal_resources:
                        self._minimal_resources.append(uri)

            self._datasets_info[dataset] = {
                self.URIS_KEY: uris,
                self.MIN_URIS_KEY: min_resources,
                self.MISSING_FILES_KEY: "",
                self.READY_TO_LAUNCH_KEY: False,
                self.PROCESSING_COMPLETE_KEY: False
            }

            self._unlaunched_datasets.append(dataset)

    def move_one_to_attemptable(self):
        expected_resources = list(self._expected_resources)
        timeout = self.watcher.fetch_timeout

        if expected_resources:
            self.move_to_attemptable(expected_resources[0], timeout)

    def move_all_to_attemptable(self):
        """
        Moves all resources from the expected list to the attemptable list
        """
        expected_resources = list(self._expected_resources)
        if self.num_expected_resources < self.watcher.max_fetchers:
            timeout = self.watcher.fetch_timeout
        else:
            timeout = self.watcher.INITIAL_TIMEOUT

        for uri in expected_resources:
            self.move_to_attemptable(uri, timeout)

    @property
    def data_is_expired(self):
        return self.no_resources_attemptable and UTCNOW() > self.expiration_date

    @property
    def data_is_past_expected(self):
        return self.no_resources_attemptable and UTCNOW() > self.expect_date

    @property
    def seconds_until_data_expected(self):
        return (self.expected_date - UTCNOW()).total_seconds()

    @property
    def data_not_yet_expected(self):
        return self.expected_date > UTCNOW()

    # ########################################## #
    # ######### DATE PROPS AND METHODS ######### #
    # ########################################## #

    @property
    def pretty_date(self):
        """
        Returns a "pretty" string representation of self.date
        """

        return self.date.strftime(mon_consts.DATE_FORMAT)

    @property
    def pretty_next_date(self):
        """
        Returns a "pretty" string representation of self.next_date
        """

        return self.next_date.strftime(mon_consts.DATE_FORMAT)

    @property
    def pretty_representative_date(self):
        """
        Returns a "pretty" string representation of the self.representative_date
        """

        return self.representative_date.strftime(mon_consts.DATE_FORMAT)

    # ########################################## #
    # ####### FALLBACK PROPS AND METHODS ####### #
    # ########################################## #

    @property
    def can_fallback(self):
        """
        Checks whether the Watch can fall back and look for "prior" data in place of the actual expected data.
        """
        if self.date == self._boundary_fallback_date:
            return False
        else:
            return self.date - self.watcher.base_dataset.fallback >= self._boundary_fallback_date

    def fallback(self):
        """
        Reconfigures the Watch to look for "prior" data in place of the actual expected data.

        Raises:
            EnvironmentError
        """
        if not self.can_fallback:
            raise EnvironmentError("The Watch can no longer fall back since it already reached the fallback boundary.")

        self.date = self.date - self.watcher.base_dataset.fallback
        self._init_data_tracking()

    def reset(self):
        """
        Resets the watcher to how it was before it performed a fallback

        Raises:
            EnvironmentError
        """
        self.date = self.representative_date
        self._init_data_tracking()

    # ########################################## #
    # ####### FAILOVER PROPS AND METHODS ####### #
    # ########################################## #

    def _start_failover_uri(self):
        """
        Removes all primary uris that are not yet available and replaces them
        the corresponding failover uri.

        Raises:
            EnvironmentError
        """
        dataset = self.watcher.base_dataset
        primary_uris = dataset.get_uris(datetime=self.date)
        failover_uris = dataset.get_failover_uris(datetime=self.date)
        acceptable_missing_uris = dataset.get_acceptable_missing_uris(datetime=self.date)

        new_uri_set = []

        for uri in primary_uris:
            if uri not in self._available_resources:
                uri_index = primary_uris.index(uri)
                alternate_failover_uri = failover_uris[uri_index]
                self.remove_unavailable_uri_for_failover(uri)
                self._all_resources.append(alternate_failover_uri)

                if not isinstance(self._minimal_resources, int):
                    if alternate_failover_uri not in acceptable_missing_uris:
                        self._minimal_resources.append(alternate_failover_uri)

                self.move_to_expected(alternate_failover_uri)
                new_uri_set.append(alternate_failover_uri)
            else:
                new_uri_set.append(uri)

        if isinstance(dataset.acceptable_uris_missing, int):
            min_resources = len(primary_uris) - dataset.acceptable_uris_missing
        elif isinstance(dataset.acceptable_uris_missing, str):
            percentage = float(dataset.acceptable_uris_missing.replace("%", ""))
            min_resources = len(primary_uris) - ceil(len(primary_uris) * percentage / 100)
        else:
            min_resources = [res for res in new_uri_set if res not in acceptable_missing_uris]

        self._datasets_info[dataset] = {
            self.URIS_KEY: self._all_resources,
            self.MIN_URIS_KEY: min_resources,
            self.MISSING_FILES_KEY: "",
            self.READY_TO_LAUNCH_KEY: False,
            self.PROCESSING_COMPLETE_KEY: False
        }

    def remove_unavailable_uri_for_failover(self, resource):
        if resource in self._attemptable_resources:
            self._attemptable_resources.remove(resource)
        # Remove from fetching
        if resource in self._fetching_resources:
            self._fetching_resources.remove(resource)
        # Remove from failed
        if resource in self._failed_resources:
            self._failed_resources.remove(resource)
        # Remove from failed info
        if resource in self.failed_resources_info:
            self.failed_resources_info.pop(resource)
        # Remove from expected
        if resource in self._expected_resources:
            self._expected_resources.remove(resource)
        # Remove from all resources
        if resource in self._all_resources:
            self._all_resources.remove(resource)
        # Remove from acceptable resources
        if not isinstance(self._minimal_resources, int):
            if resource in self._minimal_resources:
                self._minimal_resources.remove(resource)

    # ########################################## #
    # ###### "ALL" RESOURCES PROPS AND METHODS ##### #
    # ########################################## #

    @property
    def num_resources(self):
        return len(self._all_resources)

    @property
    def unavailable_data(self):
        ud = self._expected_resources + self._attemptable_resources + self._fetching_resources
        return ud

    def reset_queues(self):
        self._attemptable_queue = Queue()
        self._fetch_queue = Queue()
        self._result_queue = Queue()

    # ########################################## #
    # ### "EXPECTING" RESOURCES PROPS AND METHODS ## #
    # ########################################## #

    @property
    def num_expected_resources(self):
        return len(self._expected_resources)

    @property
    def is_expecting_data(self):
        return self.num_expected_resources > 0

    @property
    def percent_expected(self):
        return float(self.num_expected_resources)/float(self.num_resources) * 100

    @property
    def no_data_expected(self):
        return self.num_expected_resources == 0

    def move_to_expected(self, resource):
        # Remove from attemptable
        if resource in self._attemptable_resources:
            self._attemptable_resources.remove(resource)
        # Remove from fetching
        if resource in self._fetching_resources:
            self._fetching_resources.remove(resource)
        # Remove from available
        if resource in self._available_resources:
            self._available_resources.remove(resource)
        # Remove from failed
        if resource in self._failed_resources:
            self._failed_resources.remove(resource)

        # Add to expected
        if resource not in self._expected_resources:
            self._expected_resources.append(resource)

    def move_all_to_expected(self):
        if (self.unavailable_data):
            unavailable_data = list(self.unavailable_data)
            unavailable_data.append(unavailable_data.pop(0))
            for uri in unavailable_data:
                self.move_to_expected(uri)

    # ########################################## #
    # ### "ATTEMPTABLE" RESOURCES PROPS AND METHODS ### #
    # ########################################## #

    @property
    def num_attemptable_resources(self):
        return len(self._attemptable_resources)

    @property
    def percent_attemptable(self):
        return float(self.num_attemptable_resources)/float(self.num_resources) * 100

    @property
    def has_attemptable_data(self):
        return self.num_attemptable_resources > 0

    @property
    def no_resources_attemptable(self):
        return self.num_attemptable_resources == 0

    def move_to_attemptable(self, resource, timeout=None):
        """
        Move a resource to the attemptable list.

        Adds a resource to the list representing the resources that can
        be attempted to be located/fetched.

        Args:
            resource(str): the URI that should be moved to the attemptable list
            timeout(int): the number of seconds the attempt should wait before timing out
        """
        if timeout is None:
            timeout = self.watcher.INITIAL_TIMEOUT

        # Remove from failed
        if resource in self._failed_resources:
            self._failed_resources.remove(resource)

        # Remove from expected
        if resource in self._expected_resources:
            self._expected_resources.remove(resource)

        # Remove from fetching
        if resource in self._fetching_resources:
            self._fetching_resources.remove(resource)

        # Skip if already in available
        if resource in self._available_resources:
            # Remove from attemptable
            if resource in self._attemptable_resources:
                self._attemptable_resources.remove(resource)
            return

        # Add to attemptable
        if resource not in self._attemptable_resources:
            self._attemptable_resources.append(resource)

        fetch_data = {
            'uri': resource,
            'date': self.date,
            'timeout': timeout,
            'success': False,
            'message': ''
        }

        self._attemptable_queue.put(fetch_data)

    # ########################################## #
    # ### "PULLING" RESOURCES PROPS AND METHODS ### #
    # ########################################## #

    @property
    def num_fetching_resources(self):
        return len(self._fetching_resources)

    @property
    def percent_fetching(self):
        return float(self.num_fetching_resources)/float(self.num_resources) * 100

    @property
    def is_fetching_data(self):
        return self.num_fetching_resources > 0

    def prepare_for_fetching(self):
        fetching = 0
        num_already_fetching = self.num_fetching_resources
        # All data is either in queue to be fetched, being fetched, or fetched and available
        if self.data_is_available:
            # If data is available, go ahead and fetch as much remaining data as possible
            max_fetchers = self.watcher.max_fetchers
        else:
            # If no data is available, the initial fetch either should be
            # attempted (no data being fetched), or is currently being
            # attempted (data is being fetched)
            max_fetchers = 0 if self.is_fetching_data else 1

        for _ in range(num_already_fetching, max_fetchers):
            if self._attemptable_queue.empty():
                return fetching

            fetch_data = self._attemptable_queue.get()

            uri = fetch_data['uri']

            # Remove from attemptable
            if uri in self._attemptable_resources:
                self._attemptable_resources.remove(uri)

            # Remove from expected
            if uri in self._expected_resources:
                self._expected_resources.remove(uri)

            # Skip if already in available
            if uri in self._available_resources:
                # Remove from fetching
                if uri in self._fetching_resources:
                    self._fetching_resources.remove(uri)
                self._attemptable_queue.task_done()
                continue  # pragma: no cover

            # Add to fetching
            if uri not in self._fetching_resources:
                self._fetching_resources.append(uri)

            self._fetch_queue.put(fetch_data)
            self._attemptable_queue.task_done()
            fetching += 1

        return fetching

    # ########################################## #
    # #### "PULLED" RESOURCES PROPS AND METHODS #### #
    # ########################################## #

    @property
    def num_available_resources(self):
        return len(self._available_resources)

    @property
    def percent_available(self):
        return float(self.num_available_resources)/float(self.num_resources) * 100

    @property
    def num_minimal_resources(self):
        if isinstance(self._minimal_resources, int):
            return self._minimal_resources
        else:
            return len(self._minimal_resources)

    @property
    def percent_acceptable(self):
        return float(self.num_minimal_resources)/float(self.num_resources) * 100

    @property
    def data_is_available(self):
        return self.num_available_resources > 0

    @property
    def all_data_available(self):
        return self.num_available_resources == self.num_resources

    @property
    def no_data_available(self):
        return self.num_available_resources == 0

    def move_to_available(self, resource):
        # Remove from expected
        if resource in self._expected_resources:
            self._expected_resources.remove(resource)
        # Remove from attemptable
        if resource in self._attemptable_resources:
            self._attemptable_resources.remove(resource)
        # Remove from fetching
        if resource in self._fetching_resources:
            self._fetching_resources.remove(resource)
        # Remove from failed
        if resource in self._failed_resources:
            self._failed_resources.remove(resource)
        # Add to available
        if resource not in self._available_resources:
            self._available_resources.append(resource)

        for dataset, info in list(self._datasets_info.items()):
            transfer_resource = dataset.get_single_transfer_path(resource, self.date)
            if transfer_resource and self.watcher._has_connected_processes:
                lock_file = f"{transfer_resource}_{dataset.name}.LOCK"
                if not os.path.exists(lock_file):
                    open(lock_file, 'w+').close()

            # Only update dataset if it contains the available file in the first place
            if resource in info[self.URIS_KEY]:
                ready_to_launch = True
                for res in info[self.URIS_KEY]:
                    if res not in self._available_resources:
                        ready_to_launch = False
                        break

                info[self.READY_TO_LAUNCH_KEY] = ready_to_launch

    # ########################################## #
    # #### "PULLED" RESOURCES PROPS AND METHODS #### #
    # ########################################## #

    @property
    def num_failed_resources(self):
        return len(self._failed_resources)

    @property
    def percent_failed(self):
        return float(self.num_failed_resources)/float(self.num_resources) * 100

    @property
    def has_failed_fetch_attempts(self):
        return self.num_failed_resources > 0

    @property
    def no_fetch_attempts_failed(self):
        return self.num_failed_resources == 0

    def mark_as_failed(self, resource):
        if resource not in self.failed_resources_info:
            self.failed_resources_info[resource] = 0
        self.failed_resources_info[resource] += 1

        if self.fail_threshold_reached(resource) and UTCNOW() > self.expect_date:
            self.move_to_failed(resource)

    def move_to_failed(self, resource):
        if resource not in self._failed_resources:
            self._failed_resources.append(resource)

    def fail_threshold_reached(self, resource):
        return self.failed_resources_info[resource] >= self.watcher.FAIL_THRESHOLD

    @property
    def num_global_failed_resources(self):
        return len(self.failed_resources_info)

    # ########################################## #
    # ######## QUEUE PROPS AND METHODS ######### #
    # ########################################## #

    @property
    def attemptable_queue(self):
        return self._attemptable_queue

    @property
    def fetch_queue(self):
        return self._fetch_queue

    @property
    def result_queue(self):
        return self._result_queue

    # ########################################## #
    # ## RESOURCESET AND LAUNCH PROPS AND METHODS ## #
    # ########################################## #

    @property
    def num_all_datasets(self):
        return len(self._datasets_info)

    @property
    def unlaunched_datasets(self):
        return self._unlaunched_datasets

    @property
    def num_unlaunched_datasets(self):
        return len(self._unlaunched_datasets)

    @property
    def num_launch_initiated_datasets(self):
        return len(self._launch_initiated_datasets)

    @property
    def num_launched_datasets(self):
        return len(self._launched_datasets)

    @property
    def percent_unlaunched(self):
        return float(self.num_unlaunched_datasets)/float(self.num_all_datasets) * 100

    @property
    def percent_launched(self):
        return float(self.num_launched_datasets)/float(self.num_all_datasets) * 100

    @property
    def all_launches_initiated(self):
        return self.num_launch_initiated_datasets == self.num_all_datasets

    @property
    def all_processes_launched(self):
        return self.num_launched_datasets == self.num_all_datasets

    def create_file_uri_lock(self, a_dataset):
        """
        Check to see if files exist and create file lock for file with process name.

        Returns False if a file doesn't exist and moves it to expected
        """
        non_existing_files = []

        transfer_paths = a_dataset.get_all_transfer_paths(self._available_resources, self.date)

        resources_sorted = sorted(self._available_resources)
        transfer_paths_sorted = sorted(transfer_paths)

        for index in range(len(transfer_paths_sorted)):
            uri = transfer_paths_sorted[index]
            if os.path.exists(uri):
                # A {uri}_{a_dataset.name}.LOCK file will be created which indicates to other processes that the uri
                # file is being used and cant be deleted.
                lock_file = f"{uri}_{a_dataset.name}.LOCK"
                file_in_use = False
                if not os.path.exists(lock_file):
                    open(lock_file, 'w+').close()
                else:
                    file_in_use = True

                # This will ensure that the uri is fully downloaded before the process kicks off.
                file_size = 0
                while True:
                    try:
                        file_info = os.stat(uri)
                    except Exception as e:
                        a_dataset._log.warning(f"Error getting file statistics for {uri}. Trying to download file again if possible. Error - {e}")  # noqa
                        if not file_in_use and os.path.exists(uri):
                            os.remove(uri)
                            os.remove(lock_file)
                        non_existing_files.append(uri)
                        self.move_to_expected(resources_sorted[index])
                        break

                    if file_info.st_size == 0 or file_info.st_size > file_size:
                        file_size = file_info.st_size
                        time.sleep(.1)
                    else:
                        break
            else:
                non_existing_files.append(uri)
                self.move_to_expected(resources_sorted[index])

        if non_existing_files:
            self._datasets_info[a_dataset][self.READY_TO_LAUNCH_KEY] = False
            return False
        else:
            return True

    def delete_file_uri_lock(self, a_dataset):
        """
        Remove files locks (uri_dataset_name.LOCK) after the process has finished (success or not)
        """
        dataset = self._datasets_info[a_dataset]

        transfer_paths = a_dataset.get_all_transfer_paths(dataset[self.URIS_KEY], self.date)

        for uri in transfer_paths:
            lock_file = f"{uri}_{a_dataset.name}.LOCK"
            # Only delete the lock file if it exists and a window is not set for the dataset. This will make sure that
            # files are not deleted for a service that uses a window.
            if os.path.exists(lock_file) and not a_dataset.window:
                os.remove(lock_file)

    def ready_to_launch(self, a_dataset):
        uris = self._datasets_info[a_dataset][self.URIS_KEY]
        min_uris = self._datasets_info[a_dataset][self.MIN_URIS_KEY]

        ready = False
        all_uris_available = all(uri in self._available_resources for uri in uris)
        if all_uris_available:
            ready = True
        else:  # Check to make sure accaptable uris are available and resources have been attempted to fail threshold
            if self.logged_expected:  # If the data is not past expected, keep looking
                if isinstance(min_uris, int):
                    all_minimal_resources_available = min_uris <= len(self._available_resources)
                    reached_min_minimal_resources = min_uris <= len(self._available_resources)
                else:
                    all_minimal_resources_available = all(uri in self._available_resources for uri in min_uris)
                    reached_min_minimal_resources = len(min_uris) <= len(self._available_resources)

                reached_min_failed_attempts = False
                attempted_files = list(self.failed_resources_info.keys()) + self._available_resources

                if sorted(attempted_files) >= sorted(self._all_resources):
                    reached_min_failed_attempts = all(attempts >= self.watcher.FAIL_THRESHOLD for uri, attempts in self.failed_resources_info.items())  # noqa

                resources_still_pending = self.has_attemptable_data or self.is_fetching_data
                ready = all_minimal_resources_available and reached_min_minimal_resources and reached_min_failed_attempts and not resources_still_pending  # noqa

                if ready:
                    missing_files = ",".join(uri for uri in uris if uri not in self._available_resources)
                    self._datasets_info[a_dataset][self.MISSING_FILES_KEY] = missing_files

        self._datasets_info[a_dataset][self.READY_TO_LAUNCH_KEY] = ready

        return self._datasets_info[a_dataset][self.READY_TO_LAUNCH_KEY]

    def move_to_launch_initiated(self, a_dataset):
        if a_dataset not in self._launch_initiated_datasets:
            self._launch_initiated_datasets.append(a_dataset)

    def move_to_launched(self, a_dataset):
        if a_dataset not in self._launched_datasets:
            self._launched_datasets.append(a_dataset)
        if a_dataset in self.unlaunched_datasets:
            self.unlaunched_datasets.remove(a_dataset)

    def processing_complete(self, a_dataset):
        self._datasets_info[a_dataset][self.PROCESSING_COMPLETE_KEY] = True

        if all(self._datasets_info[key][self.PROCESSING_COMPLETE_KEY] is True for key in self._datasets_info):
            self.all_processing_complete = True

    def get_stats(self):
        """
        Get the stats of the Watch instance.
        """
        return '''
            Watch Info:
                Watcher: {watcher}
                Fileset date: {date}
                All resources: {num_resources}
                Expecting resources: {num_expected_resources} ({percent_expected}%){one_expected_file}
                Attemptable resources: {num_attemptable_resources} ({percent_attemptable}%)
                Fetching resources: {num_fetching_resources} ({percent_fetching}%)
                Available resources: {num_available_resources} ({percent_available}%)
                Acceptable resources: {num_minimal_resources} ({percent_acceptable}%)
                Failed resources: {num_failed_resources} ({percent_failed}%) {failed_resources_info}
                All datasets: {num_all_datasets}
                Launched datasets: {num_launched_datasets} ({percent_launched}%)
                Unlaunched datasets: {num_unlaunched_datasets} ({percent_unlaunched}%){unlaunched_datasets}
        '''.format(
            watcher=self.watcher.name,
            date=self.representative_date,
            num_resources=self.num_resources if self.num_resources > 50 else f'{self.num_resources} - i.e. {self._all_resources}',  # noqa
            num_expected_resources=self.num_expected_resources,
            percent_expected=self.percent_expected,
            one_expected_file='' if self.num_expected_resources == 0 else ' - i.e. {}'.format(self._expected_resources[0]),  # noqa
            num_attemptable_resources=self.num_attemptable_resources,
            percent_attemptable=self.percent_attemptable,
            num_fetching_resources=self.num_fetching_resources,
            percent_fetching=self.percent_fetching,
            num_available_resources=self.num_available_resources,
            percent_available=self.percent_available,
            num_minimal_resources=self.num_minimal_resources,
            percent_acceptable=self.percent_acceptable,
            num_failed_resources=self.num_global_failed_resources,
            percent_failed=self.percent_failed,
            failed_resources_info=self.failed_resources_info if self.num_global_failed_resources > 0 else '',
            num_all_datasets=self.num_all_datasets,
            num_launched_datasets=self.num_launched_datasets,
            percent_launched=self.percent_launched,
            num_unlaunched_datasets=self.num_unlaunched_datasets,
            percent_unlaunched=self.percent_unlaunched,
            unlaunched_datasets='' if self.num_unlaunched_datasets == 0 else ' - {}'.format(', '.join([fs.name for fs in self.unlaunched_datasets]))  # noqa
        )

    def __str__(self):
        return self.get_stats()
