import os
import sys
import tempfile
import platform
import time
from subprocess import Popen, STDOUT

from jinja2 import Template
from aws_loosa.processing_pipeline.cli import validation

FNULL = open(os.devnull, 'w')


def run_pipelines(configs_dir_or_file, executables_dir=None, external=False, window=False, manage=False,
                  log_level=None):
    """Runs one or more pipelines per the provided configs directory or file

    Args:
        configs_dir_or_file (str): absolute path to directory containing configs or a specific config file
        executables_dir (str): The absolute path to the directory where the actual executables (one per config) will
            be output
        external (bool): True if the pipelines should be executed external to the process used to call this function
        window (bool): True if the externally executed pipeline should be executed in a window, rather than in the
            background
        manage (bool): True if you want to manage all of the pipelines being ran from this process. This will allow
            you to stop all pipelines with Ctrl-c.
        log_level (str): Specify the level of logging for each pipeline. This will overwrite any value provided in
            the configs themselves.
    """
    pipeline_config_fpaths = []
    processes = []

    if os.path.isfile(configs_dir_or_file):
        if not any(configs_dir_or_file.endswith(yml) for yml in ['.yml', '.yaml']):
            raise ValueError("The file provided must be a .yml or .yaml file.")
        pipeline_config_fpaths.append(configs_dir_or_file)
    elif os.path.isdir(configs_dir_or_file):
        for config_name in os.listdir(configs_dir_or_file):
            if any(config_name.endswith(yml) for yml in ['.yml', '.yaml']):
                config_path = os.path.join(configs_dir_or_file, config_name)
                pipeline_config_fpaths.append(config_path)
    else:
        raise Exception("The provided path does not exist: {}".format(configs_dir_or_file))

    if executables_dir:
        if not os.path.isdir(executables_dir):
            raise ValueError('The executables_dir argument must be a path to an existing directory.')
    else:
        executables_dir = tempfile.mkdtemp()

    script_paths = []
    for config_fpath in pipeline_config_fpaths:
        try:
            validator = validation.PipelineConfigValidator(config_fpath)
            context = validator.get_validated_dict()
            if log_level:
                context[validation.consts.GLOBAL_LOGGING_KEY][validation.consts.GLOBAL_LOGGING_LEVEL_KEY] = f'"{log_level}"'  # noqa
                
            if window:
                context[validation.consts.REQUIRE_KEYPRESS_TO_CLOSE] = True
        except Exception as exc:
            raise Exception("ERROR ENCOUNTERED\nFile: {}\nError: {}".format(config_fpath, str(exc)))

        template_path = os.path.join(os.path.dirname(__file__), 'pipeline_executable.template')
        with open(template_path, 'r') as template_file:
            template = Template(template_file.read())

        script_path = os.path.join(executables_dir, context[validation.consts.GLOBAL_NAME_KEY] + '.py')
        with open(script_path, 'w+') as script_file:
            script_file.write(template.render(context))

        script_paths.append(script_path)

    if len(script_paths) > 1:
        external = True

    print("\nSTARTING UP PIPELINES AT THE FOLLOWING PATHS:")
    for script_path in script_paths:
        print(script_path)
        command_args = [sys.executable, script_path]
        if external:
            if window:
                if platform.system() == 'Windows':
                    from subprocess import CREATE_NEW_CONSOLE
                    process = Popen(command_args, creationflags=CREATE_NEW_CONSOLE)
                else:
                    process = Popen(' '.join(command_args), shell=True)
                processes.append(process)
            else:
                process = Popen(command_args, stdout=FNULL, stderr=STDOUT)
                processes.append(process)
        else:
            import importlib.util
            module_name = os.path.splitext(os.path.basename(script_path))[0]
            spec = importlib.util.spec_from_file_location(module_name, script_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.run()

    if manage:
        try:
            print('Press ctrl+c to terminate all pipeline processes')
            while True:
                if all(process.poll() is not None for process in processes):
                    print('All pipeline processes terminated.')
                    return
                time.sleep(5)
        except KeyboardInterrupt:
            print('Attempting to terminate pipeline processes gracefully.')
            for process in processes:
                print(("Terminating process {}...".format(process.pid)))
                process.terminate()
            time.sleep(2)
            for process in processes:
                if process.poll() is None:
                    print(("Process {} stalled. Forecfully terminating now...".format(process.pid)))
                    process.kill()
            print('Pipelines terminated successfully.')
