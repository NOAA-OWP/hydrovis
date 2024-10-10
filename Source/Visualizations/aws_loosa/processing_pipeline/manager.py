# -*- coding: utf-8 -*-
"""
Created on Wed May 03 12:36:07 2017

@author: Nathan.Swain, Shawn.Crawley
"""
import time
import datetime as dt
import threading

from aws_loosa.processing_pipeline.pipeline_logging import get_logger


class Manager(object):
    """
    Responsible for managing all of the watchers.
    """
    SLEEP_BETWEEN_HEARTBEAT_CHECK = 3

    def __init__(self, a_name, a_log_directory=None, a_logstash_socket=None, a_log_level='INFO'):
        """
        Constructor.

        Args:
            a_name(str): A unique name used to identify the pipeline manager instance.
            a_log_directory(str): Path to a directory where logs should be written. If not set, no logs will be
                written to file.
            a_logstash_socket(str): Socket (e.g. <hostname>:<port>) of a logstash instance where logs should be sent.
            a_log_level(logging.LEVEL): Level at which to log. Either 'DEBUG', 'INFO', 'WARNING', 'ERROR', or
                'CRITICAL'.
        """
        self.name = a_name.lower().replace(' ', '')
        self._log = get_logger(self, a_log_directory, a_logstash_socket, a_log_level)
        self._log.debug('Initializing Manager "%s"...', self.name)

        self._watchers = []
        self._threads = []
        self._stop_events = []

    def add_watcher(self, a_watcher):
        """
        Add a watcher to the pipeline.
        """
        self._watchers.append(a_watcher)

    def start(self):
        """
        Start the main pipeline loop.
        """
        self._log.info("The following pipeline was started: %s", self.name)
        self._log.debug('Starting watchers for Pipeline Manager "%s"...', self.name)
        for watcher in self._watchers:
            self._log.debug('Creating new thread for Watcher "%s".', watcher.name)
            stop_event = threading.Event()
            watcher_thread = threading.Thread(
                target=watcher.watch,
                kwargs={
                    'a_stop_event': stop_event
                }
            )
            watcher_thread.daemon = True
            watcher_thread.start()
            self._threads.append(watcher_thread)
            self._stop_events.append(stop_event)

        try:
            last_heartbeat_minute = dt.datetime.now(dt.UTC).minute
            while True:
                time.sleep(self.SLEEP_BETWEEN_HEARTBEAT_CHECK)
                current_minute = dt.datetime.now(dt.UTC).minute
                if last_heartbeat_minute != current_minute:
                    self._log.info("Heartbeat.")
                    last_heartbeat_minute = current_minute

                if all(stop_event.is_set() for stop_event in self._stop_events):
                    raise SystemExit()
        except (KeyboardInterrupt, SystemExit):
            self._log.warning("The following pipeline is stopping: %s", self.name)

            for stop_event in self._stop_events:
                stop_event.set()

            for watcher_thread in self._threads:
                watcher_thread.join()
