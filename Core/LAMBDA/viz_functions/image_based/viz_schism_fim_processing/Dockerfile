FROM public.ecr.aws/lambda/python:3.9

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY viz_classes.py ${LAMBDA_TASK_ROOT}

# Install the function's dependencies using file requirements.txt
# from your project folder.

COPY requirements.txt  .
RUN  pip3 install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

RUN mkdir -p /data/inputs
RUN mkdir -p /data/outpus
RUN mkdir -p /data/temp

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "lambda_function.lambda_handler" ]

# Removes severity vulnerabilities
RUN yum -y update