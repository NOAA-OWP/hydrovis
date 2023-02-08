# -*- coding: utf-8 -*-
"""
Created on Jun 08, 2017

@author: ArcGISServices
"""
import ctypes
import os
import re
import subprocess as sp
import sys
from threading import Lock, ThreadError

import filelock

from processing_pipeline.logging import get_logger
from processing_pipeline.utils import monitoring_consts as mon_consts


class Launcher(object):
    """
    Launches a processes.
    """
    TRANSFER_PATHS = "{{TRANSFER_PATHS}}"
    TRANSFER_PATHS_FILE = "{{TRANSFER_PATHS_FILE}}"
    FILESET_DATE = "{{FILESET_DATE__"
    FILESET_NEXT_DATE = "{{FILESET_NEXT_DATE__"
    TRANSFERS_DIR = "{{TRANSFERS_DIR}}"
    LOGS_DIRECTORY = "{{LOGS_DIR}}"
    VALID_ARG_KEYWORDS = [
        TRANSFER_PATHS,
        TRANSFER_PATHS_FILE,
        FILESET_DATE,
        FILESET_NEXT_DATE,
        TRANSFERS_DIR,
        LOGS_DIRECTORY
    ]
    DEFAULT_NAME = 'defaultlauncher'
    SWITCHBOARD_DELIMTER = '\t\t\t'
    ONOFF_TO_BOOL = {
        'On': True,
        'Off': False
    }
    BOOL_TO_ONOFF = {
        True: 'On',
        False: 'Off'
    }

    def __init__(
        self, a_process_executable, a_process_dataset=None,
        a_process_timeout=None, a_process_switchboard_file=None,
        a_process_valid_times=None, a_process_args=None, a_log_directory=None,
        a_logstash_socket=None, a_log_level='INFO'
    ):
        """
        Constructor

        Args:
            a_process_executable(str): Path to the process executable.
            a_logstash_socket(str): Socket (e.g. <hostname>:<port>) of a logstash instance where logs should be sent.
        """
        self.name = self._get_instance_name(a_process_executable, a_process_dataset)
        self._log = get_logger(self, a_log_directory, a_logstash_socket, a_log_level)
        self._log.debug('Initializing Launcher for "%s"...', a_process_executable)

        self._process_executable = a_process_executable
        self._process_switchboard_file = a_process_switchboard_file
        self._run_process_lock = Lock()
        self._raw_process_args = a_process_args
        self._process = None
        self._dataset = a_process_dataset
        self._process_valid_times = a_process_valid_times
        self._kill_lag_processes = None
        self._use_switchboard = a_process_switchboard_file is not None
        self._keyword_args_mapping = {}
        self._transfer_paths_file = None
        self._watch = None

        if self._use_switchboard:
            try:
                os.makedirs(os.path.dirname(self._process_switchboard_file))
            except OSError:
                pass

            process_switchboard_dict = self._get_process_switchboard_dict()

            if self._process_executable not in process_switchboard_dict:
                process_switchboard_dict[self._process_executable] = True

            self._write_process_switchboard_dict_to_file(process_switchboard_dict)

        if not a_process_timeout:
            if not a_process_dataset:
                self._process_timeout = None
            else:
                if a_process_dataset.repeat:
                    self._process_timeout = a_process_dataset.repeat.total_seconds()
                else:
                    self._process_timeout = None
        else:
            self._process_timeout = a_process_timeout.total_seconds()

    def _get_instance_name(self, process_executable, process_dataset):
        name = self.DEFAULT_NAME
        if process_dataset:
            name = process_dataset.name
        elif os.path.isfile(process_executable):
            try_name = os.path.basename(process_executable).replace('_process', '').replace('.py', '').replace('process', '')
            if try_name:
                name = try_name
        return name

    def _substitute_process_args(self, raw_args):
        """
        Substitute any keyword process args with the appropriate object
        """
        if not raw_args or not isinstance(raw_args, list):
            self._transfer_paths_file = self._dataset.write_transfer_paths_to_file(
                self._watch._available_resources, self._watch.date
            )
            new_args = [
                self._watch.pretty_date,
                self._transfer_paths_file,
                self._watch.watcher.log_directory,
                self._watch.pretty_next_date,
            ]
        else:
            new_args = []
            for arg in raw_args:
                found = False
                for key in self.VALID_ARG_KEYWORDS:
                    arg_str = str(arg)
                    if key in arg_str:
                        if key in [self.FILESET_DATE, self.FILESET_NEXT_DATE]:
                            new_arg = self.replace_datetime_keywords(arg_str)
                            new_args.append(new_arg)
                        elif key == self.TRANSFER_PATHS_FILE:
                            self._transfer_paths_file = self._dataset.write_transfer_paths_to_file(
                                self._watch._available_resources, self._watch.date
                            )
                            new_args.append(arg_str.replace(key, self._transfer_paths_file))
                        elif key == self.TRANSFER_PATHS:
                            transfer_paths = ','.join(
                                self._dataset.get_all_transfer_paths(self._watch._available_resources, self._watch.date)
                            )
                            new_args.append(arg_str.replace(key, transfer_paths))
                        elif key == self.TRANSFERS_DIR:
                            transfers_dir = self._dataset.get_transfer_destination_path(datetime=self._watch.date)
                            new_args.append(arg_str.replace(key, transfers_dir))
                        elif key == self.LOGS_DIRECTORY:
                            new_args.append(arg_str.replace(key, self._watch.watcher.log_directory))
                        found = True
                if not found:
                    new_args.append(str(arg))

        return new_args

    def _get_process_switchboard_dict(self):
        process_switchboard_dict = {}
        if os.path.isfile(self._process_switchboard_file):
            with open(self._process_switchboard_file, 'r') as swithboard_file_ro:
                for line in swithboard_file_ro.readlines():
                    cols = line.strip().split(self.SWITCHBOARD_DELIMTER)
                    process_switchboard_dict[cols[0]] = self.ONOFF_TO_BOOL[cols[1]]

        return process_switchboard_dict

    def _write_process_switchboard_dict_to_file(self, process_switchboard_dict):
        try:
            lockfile = filelock.FileLock(self._process_switchboard_file + '.lock', timeout=1)
            with lockfile:
                with open(self._process_switchboard_file, 'w+') as swithboard_file_w:
                    for key, val in sorted(list(process_switchboard_dict.items())):
                        swithboard_file_w.write(
                            '{}{}{}\n'.format(key, self.SWITCHBOARD_DELIMTER, self.BOOL_TO_ONOFF[val])
                        )
        except filelock.Timeout:
            self._log.warning("Switchboard location was inacessible: %s", self._process_switchboard_file)

    def launch(self, watch=None):
        """
        Method that is used to launch process executables.

        NOTE: In the pipeline, this method is run on a separate thread.
        """
        # Prevent launching the same process back to back by creating an id from the args
        if self._process:
            if watch == self._watch:
                self._log.warning('An attempt was prevented from launching a duplicate publishing process: "%s".',
                                  self._process_executable)
                return

        if self._use_switchboard:
            process_switchboard_dict = self._get_process_switchboard_dict()
            if self._process_executable in process_switchboard_dict:
                if process_switchboard_dict[self._process_executable] is False:
                    self._log.info('Process %s was ready to launch, but is turned off in the switchboard file. '
                                   'Skipping for now...', self._process_executable)
                    watch.move_to_launched(self._dataset)
                    watch.processing_complete(self._dataset)
                    return

        if self._process_valid_times and watch.date.time() not in self._process_valid_times:
            self._log.info('Process %s is not being launched since the current time of the launching watch (%s) is '
                           'not in the valid times of this process: %s.',
                           self._process_executable, watch.date.time(), self._process_valid_times)
            watch.move_to_launched(self._dataset)
            watch.processing_complete(self._dataset)
            return

        # Acquire process lock and check - only allow one process to run per launcher
        lock_acquired = self._run_process_lock.acquire(False)

        # Prevent launcher from backing up with to many processes
        if not lock_acquired:
            self._log.warning(
                'Cannot launch publishing process for %s, because another process is already running.',
                watch.pretty_date
            )
            # If process is already running, this function should return immediately and not attempt to start the
            #  process again.
            return

        self._watch = watch
        process_args = self._substitute_process_args(self._raw_process_args)

        if self._process_executable.endswith('.py'):
            cmd_args = [sys.executable, self._process_executable] + list(process_args)
            self._log.debug('Using Python executable "%s" for process "%s"', sys.executable, self._process_executable)
        else:
            cmd_args = [self._process_executable] + list(process_args)

        # Create the new process
        if sys.platform.startswith("win"):
            # Don't display the Windows GPF dialog if the invoked program dies.
            # See comp.os.ms-windows.programmer.win32
            ctypes.windll.kernel32.SetErrorMode(0x0002)  # From MSDN
            subprocess_flags = 0x08000000  # CREATE_NO_WINDOW flag - Windows API
        else:
            subprocess_flags = 0

        # This is to make sure that the correct username is used for Pro so that arcpy doesn't raise an error about
        # not being signed in
        if os.getenv('VIZ_ENVIRONMENT') in ['production', 'staging']:
            os.environ['USERNAME'] = os.environ['VIZ_USER']

        self._process = sp.Popen(
            cmd_args,
            creationflags=subprocess_flags,
            stderr=sp.PIPE,
            stdout=sp.PIPE,
        )

        self._log.info(
            mon_consts.PROCESS_LAUNCHED_TEXT,
            self._watch.pretty_date,
            self._watch.watcher.name,
            ' '.join('"{0}"'.format(parg) for parg in cmd_args)
        )

        self._watch.move_to_launched(self._dataset)

        try:
            stdout, stderr = self._process.communicate(timeout=self._process_timeout)
        except sp.TimeoutExpired:
            self._process.kill()
            message = f'Process launched for {self._watch.pretty_date} timed out.'
            self._log.error(message)
            self._watch.watcher.send_email(message)
        else:
            if self._process.returncode != 0:
                message = f'Process launched for {self._watch.pretty_date} exited with return code {self._process.returncode}./n{stderr}'
                self._log.error(message)
                self._watch.watcher.send_email(message)
            else:
                self._log.info(
                    mon_consts.PROCESS_EXITED_TEXT,
                    self._watch.pretty_date,
                    self._watch.watcher.name,
                )
        finally:
            self._watch.delete_file_uri_lock(self._dataset)

        self._watch.processing_complete(self._dataset)

        try:
            self._run_process_lock.release()
        except ThreadError:
            pass

    def replace_datetime_keywords(self, arg_str):
        new_arg = arg_str
        date_matches = set(re.findall('{{FILESET_DATE__[^}]+}}', arg_str))
        next_date_matches = set(re.findall('{{FILESET_NEXT_DATE__[^}]+}}', arg_str))
        matches = date_matches.union(next_date_matches)
        if matches:
            for match in matches:
                format = match.split('__')[1][:-2]
                date_obj = self._watch.next_date if 'NEXT_DATE' in match else self._watch.date
                date_string = date_obj.strftime(format)
                new_arg = new_arg.replace(match, date_string)

        return new_arg

    def stop_processes(self):
        """
        Safely stop processes if running.
        """
        # Try to aquire the run process lock to prevent further processes from launching if none are running
        lock_acquired = self._run_process_lock.acquire(False)

        # If we can't acquire the lock, then a process is running, so we need to stop it.
        if not lock_acquired and self._process:
            self._process.kill()
            self._log.fatal('Process "%s" killed prematurely.', self.name)
