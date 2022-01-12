function parse_viz_logs(source, logGroup, message) {
    source['function_name'] = source['@log_group'].replace("/aws/lambda/", '');
    
    if (logGroup.toLowerCase().includes("viz")) {
        source['aws_process'] = "visualization"
    } else if (logGroup.toLowerCase().includes("hml")) {
        source['aws_process'] = "data_ingest"
    }
    
    try {
      var logGroup_split = logGroup.split("_")
      var hv_environment = logGroup_split[logGroup_split.length - 1].toLowerCase()
      source['hv_environment'] = hv_environment
    } catch (error) {
      console.error(error);
    }
    
    if (message.includes("REPORT RequestId")) {
        console.log(source['@log_group'])
        var myRe = /Duration: (.*) ms Billed Duration: (.*) ms Memory Size: (.*) MB Max Memory Used: (.*) MB/;
        message = message.replace(/\s+/g, ' ');
        var match_array = message.match(myRe);
        source['duration'] = parseFloat(match_array[1]);
        source['billed_duration'] = parseFloat(match_array[2]);
        source['memory_size'] = parseFloat(match_array[3]);
        source['max_memory_used'] = parseFloat(match_array[4]);
        
        source['@message'] = message
    } else if (source.aws_process == "visualization") {
        if (message.includes("Creating max flows file")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Creating max flows file for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['configuration'] = match_array[3];
            var date_string = match_array[4].slice(0,4) + "-" + match_array[4].slice(4,6) + "-" + match_array[4].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 1
    
        } else if (message.includes("Waiting for missing NWM files")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Waiting for missing NWM files (.*) for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 1
    
        } else if (message.includes("Successfully created max flows file")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Successfully created max flows file for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['configuration'] = match_array[3];
            var date_string = match_array[4].slice(0,4) + "-" + match_array[4].slice(4,6) + "-" + match_array[4].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 2
    
        } else if (message.includes("Kicking off")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Kicking off (.*) hucs for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['hucs_to_process'] = parseInt(match_array[3]);
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 3
    
        } else if (message.includes("Processing HUC")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Processing HUC (.*) for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['huc'] = match_array[3];
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 4
    
        } else if (message.includes("Successfully processed tif for HUC")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Successfully processed tif for HUC (.*) for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['huc'] = match_array[3];
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 5
    
        } else if (message.includes("Successfully processed mrf")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Successfully processed mrf for HUC (.*) for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['huc'] = match_array[3];
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 6
    
        } else if (message.includes("Copying empty raster")) {
            var myRe = /\[ELASTICSEARCH (.*)\]:  (.*) - Copying empty raster for HUC (.*) for (.*) for (.*)/;
            var match_array = message.match(myRe)
            source['log_level'] = match_array[1];
            source['huc'] = match_array[3];
            source['configuration'] = match_array[4];
            var date_string = match_array[5].slice(0,4) + "-" + match_array[5].slice(4,6) + "-" + match_array[5].slice(6,)
            source['reference_time'] = new Date(date_string);
    
            source['process_code'] = 6
        }
    }
    return source
}

module.exports = { parse_viz_logs };
