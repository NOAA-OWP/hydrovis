#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
#
# United States Department of Commerce
# NOAA (National Oceanic Atmospheric Administration)
# National Weather Service
# Office of Water Prediction
#
# Author:
#     Shawn Crawley (creator)
#
'''
This script is used to delete all of the services per the list of services under
the ADDED, UPDATED, OR UNCHANGED section within the provided services config file.
'''
import argparse
import os
import yaml

from aws_loosa.processing_pipeline.cli.run_pipelines import run_pipelines
from aws_loosa.consts.paths import PIPELINES_DIR
from aws_loosa.consts import TOTAL_PROCESSES_ENV_VAR

from aws_loosa.deploy.validate_config import CONFIG_SCHEMA, ADDED, UPDATED, UNCHANGED, validate_multimachine_config


def start_pipelines(config_fpath, manage=False):
    """Start a pipeline for each service specified in the provided config file

    Args:
        config_fpath (str): Absolute path to the services config file
    """

    with open(config_fpath, 'r') as cfg:
        raw_content = cfg.read()

    config = yaml.load(raw_content, Loader=yaml.FullLoader)
    machine_config = validate_multimachine_config(config, config_fpath)
    validated_config = CONFIG_SCHEMA(machine_config)
    pipelines = []
    if ADDED in validated_config:
        pipelines += validated_config[ADDED]
    if UPDATED in validated_config:
        pipelines += validated_config[UPDATED]
    if UNCHANGED in validated_config:
        pipelines += validated_config[UNCHANGED]

    total_processes = len(pipelines)
    os.environ[TOTAL_PROCESSES_ENV_VAR] = str(total_processes)

    for pipeline in pipelines:
        pipeline_config = os.path.join(PIPELINES_DIR, pipeline, 'pipeline.yml')
        run_pipelines(pipeline_config, external=True)

    if manage:
        while True:
            pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Starts one or more pipelines per the provided services configuration file'
    )
    parser.add_argument(
        'config_location', type=str,
        help='absolute path to a single pipeline config file, or a directory containing multiple config files'
    )
    parser.add_argument(
        '-m', required=False, action='store_true',
        help='include if external pipelines should still be managed (i.e. stopped) from this console'
    )
    args = parser.parse_args()

    start_pipelines(args.config_location, manage=args.m)
