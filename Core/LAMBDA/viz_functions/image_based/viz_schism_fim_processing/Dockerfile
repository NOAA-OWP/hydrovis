FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal AS alinux

ARG MINIFORGE_NAME=Miniforge3
ARG MINIFORGE_VERSION=24.9.2-0

ENV CONDA_DIR=/opt/conda
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH=${CONDA_DIR}/bin:${PATH}
# Prevent Python from writing bytecode files
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent python from buffering stdout
ENV PYTHONUNBUFFERED=1

# Installs some basic system tools to get conda installed
RUN dnf update && \
    dnf -y install wget bzip2 ca-certificates findutils && \
    dnf clean all

# Install and setup conda
RUN wget --no-hsts --quiet https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_NAME}-${MINIFORGE_VERSION}-Linux-$(uname -m).sh -O /tmp/miniforge.sh && \
    /bin/bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && \
    rm /tmp/miniforge.sh && \
    conda clean --tarballs --index-cache --packages --yes && \
    conda clean -afy && \
    find ${CONDA_DIR} -regex '^.*\(__pycache__\|\.py[co]\)$' -delete && \
    find ${CONDA_DIR} -follow -type f -name '*.a' -delete && \
    rm -rf ${CONDA_DIR}/share/man ${CONDA_DIR}/man ${CONDA_DIR}/share/doc

# END BASE IMAGE SETUP

# BEGIN SCRIPT SETUP

# Install the function's dependencies using file requirements.txt
# from your project folder.
WORKDIR /code
#COPY conda-linux-64.lock  .
# Create conda environment for hydrovis
RUN --mount=type=bind,source=conda-linux-64.lock,target=/tmp/conda-linux-64.lock \
    conda create -y -p /HV --file /tmp/conda-linux-64.lock && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate /HV" >> ~/.bashrc && \
    conda clean -afy && \
    find /HV -regex '^.*\(__pycache__\|\.py[co]\)$' -delete && \
    find /HV -follow -type f -name '*.a' -delete

# Copy function code
COPY viz_classes.py \
    process_schism_fim.py \
    ./

ENTRYPOINT [ "conda", "run", "--no-capture-output", "-p", "/HV" ]
CMD [ \
    "python", "process_schism_fim.py" \
]
