import sys
import time
import os
import re
import xarray
from datetime import datetime
import arcpy

from aws_loosa.processes.base.aws_egis_process import AWSEgisPublishingProcess
from aws_loosa.consts.egis import PRIMARY_SERVER, NWM_FOLDER, VALID_TIME
from aws_loosa.products.anomaly import anomaly
from aws_loosa.utils.shared_funcs import create_service_db_tables


class AnaAnomaly(AWSEgisPublishingProcess):
    service_name = 'ana_anomaly_para'

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
        arcpy.AddMessage("Running Streamflow Anomaly v2.0:")

        day7_list = []
        day14_list = []
        day7_threshold = a_event_time - datetime.timedelta(days=7)
        day14_threshold = a_event_time - datetime.timedelta(days=14)
        latest_file = None
        latest_date = None

        # With file threshold being used, we cant assume the first half of the files are for 7 days
        for file in a_input_files:
            re_str = r"(\d{4})(\d{2})(\d{2})-analysis_assim.nwm.t(\d{2})z.analysis_assim.channel_rt.tm00.conus.nc"
            findings = re.findall(re_str, file.replace("\\", "."))[0]
            file_date = datetime.datetime(
                year=int(findings[0]), month=int(findings[1]), day=int(findings[2]), hour=int(findings[3])
            )

            if day14_threshold <= file_date <= a_event_time:
                day14_list.append(file)

            if day7_threshold <= file_date <= a_event_time:
                day7_list.append(file)

            if not latest_file:
                latest_file = file
                latest_date = file_date
            elif file_date > latest_date:
                latest_file = file
                latest_date = file_date

        ds_latest = xarray.open_dataset(latest_file)

        channel_rt_date_time = a_event_time
        self._log.info("Calculating 7 day anomaly")
        df_7_day_anomaly = anomaly(day7_list, channel_rt_date_time, anomaly_config=7)

        self._log.info("Calculating 14 day anomaly")
        df_14_day_anomaly = anomaly(day14_list, channel_rt_date_time, anomaly_config=14)

        self._log.info("Joining 7day and 14day dataframes")
        df = df_7_day_anomaly.join(df_14_day_anomaly[['average_flow_14day', 'anom_cat_14day']])

        self._log.info("Adding latest data")
        df['latest_flow'] = (ds_latest.streamflow * 35.3147).round(2)
        df['reference_time'] = latest_date.strftime("%Y-%m-%d %H:%M UTC")
        df['valid_time'] = latest_date.strftime("%Y-%m-%d %H:%M UTC")

        self._log.info("Removing unnecessary rows")
        df = df.loc[~((df['average_flow_7day'] == 0) & (df['average_flow_14day'] == 0) & (df['prcntle_95'] == 0))]
        df = df.loc[~((df['anom_cat_7day'] == 'Normal (26th - 75th)') & (df['anom_cat_14day'] == 'Normal (26th - 75th)'))]  # noqa: E501
        df = df.reset_index()

        sql_files = [os.path.join(os.path.dirname(__file__), "ana_anomaly_para.sql")]

        service_table_names = ["ana_anomaly_para"]

        create_service_db_tables(df, self.service_name, sql_files, service_table_names, self.process_event_time, past_run=self.one_off)

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
    p = AnaAnomaly(a_log_directory=log_directory, a_log_level='INFO')
    success = p.execute(forecast_date, input_files, next_forecast_date)
    exit(0 if success else 1)
