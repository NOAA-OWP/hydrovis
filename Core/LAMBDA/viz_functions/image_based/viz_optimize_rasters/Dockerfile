FROM ghcr.io/lambgeo/lambda-gdal:3.6-python3.9

RUN python -m pip install gdal==$(gdal-config --version)

# Copy any local files to the package
COPY lambda_function.py /var/task/lambda_function.py
COPY logger.py /var/task/logger.py
COPY OptimizeRasters.py /var/task/OptimizeRasters.py
COPY TIF_to_MRF.xml /var/task/TIF_to_MRF.xml

ENTRYPOINT [ "/lambda-entrypoint.sh" ]
CMD [ "lambda_function.lambda_handler" ]