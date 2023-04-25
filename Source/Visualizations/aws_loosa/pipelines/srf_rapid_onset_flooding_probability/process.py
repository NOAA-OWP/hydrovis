import sys
import time
import os
import arcpy

from aws_loosa.processes.base.aws_egis_process import AWSEgisPublishingProcess
from aws_loosa.consts.egis import PRIMARY_SERVER, NWM_FOLDER, REFERENCE_TIME
from aws_loosa.products.rapid_onset_probability import srf_rapid_onset_probability
from aws_loosa.utils.shared_funcs import create_service_db_tables


class SrfRapidOnsetFloodingProbability(AWSEgisPublishingProcess):
    service_name = 'srf_rapid_onset_flooding_probability'

    def _process(self, a_event_time, a_input_files, a_output_location, *args, **kwargs):
        """
        Override this method to execute the post processing steps.

        Args:
            a_event_time(datetime.datetime): the datetime associated with the current processing run.
            a_input_files(list): a list of absolute paths to the required input files.
            a_output_location(str): the location to be used to write output from the process.

        Returns:
            bool: True if processing finished successfully and False if it encountered an error.
        """

        # Execute script
        start_time = time.time()
        arcpy.AddMessage("Running Short-Range Rapid Onset Flooding Probability:")

        percent_change_threshold = 100
        high_water_hour_threshold = 6
        stream_reaches_at_or_below = 4

        arcpy.AddMessage("Processing Files")
        df_rofp = srf_rapid_onset_probability(
            a_event_time, a_input_files, percent_change_threshold, high_water_hour_threshold, stream_reaches_at_or_below
        )
        df_rofp['reference_time'] = a_event_time.strftime("%Y-%m-%d %H:%M:%S UTC")

        sql_files = [
            os.path.join(os.path.dirname(__file__), "srf_rapid_onset_flooding_probability.sql"),
            os.path.join(os.path.dirname(__file__), "srf_rapid_onset_flooding_probability_hucs.sql")
        ]

        service_table_names = ["srf_rapid_onset_flooding_probability", "srf_rapid_onset_flooding_probability_hucs"]

        create_service_db_tables(df_rofp, self.service_name, sql_files, service_table_names, self.process_event_time, past_run=self.one_off)

        arcpy.AddMessage("All done!")
        seconds = time.time() - start_time
        minutes = str(round((seconds / 60.0), 2))
        arcpy.AddMessage("Run time: " + minutes + " minutes")


if __name__ == '__main__':
    # Get Args
    forecast_date = sys.argv[1]
    input_files = sys.argv[2]
    log_directory = sys.argv[3]
    next_forecast_date = sys.argv[4]

    # Create process
    p = SrfRapidOnsetFloodingProbability(a_log_directory=log_directory, a_log_level='INFO')
    success = p.execute(forecast_date, input_files, next_forecast_date)
    exit(0 if success else 1)
