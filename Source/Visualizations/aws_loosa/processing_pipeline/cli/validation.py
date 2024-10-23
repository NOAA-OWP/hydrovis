import datetime
import isodate
import os
import re
from platform import system as system_name
from subprocess import call as system_call
import tempfile

import yaml
import voluptuous as v

from aws_loosa.processing_pipeline.utils.extract_list_from_file import extract_list_from_file
from aws_loosa.processing_pipeline.watcher import Watcher
from aws_loosa.processing_pipeline.dataset import DataSet
from aws_loosa.processing_pipeline.cli import consts


class PipelineConfigValidator(object):
    def __init__(self, config_fpath, ignore_envs=False):
        if not any(config_fpath.endswith(x) for x in ['.yml', '.yaml', '.YML', '.YAML']):
            raise ValueError("The file provided to the PipelineConfigManager constructor is not a YAML file.")

        with open(config_fpath, 'r') as config_file:
            raw_content = config_file.read()
        self._config_fpath = os.path.abspath(config_fpath)
        self._raw_config_dict = yaml.load(raw_content, Loader=yaml.FullLoader)
        self._pipeline_name = self._get_pipeline_name()
        self._previous_dataset_count = 0
        self._current_dataset_count = 0
        self._subset_count = 0
        self._ignore_envs = ignore_envs

    @classmethod
    def _raise(cls, message):
        raise v.Invalid(message)

    def _get_pipeline_name(self):
        if consts.GLOBAL_NAME_KEY in self._raw_config_dict:
            name = self._raw_config_dict[consts.GLOBAL_NAME_KEY]
        else:
            name = 'pipeline{}'.format(datetime.datetime.now().strftime('%Y%m%d%H%M%S'))

        return name

    def _generate_dataset_name(self):
        if consts.DATASET_KEY in self._raw_config_dict:
            return self._pipeline_name
        else:
            self._previous_dataset_count = self._current_dataset_count
            self._current_dataset_count += 1
            return "{}_dataset{}".format(self._pipeline_name, self._current_dataset_count)

    def _generate_subset_name(self):
        if consts.DATASET_KEY in self._raw_config_dict:
            dataset_name = self._pipeline_name
        else:
            dataset_name = "{}_dataset{}".format(self._pipeline_name, self._current_dataset_count)

        if self._previous_dataset_count != self._current_dataset_count:
            self._subset_count = 0
        self._subset_count += 1

        return "{}_subset{}".format(dataset_name, self._subset_count)

    def _substitute_variables_in_string(self, string):
        if type(string) is not str:
            if string is None:
                return None
            self._raise("A string is required")
        matches = set(re.findall('[$][^$]+[$]', string))
        new_string = string
        if not matches and '$' in string:
            print('WARNING: A "$" was found in the following string, but it did not have a matching opening or '
                  f'closing "$":\n{string}\nIf you were trying to reference a variable, please add the missing "$".')
        for match in matches:
            var = match[1:-1]
            env_var = os.getenv(var)
            if env_var is not None:
                new_string = new_string.replace(match, env_var)
            elif consts.GLOBAL_VARS_KEY in self._raw_config_dict and var in self._raw_config_dict[consts.GLOBAL_VARS_KEY]:  # noqa
                script_var = self._raw_config_dict[consts.GLOBAL_VARS_KEY][var]
                new_string = new_string.replace(match, script_var)
            else:
                if self._ignore_envs:
                    print(f'WARNGING: The variable "{var}" was not found in the system envrionment variables nor in '
                          'the global->vars definition of the pipeline YAML file')
                else:
                    self._raise('The variable "{var}" was not found in the system envrionment variables nor in the '
                                'global->vars definition of the pipeline YAML file')

        substr1 = '../' if '../' in new_string else '..\\'
        parent_dir_count = new_string.count(substr1)
        if parent_dir_count > 0:
            abs_path = os.path.dirname(self._config_fpath)
            for count in range(0, parent_dir_count):
                abs_path = os.path.dirname(abs_path)
            new_string = os.path.join(abs_path, new_string.split(substr1*parent_dir_count)[1])

        substr2 = './' if './' in new_string else '.\\'
        if substr2 in new_string:
            new_string = os.path.join(os.path.dirname(self._config_fpath), new_string.split(substr2)[1])

        return os.path.join(new_string)

    def validate_boolean(self, val):
        if not isinstance(val, bool):
            self._raise('value must be boolean')

        return repr(val)

    def validate_string(self, val):
        new_val = self._substitute_variables_in_string(val)

        return repr(new_val)

    def validate_variable(self, possible_string):
        if type(possible_string) is not str:
            return possible_string

        mod_string = self._substitute_variables_in_string(possible_string)
        parts = mod_string.split('?')
        num_parts = len(parts)

        if not os.path.isfile(parts[0]):
            new_val = possible_string
        else:
            fpath = parts[0]
            col = 0
            delimeter = ','
            header = True
            if num_parts == 2:
                params = parts[1].split('&')
                if len(params) > 3:
                    self._raise('Only three parameters are recognized: "col", "delimeter", and "header"')
                for param in params:
                    try:
                        p_key, p_val = param.split('=')
                        if p_key == 'col':
                            col = int(p_val)
                        elif p_key == 'delimeter':
                            delimeter = p_val
                        elif p_key == 'header':
                            header = p_val.lower() == 'true'
                        else:
                            raise ValueError()
                    except ValueError:
                        self._raise('The parameters following the csv path must be formatted as follows: '
                                    '/path/to/file.csv?col=1&header=true&delimeter=\t')

            new_val = extract_list_from_file(fpath, col, delimeter, header)

        return new_val

    def validate_file_path(self, fpath):
        if not fpath:
            return repr(None)
        mod_fpath = self._substitute_variables_in_string(fpath)
        if not os.path.isfile(mod_fpath):
            self._raise('The file "{}" does not exist'.format(mod_fpath))

        return repr(mod_fpath)

    def validate_process_arg(self, argument):
        if type(argument) is str:
            return self._substitute_variables_in_string(argument)
        else:
            return repr(argument)

    def validate_duration(self, duration):
        if not duration:
            valid_duration = None
        elif duration.lower() == consts.NONE:
            valid_duration = datetime.timedelta(0)
        elif duration == consts.ALL:
            valid_duration = Watcher.CACHE_ALL
        else:
            try:
                valid_duration = isodate.parse_duration(duration)
            except isodate.ISO8601Error:
                self._raise("{} does not match the ISO8601 Duration format".format(duration))

        return repr(valid_duration)

    def validate_logstash_host(self, raw_host):
        """
        Returns unmodified host if host (str) responds to a ping request.
        Remember that a host may not respond to a ping (ICMP) request even if the host name is valid.
        """
        host = raw_host
        if host is not None:
            host = self._substitute_variables_in_string(raw_host)
            if '://' in host:
                protocol = host.split('://')[0]
                self._raise(f'The host parameter should not contain the protocol (i.e. "{protocol}"). Please specify '
                            'the protocol with the "protocol" parameter.')

            mod_host = host.split(':')[0] if ':' in host else host

            # Ping command count option as function of OS
            param = '-n' if system_name().lower() == 'windows' else '-c'

            # Building the command. Ex: "ping -c 1 google.com"
            command = ['ping', param, '1', str(mod_host)]

            # Pinging
            with open(os.devnull, 'wb') as f:
                if system_call(command, stdout=f, stderr=f) != 0:
                    print(f"WARNING: The host {host} could not be pinged and thus may be invalid or unreachable on "
                          "the current network.")

        return repr(host)

    @classmethod
    def get_datetime_from_relative_time(cls, val):
        import operator
        new_val = None
        if '+' in val:
            parts = val.split('+')
            operation = operator.add
        elif '-' in val:
            parts = val.split('-')
            operation = operator.sub
        try:
            raw_start = parts[0].strip().lower()
            raw_duration = parts[1].strip().upper()

            if raw_start not in ['', 'now']:
                raise ValueError()

            duration = isodate.parse_duration(raw_duration)
            new_val = operation(datetime.datetime.now(datetime.UTC), duration)
        except Exception:
            cls._raise('When using relative times, follow the format: [now]+|-<iso 8601 duration>')

        return new_val

    def validate_start_time(self, val):
        try:
            if not val:
                new_val = None
            elif type(val) is datetime.datetime:
                new_val = val
            elif type(val) is str:
                mod_val = self._substitute_variables_in_string(val)
                if mod_val.lower() == consts.LATEST or mod_val.lower() == consts.NONE:
                    new_val = None
                elif mod_val.lower().strip() == consts.NOW:
                    new_val = datetime.datetime.now(datetime.UTC)
                elif any(x in mod_val for x in ['+', '-']):
                    new_val = self.get_datetime_from_relative_time(mod_val)
                else:
                    raise Exception()
            else:
                raise Exception()
        except Exception:
            self._raise('The "end" value must be either a valid keyword (i.e. "latest" or "none"), a relative time of '
                       'the form [now]+|-<iso 8601 duration>, or a datetime string in the format YYYY-mm-ddTHH:MM:SSZ')

        return repr(new_val)

    def validate_end_time(self, val):
        try:
            if not val:
                new_val = None
            elif type(val) is datetime.datetime:
                new_val = val
            elif type(val) is str:
                mod_val = self._substitute_variables_in_string(val)
                if not mod_val or mod_val.lower() == consts.NONE:
                    new_val = None
                elif mod_val.lower().strip() == consts.LATEST:
                    new_val = Watcher.END_AT_LATEST
                elif any(x in mod_val for x in ['+', '-']):
                    new_val = self.get_datetime_from_relative_time(mod_val)
                else:
                    raise Exception()
            else:
                raise Exception()
        except Exception:
            self._raise('The "end" value must be either a valid keyword (i.e. "latest" or "none"), a relative time of '
                       'the form [now]+|-<iso 8601 duration>, or a datetime string in the format YYYY-mm-ddTHH:MM:SSZ')

        return repr(new_val)

    def validate_seed_times(self, vals):
        if not vals:
            return None

        valid_times = []
        for val in vals:
            new_val = val
            if type(val) == datetime.datetime:
                new_val = val
            elif not val or val.lower() == consts.NONE:
                new_val = None
            elif val.lower() == consts.LATEST:
                new_val = Watcher.END_AT_LATEST
            else:
                self._raise('The "seed_time" value must be either a valid keyword (i.e. "latest" or "none") or a '
                            'datetime string in the format YYYY-mm-ddTHH:MM:SSZ')

            valid_times.append(repr(new_val))

        return valid_times

    def validate_repeat_ref_time(self, val):
        try:
            if not val or str(val).lower() == consts.NOW or str(val).lower() == consts.NONE:
                return repr(None)
            else:
                if type(val) is int:
                    if val > 23:
                        return repr((datetime.datetime(1, 1, 1) + datetime.timedelta(seconds=val)).time())
                    else:
                        val = '{}:00:00'.format(str(val))
                return repr(datetime.datetime.strptime(val, '%H:%M:%S').time())
        except Exception as exc:
            self._raise(str(exc))

    def validate_skip(self, val):
        if val is None:
            new_val = val
        elif isinstance(val, list):
            new_val = []
            for item in val:
                try:
                    dt_obj = isodate.parse_datetime(item)
                    new_val.append(dt_obj)
                except Exception:
                    try:
                        dt_obj = isodate.parse_time(item)
                        new_val.append(dt_obj)
                    except Exception:
                        self._raise("The skip parameter must be a list of valid ISO 8601 Times or Datetimes or the "
                                    "path to a python script.")
        elif isinstance(val, str):
            return self.validate_file_path(val)
        else:
            self._raise("The skip parameter must be a list of valid ISO 8601 Times or Datetimes or the path to "
                        "a python script.")

        return repr(new_val)

    def validate_uris(self, val):
        validated_uris = {}
        if val is None:
            return repr(None)
        if isinstance(val, str):
            validated_uris[consts.URI_PRIMARY] = repr([self._substitute_variables_in_string(val)])
            validated_uris[consts.URI_FAILOVER] = repr([self._substitute_variables_in_string(val)])
        elif isinstance(val, list):
            main_uris_list = []
            failover_uris_list = []
            for uri in val:
                if isinstance(uri, dict):
                    if consts.URI_PRIMARY not in uri or consts.URI_FAILOVER not in uri:
                        self._raise(f'{consts.URI_PRIMARY} and {consts.URI_FAILOVER} key/value pairs must be included '
                                    'in uris for failover capability')
                    main_uris_list.append(self._substitute_variables_in_string(uri[consts.URI_PRIMARY]))
                    failover_uris_list.append(self._substitute_variables_in_string(uri[consts.URI_FAILOVER]))
                else:
                    main_uris_list.append(self._substitute_variables_in_string(uri))
                    failover_uris_list.append(self._substitute_variables_in_string(uri))
            validated_uris[consts.URI_PRIMARY] = repr(main_uris_list)
            validated_uris[consts.URI_FAILOVER] = repr(failover_uris_list)
        else:
            self._raise('The "uris" value must either be a single string or a list of strings')

        return validated_uris

    def validate_log_level(self, val):
        if val not in consts.VALID_LEVELS:
            self._raise(consts.INVALID_LEVEL_ERROR)

        return repr(val)

    def validate_transfer_dataset(self, val):
        if not val:
            valid_val = DataSet.TRANSFER_ALL
        else:
            if val not in DataSet.TRANSFER_OPTIONS:
                try_val = self._substitute_variables_in_string(val)
                if not os.path.exists(try_val):
                    self._raise(DataSet.INVALID_TRANSFER_OPTION_ERROR)
                else:
                    valid_val = try_val
            else:
                valid_val = val

        return repr(valid_val)

    def validate_transfers_dir(self, val):
        if not val:
            return repr(None)
        else:
            return self.validate_string(val)

    def validate_credentials(self, raw_val):
        validated_credentials = {}
        valid_keys = [
            consts.DATASET_CREDENTIALS_ACCESS_KEY, consts.DATASET_CREDENTIALS_SECRET_KEY,
            consts.DATASET_CREDENTIALS_TOKEN_KEY
        ]
        if not isinstance(raw_val, dict):
            self._raise("The credentials attribute must be specified in dictionary form, with access_key, access_id, "
                        "or token as the only valid keys")
        if raw_val:
            validated_credentials = {}
            for key, val in raw_val.items():
                if key not in valid_keys:
                    self._raise("The only valid keys of the credentials attribute are: access_key, access_id "
                                "and/or token.")
                if key in [consts.DATASET_CREDENTIALS_ACCESS_KEY, consts.DATASET_CREDENTIALS_SECRET_KEY]:
                    validated_credentials[key] = self._substitute_variables_in_string(val)
                else:
                    validated_credentials[key] = dict()
                    for token_key, token_val in val.items():
                        if isinstance(token_val, dict):
                            validated_credentials[key][token_key] = dict()
                            for token_key2, token_val2 in token_val.items():
                                sub_vars = self._substitute_variables_in_string(token_val2)
                                validated_credentials[key][token_key][token_key2] = sub_vars
                        else:
                            validated_credentials[key][token_key] = self._substitute_variables_in_string(token_val)

        return repr(validated_credentials)

    def validate_transfer_format(self, raw_val):
        valid_keys = ['find', 'replace']
        if isinstance(raw_val, dict):
            for key in raw_val:
                if key not in valid_keys:
                    self._raise(f'The "{key}" key is not allowed in the transfer_format specification.')
            return raw_val
        else:
            return repr(raw_val)

    def validate_acceptable_uris_missing(self, raw_val):
        if not raw_val:
            return repr(None)

        if isinstance(raw_val, int):
            return raw_val

        if isinstance(raw_val, str):
            if raw_val[-1] == "%":
                percentage = float(raw_val.replace("%", ""))
                if not 0 <= percentage <= 100:
                    self._raise('Percentages must be between 0 and 100.')
                return repr(raw_val)

        if isinstance(raw_val, list) and any(isinstance(val, int) for val in raw_val):
            self._raise('If using a list, values must be a string. A single integer value or percentage may also be '
                        'used.')

        return self.validate_uris(raw_val)

    def get_validated_dict(self):
        # SCHEMAS
        _name_schema = v.Schema(lambda x: re.sub('[ ]+', '_', x.lower()))
        write_space = os.path.join(os.getenv("PIPELINE_WORKSPACE") or tempfile.mkdtemp())

        _globals_schema = v.Schema({
            v.Optional(
                consts.GLOBAL_NAME_KEY,
                default=self._pipeline_name
            ): _name_schema,

            v.Optional(
                consts.GLOBAL_LOGGING_KEY,
                default={
                    consts.GLOBAL_LOGGING_LEVEL_KEY: consts.INFO,
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY: os.path.join(write_space, 'logs')
                }
            ): v.Schema({
                v.Optional(
                    consts.GLOBAL_LOGGING_LEVEL_KEY,
                    default=consts.INFO
                ): v.Schema(self.validate_log_level),
                v.Optional(
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY,
                    default=os.path.join(write_space, 'logs')
                ): v.Schema(self.validate_string),
                v.Optional(
                    consts.GLOBAL_LOGGING_LOGSTASH_KEY,
                    default=os.getenv("LOGSTASH_SOCKET")
                ): v.Schema(self.validate_logstash_host),
            }),
            v.Optional(
                consts.GLOBAL_SWITCHBOARDS_KEY,
                default=os.path.join(write_space, 'switchboards', self._pipeline_name)
            ): v.Schema(self.validate_string),
            v.Optional(
                consts.GLOBAL_TRANSFERS_KEY,
                default=os.path.join(write_space, 'transfers')
            ): v.Schema(self.validate_string),
            v.Optional(consts.GLOBAL_VARS_KEY): v.Schema({v.Extra: str}),
            v.Optional(consts.GLOBAL_REQ_ENVS_KEY): v.Schema([str]),
            v.Optional(consts.DATASET_START_KEY, default=None): v.Schema(self.validate_start_time),
            v.Optional(consts.DATASET_STOP_KEY, default=None): v.Schema(self.validate_end_time),
            v.Optional(consts.DATASET_SEED_TIMES_KEY, default=None): v.Schema(self.validate_seed_times)
        })
        globals_dict = dict(self._raw_config_dict)

        if consts.DATASETS_KEY in globals_dict:
            del globals_dict[consts.DATASETS_KEY]
        if consts.DATASET_KEY in globals_dict:
            del globals_dict[consts.DATASET_KEY]
        if consts.PROCESSES_KEY in globals_dict:
            del globals_dict[consts.PROCESSES_KEY]
        if consts.PROCESS_KEY in globals_dict:
            del globals_dict[consts.PROCESS_KEY]

        self.globals = _globals_schema(globals_dict)

        _process_schema = {
            v.Required(consts.PROCESS_SCRIPT_KEY): v.Schema(self.validate_file_path),
            v.Optional(consts.PROCESS_ARGS_KEY, default=[]): v.Schema([self.validate_process_arg]),
            v.Optional(consts.PROCESS_INTERPRETER_KEY, default=None): v.Schema(self.validate_file_path),
            v.Optional(consts.PROCESS_INTERVAL_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.PROCESS_REPEAT_REF_TIME_KEY, default=None): v.Schema(self.validate_repeat_ref_time),
            v.Optional(consts.PROCESS_TIMEOUT_KEY, default=None): v.Schema(self.validate_duration)
        }
        _dataset_list_schema = {
            v.Required(consts.DATASET_URIS_KEY): v.Schema(self.validate_uris),
            v.Required(consts.DATASET_REPEAT_KEY): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_NAME_KEY, default=self._generate_dataset_name): _name_schema,
            v.Optional(consts.DATASET_VARIABLES_KEY, default={}): v.Schema({v.Extra: self.validate_variable}),
            v.Optional(consts.DATASET_WINDOW_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_WINDOW_STEP_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_REPEAT_REF_TIME_KEY, default=None): v.Schema(self.validate_repeat_ref_time),
            v.Optional(consts.DATASET_DELAY_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_EXPIRATION_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_EXPECT_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_SKIP_KEY, default=None): v.Schema(self.validate_skip),
            v.Optional(consts.DATASET_PING_KEY, default='PT3M'): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_FALLBACK_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_CACHE_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_MAX_SERVICE_LAG_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_TRANSFER_KEY, default=consts.ALL): v.Schema(self.validate_transfer_dataset),
            v.Optional(consts.DATASET_CLEAN_KEY, default=False): v.Schema(self.validate_boolean),
            v.Optional(
                consts.DATASET_TRANSFERS_KEY,
                default=eval(self.globals[consts.GLOBAL_TRANSFERS_KEY])
            ): v.Schema(self.validate_transfers_dir),

            v.Optional(consts.DATASET_TRANSFER_FORMAT_KEY, default=None): v.Schema(self.validate_transfer_format),
            v.Optional(
                consts.DATASET_CONCURRENT_TRANSFERS_KEY,
                default=Watcher.DEFAULT_MAX_CONCURRENT_TRANSFERS
            ): v.All(int, v.Range(min=1, max=100)),
            v.Optional(consts.DATASET_START_KEY, default=None): v.Schema(self.validate_start_time),
            v.Optional(consts.DATASET_STOP_KEY, default=None): v.Schema(self.validate_end_time),
            v.Optional(consts.DATASET_SEED_TIMES_KEY, default=None): v.Schema(self.validate_seed_times),
            v.Optional(consts.DATASET_CREDENTIALS_KEY, default={}): v.Schema(self.validate_credentials),
            v.Optional(
                consts.DATASET_ACCEPTABLE_URIS_MISSING_KEY,
                default={}
            ): v.Schema(self.validate_acceptable_uris_missing),
            v.Optional(consts.PROCESSES_KEY, default=[]): v.Schema([_process_schema]),
            v.Optional(consts.DATASET_SUBSETS_KEY, default=[]): v.Schema([{
                v.Optional(consts.DATASET_URIS_KEY, default=None): v.Schema(self.validate_uris),
                v.Optional(consts.DATASET_WINDOW_KEY, default=None): v.Schema(self.validate_duration),
                v.Optional(consts.DATASET_VARIABLES_KEY, default={}): v.Schema({v.Extra: self.validate_variable}),
                v.Optional(consts.PROCESSES_KEY, default=[]): v.Schema([_process_schema])
            }])
        }
        _dataset_single_schema = v.Schema({
            v.Required(consts.DATASET_URIS_KEY): v.Schema(self.validate_uris),
            v.Optional(consts.DATASET_REPEAT_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_NAME_KEY, default=self._generate_dataset_name): _name_schema,
            v.Optional(consts.DATASET_VARIABLES_KEY, default={}): v.Schema({v.Extra: self.validate_variable}),
            v.Optional(consts.DATASET_WINDOW_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_WINDOW_STEP_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_REPEAT_REF_TIME_KEY, default=None): v.Schema(self.validate_repeat_ref_time),
            v.Optional(consts.DATASET_DELAY_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_EXPIRATION_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_EXPECT_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_SKIP_KEY, default=None): v.Schema(self.validate_skip),
            v.Optional(consts.DATASET_PING_KEY, default='PT3M'): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_FETCH_TIMEOUT_KEY, default=60): v.Schema(int),
            v.Optional(consts.DATASET_FALLBACK_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_CACHE_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_MAX_SERVICE_LAG_KEY, default=None): v.Schema(self.validate_duration),
            v.Optional(consts.DATASET_TRANSFER_KEY, default=consts.ALL): v.Schema(self.validate_transfer_dataset),
            v.Optional(consts.DATASET_CLEAN_KEY, default=False): v.Schema(self.validate_boolean),
            v.Optional(consts.DATASET_TRANSFER_FORMAT_KEY, default=None): v.Schema(self.validate_transfer_format),
            v.Optional(consts.DATASET_CREDENTIALS_KEY, default={}): v.Schema(self.validate_credentials),

            v.Optional(
                consts.DATASET_TRANSFERS_KEY,
                default=eval(self.globals[consts.GLOBAL_TRANSFERS_KEY])
            ): v.Schema(self.validate_transfers_dir),

            v.Optional(
                consts.DATASET_CONCURRENT_TRANSFERS_KEY,
                default=Watcher.DEFAULT_MAX_CONCURRENT_TRANSFERS
            ): v.All(int, v.Range(min=1, max=100)),

            v.Optional(
                consts.DATASET_ACCEPTABLE_URIS_MISSING_KEY, default=None
            ): v.Schema(self.validate_acceptable_uris_missing)
        })

        _old_config_schema = v.Schema({
            v.Optional(
                consts.GLOBAL_NAME_KEY,
                default=self._pipeline_name
            ): _name_schema,

            v.Optional(
                consts.GLOBAL_LOGGING_KEY,
                default={
                    consts.GLOBAL_LOGGING_LEVEL_KEY: consts.INFO,
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY: os.path.join(write_space, 'logs')
                }
            ): v.Schema({
                v.Optional(
                    consts.GLOBAL_LOGGING_LEVEL_KEY,
                    default=consts.INFO
                ): v.Schema(self.validate_log_level),

                v.Optional(
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY,
                    default=os.path.join(write_space, 'logs')
                ): v.Schema(self.validate_string),

                v.Optional(
                    consts.GLOBAL_LOGGING_LOGSTASH_KEY,
                    default=os.getenv("LOGSTASH_SOCKET")
                ): v.Schema(self.validate_logstash_host),
            }),

            v.Optional(
                consts.GLOBAL_SWITCHBOARDS_KEY,
                default=os.path.join(write_space, 'switchboards', self._pipeline_name)
            ): v.Schema(self.validate_string),

            v.Optional(
                consts.GLOBAL_TRANSFERS_KEY,
                default=os.path.join(write_space, 'transfers')
            ): v.Schema(self.validate_string),

            v.Optional(consts.GLOBAL_VARS_KEY): v.Schema({v.Extra: str}),
            v.Optional(consts.GLOBAL_REQ_ENVS_KEY): v.Schema([str]),
            v.Required(consts.DATASETS_KEY): v.Schema([_dataset_list_schema])
        })

        _new_config_schema = v.Schema({
            v.Optional(
                consts.GLOBAL_NAME_KEY,
                default=self._pipeline_name
            ): _name_schema,

            v.Optional(
                consts.GLOBAL_LOGGING_KEY,
                default={
                    consts.GLOBAL_LOGGING_LEVEL_KEY: consts.INFO,
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY: os.path.join(write_space, 'logs')
                }
            ): v.Schema({
                v.Optional(
                    consts.GLOBAL_LOGGING_LEVEL_KEY,
                    default=consts.INFO
                ): v.Schema(self.validate_log_level),

                v.Optional(
                    consts.GLOBAL_LOGGING_DIRECTORY_KEY,
                    default=os.path.join(write_space, 'logs')
                ): v.Schema(self.validate_string),

                v.Optional(
                    consts.GLOBAL_LOGGING_LOGSTASH_KEY,
                    default=os.getenv("LOGSTASH_SOCKET")
                ): v.Schema(self.validate_logstash_host),
            }),

            v.Optional(
                consts.GLOBAL_SWITCHBOARDS_KEY,
                default=os.path.join(write_space, 'switchboards', self._pipeline_name)
            ): v.Schema(self.validate_string),

            v.Optional(
                consts.GLOBAL_TRANSFERS_KEY,
                default=os.path.join(write_space, 'transfers')
            ): v.Schema(self.validate_string),

            v.Optional(consts.GLOBAL_VARS_KEY): v.Schema({v.Extra: str}),
            v.Optional(consts.GLOBAL_REQ_ENVS_KEY): v.Schema([str]),
            v.Optional(consts.DATASET_START_KEY, default=None): v.Schema(self.validate_start_time),
            v.Optional(consts.DATASET_STOP_KEY, default=None): v.Schema(self.validate_end_time),
            v.Optional(consts.DATASET_SEED_TIMES_KEY, default=None): v.Schema(self.validate_seed_times),
            v.Required(consts.DATASET_KEY): v.Schema(_dataset_single_schema),
            v.Optional(consts.PROCESS_KEY): v.Schema(_process_schema)
        })
        try:
            validated = _old_config_schema(self._raw_config_dict)
        except Exception as e1:
            try:
                validated = _new_config_schema(self._raw_config_dict)
            except Exception as e2:
                raise ValueError(
                    "Depending on which configuration you are going for, "
                    "one of the following is wrong:\n"
                    "Combined Dataset/Process config: {}\n"
                    "Separated Process/Process config: {}".format(e1, e2)
                )

        return validated
