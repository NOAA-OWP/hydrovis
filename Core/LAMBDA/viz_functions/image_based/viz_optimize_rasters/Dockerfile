FROM ghcr.io/lambgeo/lambda-gdal:3.5 as gdal

# We use the official AWS Lambda image
FROM public.ecr.aws/lambda/python:3.9

ENV PACKAGE_PREFIX=/opt

# Bring C libs from lambgeo/lambda-gdal image
COPY --from=gdal /opt/lib/ ${PACKAGE_PREFIX}/lib/
COPY --from=gdal /opt/include/ ${PACKAGE_PREFIX}/include/
COPY --from=gdal /opt/share/ ${PACKAGE_PREFIX}/share/
COPY --from=gdal /opt/bin/ ${PACKAGE_PREFIX}/bin/

ENV \
  GDAL_DATA=${PACKAGE_PREFIX}/share/gdal \
  PROJ_LIB=${PACKAGE_PREFIX}/share/proj \
  GDAL_CONFIG=${PACKAGE_PREFIX}/bin/gdal-config \
  GEOS_CONFIG=${PACKAGE_PREFIX}/bin/geos-config \
  PATH=${PACKAGE_PREFIX}/bin:$PATH

# Copy any local files to the package
COPY lambda_function.py /var/task/lambda_function.py
COPY logger.py /var/task/logger.py
COPY OptimizeRasters.py /var/task/OptimizeRasters.py
COPY TIF_to_MRF.xml /var/task/TIF_to_MRF.xml

CMD [ "lambda_function.lambda_handler" ]