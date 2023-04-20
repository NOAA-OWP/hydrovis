import os
import traceback
import argparse

from aws_loosa.processing_pipeline.cli.run_pipelines import run_pipelines

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Runs one or more pipelines per the provided configuration file'
    )
    parser.add_argument(
        'config_location',
        type=str,
        help='absolute path to a single pipeline config file, or a directory containing multiple config files'
    )
    parser.add_argument(
        '-o',
        required=False,
        action='store_true',
        help='absoulte path to location where executables should be output'
    )
    parser.add_argument(
        '-v',
        required=False,
        type=str,
        choices=['INFO', 'WARNING', 'ERROR', 'DEBUG'],
        help='specify the verbosity of the output: INFO, WARNING, ERROR, DEBUG'
    )
    parser.add_argument(
        '-e',
        required=False,
        action='store_true',
        help='include if pipelines should be executed external to this console (i.e. in a subprocess)'
    )
    external_group = parser.add_argument_group('if -e is supplied')
    external_group.add_argument(
        '-w',
        required=False,
        action='store_true',
        help='include if external pipelines should spin up a new console window'
    )
    external_group.add_argument(
        '-m',
        required=False,
        action='store_true',
        help='include if external pipelines should still be managed (i.e. stopped) from this console'
    )
    args = parser.parse_args()

    configs_dir_or_file = args.config_location
    executables_dir = args.o
    external = args.e
    window = args.w
    manage = args.m
    log_level = args.v

    if not os.path.exists(configs_dir_or_file):
        parser.error("The specified config_location does not exist.")

    if not external and (window or manage):
        parser.error("The -w and -m arguments can only be included when -e is included.")

    try:
        run_pipelines(
            configs_dir_or_file, executables_dir=executables_dir, external=external,
            window=window, manage=manage, log_level=log_level)
    except Exception:
        print(traceback.format_exc())
