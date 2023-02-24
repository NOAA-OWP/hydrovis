import sys
import time
import os
import arcpy

from aws_loosa.ec2.processes.base.aws_egis_process import AWSEgisPublishingProcess
from aws_loosa.ec2.consts.egis import PRIMARY_SERVER, NWM_FOLDER, REFERENCE_TIME
from aws_loosa.ec2.products.high_water_probability import srf_high_water_probability
from aws_loosa.ec2.utils.shared_funcs import get_db_values, create_service_db_tables


class SrfHighWaterProbabilityForecast(AWSEgisPublishingProcess):
    service_name = 'srf_high_water_probability'

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

        start_time = time.time()
        arcpy.AddMessage("Running NWM 12-Hour High Water Probability Forecast:")

        lead_times = list(range(1, 13, 1))
        discard_threshold = 7

        self._log.info("Retrieving High Water Values From Viz DB")
        df_high_water_threshold = get_db_values("derived.recurrence_flows_conus", ["feature_id", "high_water_threshold"])
        df_high_water_threshold = df_high_water_threshold.set_index("feature_id")
        df_high_water_threshold = df_high_water_threshold.sort_index()

        df_probabilities = srf_high_water_probability(a_event_time, lead_times, discard_threshold, a_input_files, df_high_water_threshold)
        df_probabilities = df_probabilities.rename(columns={"Prob": "srf_prob"})

        self._log.info("Adding high water threshold, reference time, and update time to dataframe")
        df_probabilities = df_probabilities.loc[~(df_probabilities == 0).all(axis=1)]
        df_probabilities = df_probabilities.join(df_high_water_threshold)
        df_probabilities = df_probabilities.loc[~(df_probabilities['high_water_threshold'] == 0)]
        df_probabilities['reference_time'] = a_event_time.strftime("%Y-%m-%d %H:%M:%S UTC")
        df_probabilities = df_probabilities.reset_index()

        sql_files = [
            os.path.join(os.path.dirname(__file__), "srf_high_water_probability.sql"),
            os.path.join(os.path.dirname(__file__), "srf_high_water_probability_hucs.sql")
        ]

        service_table_names = ["srf_high_water_probability", "srf_high_water_probability_hucs"]

        create_service_db_tables(df_probabilities, self.service_name, sql_files, service_table_names, self.process_event_time, past_run=self.one_off)

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
    p = SrfHighWaterProbabilityForecast(a_log_directory=log_directory, a_log_level='INFO')
    success = p.execute(forecast_date, input_files, next_forecast_date)
    exit(0 if success else 1)
