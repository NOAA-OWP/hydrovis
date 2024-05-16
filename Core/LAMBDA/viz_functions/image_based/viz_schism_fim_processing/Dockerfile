FROM public.ecr.aws/amazonlinux/amazonlinux

RUN dnf -y install gcc-c++ cpp sqlite-devel libtiff cmake python3 python3-pip \
python3-setuptools python3-devel openssl-devel tcl libtiff-devel libcurl-devel \
swig libpng-devel libjpeg-turbo-devel expat-devel wget tar gzip

RUN wget https://hdf-wordpress-1.s3.amazonaws.com/wp-content/uploads/manual/HDF5/HDF5_1_14_3/src/hdf5-1.14.3.tar.gz && \
    tar zxvf hdf5-1.14.3.tar.gz && \
    cd hdf5-1.14.3 && \
    mkdir build && \
    cd build && \
    cmake .. && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . --prefix /usr;

RUN wget https://download.osgeo.org/proj/proj-9.3.1.tar.gz && \
    tar zxvf proj-9.3.1.tar.gz && \
    cd proj-9.3.1/ && \
    mkdir build && \
    cd build && \
    cmake .. && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . --prefix /usr;

RUN wget https://github.com/OSGeo/gdal/releases/download/v3.8.3/gdal-3.8.3.tar.gz && \
    tar xvzf gdal-3.8.3.tar.gz && \
    cd gdal-3.8.3/ && \
    mkdir build && \
    cd build && \
    cmake -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF -DOGR_BUILD_OPTIONAL_DRIVERS=OFF .. && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . --prefix /usr;

# END BASE IMAGE SETUP

# BEGIN SCRIPT SETUP

# Install the function's dependencies using file requirements.txt
# from your project folder.
COPY requirements.txt  .
RUN  HDF5_DIR=/usr pip3 install --no-cache-dir --no-binary fiona -r requirements.txt

# Copy function code
COPY process_schism_fim.py .
COPY viz_classes.py .

ENV PYTHONUNBUFFERED=1
ENV GDAL_DATA=/usr/share/gdal/data

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "python3", "./process_schism_fim.py" ]