# -*- coding: utf-8 -*-
"""
Created on Fri Mar 24 09:31:40 2017

@author: Nathan.Swain
"""
import os
import re
import json
import datetime as dt
import inspect
import traceback

from processing_pipeline.logging import get_logger
from processing_pipeline.utils.mixins import FileHandlerMixin
from processing_pipeline.utils import monitoring_consts as mon_consts


class PipelineProcess(FileHandlerMixin):
    """
    Processor objects wrap the product functions to provide a consistent interface for the publishing pipeline to call.

    Args:
        a_log_directory (str): Directory where log will be written.
        a_log_level (str): Log level to use for logging. Either 'INFO', 'WARN', 'ERROR', or 'DEBUG'.

    Attributes:
        output_location (str): Path to output location.
    """
    # Data locations and names
    output_location = ''

    def __init__(self, a_log_directory=None, a_logstash_socket=None, a_log_level='INFO', a_name='', **kwargs):
        """
        Constructor.
        """
        self.name = self._get_instance_name(a_name)
        self._log = get_logger(self, a_log_directory, a_logstash_socket, a_log_level)
        self._log.debug('Initializing Process "%s"...', self.name)

    def _get_instance_name(self, a_name):
        name = self.__class__.__name__.lower()
        # Derive name from name of subclass
        if a_name:
            name = a_name
        else:
            try:
                # Gets the file of the class (i.e. "mrf_day2_high_flow_probability_process.py") & cuts off "_process.py"
                name = os.path.basename(inspect.getfile(self.__class__)).replace('_process', '').replace('.py', '')
            except Exception:
                try:
                    # The following turns "Ana24HrAccumPrecipitation" into "ana_24_hr_accum_precipitation"
                    name = re.sub('([A-Z]+|[0-9A-Z]+)', r'_\1', self.__class__.__name__).lower()[1:]
                except Exception:
                    pass

        return name

    def _process(self, a_event_time, a_input_files, a_output_location, *args, **kwargs):
        """
        Override this method with logic to execute the post processing steps.

        Args:
            a_event_time(datetime.datetime): the datetime associated with the current processing run.
            a_input_files(list): a list of absolute paths to the required input files.
            a_output_location(str): the location to be used to write output from the process.
        """
        raise NotImplementedError()

    def execute(self, a_event_time, a_input_files):
        """
        A Slot for the Watcher's "files_ready" Signal. On startup register each Processor's "process" method with the
        appropriate Watcher's "files_ready" Signal. At a minimum, this method should deserialize the forecast time and
        input files list and call the _process method with the results. Override this method to do more than this.

        Args:
            a_event_time (str): Serialized datetime corresponding with this processing event.
            a_input_files (str): Path to file with serialized list of files to be processed.
        """
        success = False
        try:
            self.input_files = []
            self.process_event_time = dt.datetime.strptime(a_event_time, mon_consts.DATE_FORMAT)
            self.pretty_event_datetime = a_event_time

            # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
            self._log.info(mon_consts.EXECUTE_CALLED_TEXT, self.pretty_event_datetime)

            if not os.path.exists(a_input_files):
                raise Exception('Could not find file "{0}"'.format(a_input_files))

            # Deserialize the list of files
            with open(a_input_files) as files_list_file:
                content = files_list_file.read()
                self.input_files = json.loads(content)

            # DON'T CHANGE THE FOLLOWING LOG STATEMENT - MONITORING DEPENDS ON IT EXACTLY AS IS
            self._log.info(mon_consts.EXECUTING_PROCESSING_TEXT, self.pretty_event_datetime)
            self._process(self.process_event_time, self.input_files, self.output_location)
            self._log.info(mon_consts.EXECUTE_SUCCESS_TEXT, self.pretty_event_datetime)
            success = True
        except Exception as e:
            self._log.error(
                'Processing for %s failed with the following details:\n%s\n%s',
                self.pretty_event_datetime, str(e), traceback.format_exc()
            )

        return success
