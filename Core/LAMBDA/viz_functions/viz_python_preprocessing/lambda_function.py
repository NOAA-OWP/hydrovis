from datetime import datetime
import os

from viz_lambda_shared_funcs import generate_file_list
from products.max_values import aggregate_max_to_file
from products.high_water_probability import run_high_water_probability
from products.rapid_onset_flooding_probability import run_rapid_onset_flooding_probability
from products.anomaly import run_anomaly

def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will take all the
        forecast steps in the NWM configuration, calculate the max streamflow for each feature and then save the
        output in S3
        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    # parse the event to get the bucket and file that kicked off the lambda
    print("Parsing event to get configuration") 
    reference_time = event['args']['reference_time']
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    step = event["step"]

    if step == "fim_config_max_file":
        config_name = event['args']['fim_config']['name']
        print(f"Getting fileset for {config_name}")
        preprocess_args = event['args']['fim_config']['preprocess']
        file_pattern = preprocess_args['file_format']
        file_step = preprocess_args['file_step']
        file_window = preprocess_args['file_window']
        fileset_bucket = preprocess_args['fileset_bucket']
        product = preprocess_args['product']
        output_file = preprocess_args['output_file']
        output_file_bucket = preprocess_args['output_file_bucket']
        
        file_step = None if file_step == "None" else file_step
        file_window = None if file_window == "None" else file_window
        
        fileset = generate_file_list(file_pattern, file_step, file_window, reference_date)
        output_file = generate_file_list(output_file, None, None, reference_date)[0]
        
        event['args']['fim_config'].pop("preprocess")
        event['args']['fim_config']['max_file_bucket'] = output_file_bucket
        event['args']['fim_config']['max_file'] = output_file
    
    else:
        fileset = event['args']['python_preprocessing']['fileset']
        fileset_bucket = event['args']['python_preprocessing']['fileset_bucket']
        product = event['args']['python_preprocessing']['product']
        output_file = event['args']['python_preprocessing']['output_file']
        output_file_bucket = event['args']['python_preprocessing']['output_file_bucket']
        
    
    print(f"Running {product} code and creating {output_file}")
    if product == "max_values":
        aggregate_max_to_file(fileset_bucket, fileset, output_file_bucket, output_file)
    elif product == "high_water_probability":
        run_high_water_probability(reference_date, fileset_bucket, fileset, output_file_bucket, output_file)
    elif product == "rapid_onset_flooding_probability":
        run_rapid_onset_flooding_probability(reference_date, fileset_bucket, fileset, output_file_bucket, output_file)
    elif product == "anomaly":
        anomaly_config = event['args']['python_preprocessing']['config']
        auth_data_bucket = os.environ['AUTH_DATA_BUCKET']
        run_anomaly(reference_date, fileset_bucket, fileset, output_file_bucket, output_file, auth_data_bucket, anomaly_config=anomaly_config)
        
    print(f"Successfully created {output_file} in {output_file_bucket}")
    
    return event['args']