import os
import voluptuous as v

from aws_loosa.consts.paths import PIPELINES_DIR
from aws_loosa.consts import PIPELINE_MACHINE_ENV_VAR

ADDED = 'ADDED'
REMOVED = 'REMOVED'
UPDATED = 'UPDATED'
UNCHANGED = 'UNCHANGED'


def validate_multimachine_config(raw_config, config_fpath):

    machine_config = raw_config

    if PIPELINE_MACHINE_ENV_VAR in os.environ:
        PIPELINE_MACHINE = os.environ[PIPELINE_MACHINE_ENV_VAR]
        try:
            PIPELINE_MACHINE_KEY = f"MACHINE_{PIPELINE_MACHINE}"
            machine_config = raw_config[PIPELINE_MACHINE_KEY]
        except Exception:
            raise EnvironmentError(
                f'The environment variable "{PIPELINE_MACHINE_KEY}" is not a key in in the config file ({config_fpath}).'  # noqa
            )

    return machine_config


def _validate_service_spec(raw_value):
    """Validates that the service speicified is valid in syntax and otherwise

    The required syntax is "<server_name>[/<folder_name>]/<service_name>".

    Args:
        raw_value (str): the value that comes from the config file

    Returns:
        raw_value if valid. An exception is raised otherwise.
    """
    message = 'The required syntax for a service is "<server_name>[/<folder_name>]/<service_name>"'
    parts = raw_value.split('/')
    if len(parts) < 2:
        v.Invalid(message)

    server_name = parts[0]
    if server_name.startswith('$') and server_name.endswith('$'):
        varname = server_name[1:-1]
        varval = os.environ.get(varname)
        if not server_name:
            raise EnvironmentError(
                'The environment variable "{}" is not set.'.format(varname)
            )
        return_val = raw_value.replace('${}$'.format(varname), varval)
    else:
        return_val = raw_value

    return return_val


def _validate_pipeline_exists(raw_value):
    """Validates that the pipeline specified exists

    Args:
        raw_value (str): the value that comes from the config file

    Returns:
        raw_value if valid. An exception is raised otherwise.
    """
    pipelines_dir = os.path.join(PIPELINES_DIR, raw_value)
    if not os.path.isdir(pipelines_dir):
        raise IOError(
            "The directory at {} does not exist.".format(pipelines_dir)
        )

    return raw_value


CONFIG_SCHEMA = v.Schema({
    v.Optional(ADDED, default=[]): v.Schema([_validate_pipeline_exists]),
    v.Optional(UPDATED, default=[]): v.Schema([_validate_pipeline_exists]),
    v.Optional(UNCHANGED, default=[]): v.Schema([_validate_pipeline_exists]),
    v.Optional(REMOVED, default=[]): v.Schema([_validate_service_spec]),
})
