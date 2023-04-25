# -*- coding: utf-8 -*-
"""
Created on Dec 26, 2018

@author: Shawn.Crawley
"""
import logging
import logging.handlers
import os
import inspect

DEBUG = "DEBUG"
INFO = "INFO"
WARNING = "WARNING"
ERROR = "ERROR"
VALID_LEVELS = [DEBUG, INFO, WARNING, ERROR]
INVALID_LEVEL_ERROR = 'The logging level must be one of the following: {}'.format(', '.join(VALID_LEVELS))
RECOGNIZED_CLASSES = ['DataSet', 'Launcher', 'Manager', 'Watcher']


def get_logger(class_instance, a_log_directory=None, a_logstash_socket=None, a_log_level=INFO):
    """
    Sets up the logger for the provided class instance.
    """
    if not getattr(class_instance, 'name', None):
        instance_name = 'unnamed_{}'.format(class_instance.__class__.__name__.lower())
    else:
        instance_name = class_instance.name
    frame_records = inspect.stack()[1]
    calling_module = inspect.getmodulename(frame_records[1])
    # Get logger
    logger_name = '.'.join([calling_module, instance_name])
    logger = logging.getLogger(logger_name)

    # Setup handlers if not done already... remember that the logger is a singleton...
    if not logger.handlers:

        # Setup console logger
        stream_handler = logging.StreamHandler()
        logger.addHandler(stream_handler)

        # Setup file logger if args provided
        if a_log_directory is not None and os.path.isdir(a_log_directory):
            # Configure log location
            class_name = class_instance.__class__.__name__
            if class_name in RECOGNIZED_CLASSES:
                subdir_name = '%ss' % class_name.lower()
            else:
                # It must be a process that is being logged.
                subdir_name = 'processes'
            log_dir = os.path.join(a_log_directory, subdir_name)
            if not os.path.exists(log_dir):
                os.mkdir(log_dir)
            log_name = instance_name + '.log'
            log_path = os.path.join(log_dir, log_name)

            # Setup handler
            file_handler = logging.handlers.RotatingFileHandler(log_path, maxBytes=1000000, backupCount=1)
            formatter = logging.Formatter('%(asctime)s::%(name)s::%(levelname)s::%(message)s')
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)

        # Setup console logger if args provided
        if a_logstash_socket:
            from logstash_async.handler import AsynchronousLogstashHandler
            socket_parts = a_logstash_socket.split(':')
            logger.addHandler(AsynchronousLogstashHandler(socket_parts[0], int(socket_parts[1]), database_path=None))

    # Set log level if given
    log_level = getattr(logging, a_log_level.upper(), None)
    if log_level:
        logger.setLevel(log_level)
    else:
        raise ValueError(INVALID_LEVEL_ERROR)

    return logger
