FROM nvidia/cuda:11.7.1-cudnn8-devel-ubuntu18.04

ENV DEBIAN_FRONTEND noninteractive

##############################################################################
# Temporary Installation Directory
##############################################################################
ENV STAGE_DIR=/tmp
ENV HOME=/root
RUN mkdir -p ${STAGE_DIR}
RUN test -n "$HTTPS_PROXY" || export HTTPS_PROXY="$https_proxy"

##############################################################################
# add aliyun ubuntu repo
##############################################################################
RUN test -n "$IN_CHINA" && echo \
"deb https://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse\n\
deb-src https://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse\n\
deb https://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse\n\
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse\n\
deb https://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse\n\
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse\n\
deb https://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse\n\
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse" > /etc/apt/sources.list


##############################################################################
# Installation/Basic Utilities
##############################################################################
RUN apt-get update && \
        apt-get install -y --no-install-recommends \
        software-properties-common build-essential autotools-dev \
        nfs-common pdsh \
        cmake g++ gcc \
        curl wget vim tmux emacs less unzip \
        htop iftop iotop ca-certificates openssh-client openssh-server \
        rsync iputils-ping net-tools sudo \
        llvm-9-dev haveged ninja-build

##############################################################################
# Installation Latest Git
##############################################################################
RUN add-apt-repository ppa:git-core/ppa -y && \
        apt-get update && \
        apt-get install -y git && \
        git --version
RUN test -n "${HTTPS_PROXY}" && \
    git config --global https.proxy ${HTTPS_PROXY}

##############################################################################
# Client Liveness & Uncomment Port 22 for SSH Daemon
##############################################################################
# Keep SSH client alive from server side
RUN echo "ClientAliveInterval 30" >> /etc/ssh/sshd_config
RUN cp /etc/ssh/sshd_config ${STAGE_DIR}/sshd_config && \
        sed "0,/^#Port 22/s//Port 22/" ${STAGE_DIR}/sshd_config > /etc/ssh/sshd_config

##############################################################################
# Mellanox OFED
##############################################################################
ENV MLNX_OFED_VERSION=4.6-1.0.1.1
RUN apt-get install -y libnuma-dev
RUN cd ${STAGE_DIR} && \
        wget -q -O - http://www.mellanox.com/downloads/ofed/MLNX_OFED-${MLNX_OFED_VERSION}/MLNX_OFED_LINUX-${MLNX_OFED_VERSION}-ubuntu18.04-x86_64.tgz | tar xzf - && \
        cd MLNX_OFED_LINUX-${MLNX_OFED_VERSION}-ubuntu18.04-x86_64 && \
        ./mlnxofedinstall --user-space-only --without-fw-update --all -q && \
        cd ${STAGE_DIR} && \
        rm -rf ${STAGE_DIR}/MLNX_OFED_LINUX-${MLNX_OFED_VERSION}-ubuntu18.04-x86_64*

##############################################################################
# nv_peer_mem
##############################################################################
ENV NV_PEER_MEM_VERSION=1.1
ENV NV_PEER_MEM_TAG=1.1-0
RUN mkdir -p ${STAGE_DIR} && \
        git clone https://github.com/Mellanox/nv_peer_memory.git --branch ${NV_PEER_MEM_TAG} ${STAGE_DIR}/nv_peer_memory && \
        cd ${STAGE_DIR}/nv_peer_memory && \
        ./build_module.sh && \
        cd ${STAGE_DIR} && \
        tar xzf ${STAGE_DIR}/nvidia-peer-memory_${NV_PEER_MEM_VERSION}.orig.tar.gz && \
        cd ${STAGE_DIR}/nvidia-peer-memory-${NV_PEER_MEM_VERSION} && \
        apt-get update && \
        apt-get install -y dkms && \
        dpkg-buildpackage -us -uc && \
        dpkg -i ${STAGE_DIR}/nvidia-peer-memory_${NV_PEER_MEM_TAG}_all.deb

##############################################################################
# OPENMPI
##############################################################################
ENV OPENMPI_BASEVERSION=4.0
ENV OPENMPI_VERSION=${OPENMPI_BASEVERSION}.1
RUN cd ${STAGE_DIR} && \
        wget -q -O - https://download.open-mpi.org/release/open-mpi/v${OPENMPI_BASEVERSION}/openmpi-${OPENMPI_VERSION}.tar.gz | tar xzf - && \
        cd openmpi-${OPENMPI_VERSION} && \
        ./configure --prefix=/usr/local/openmpi-${OPENMPI_VERSION} && \
        make -j"$(nproc)" install && \
        ln -s /usr/local/openmpi-${OPENMPI_VERSION} /usr/local/mpi && \
        # Sanity check:
        test -f /usr/local/mpi/bin/mpic++ && \
        cd ${STAGE_DIR} && \
        rm -r ${STAGE_DIR}/openmpi-${OPENMPI_VERSION}
ENV PATH=/usr/local/mpi/bin:${PATH} \
        LD_LIBRARY_PATH=/usr/local/lib:/usr/local/mpi/lib:/usr/local/mpi/lib64:${LD_LIBRARY_PATH}
# Create a wrapper for OpenMPI to allow running as root by default
RUN mv /usr/local/mpi/bin/mpirun /usr/local/mpi/bin/mpirun.real && \
        echo '#!/bin/bash' > /usr/local/mpi/bin/mpirun && \
        echo 'mpirun.real --allow-run-as-root --prefix /usr/local/mpi "$@"' >> /usr/local/mpi/bin/mpirun && \
        chmod a+x /usr/local/mpi/bin/mpirun

##############################################################################
# Some Packages
##############################################################################
RUN apt-get update && \
        apt-get install -y --no-install-recommends \
        libsndfile-dev \
        libcupti-dev \
        libjpeg-dev \
        libpng-dev \
        screen \
        libaio-dev
RUN apt-get install -y python3 python3-dev
RUN apt-get install -y libssl-dev zlib1g-dev \
	libbz2-dev libreadline-dev libsqlite3-dev \
	libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

##############################################################################
# Python
##############################################################################
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHON_VERSION=3.10

RUN wget -O /tmp/Python-3.10.6.tgz https://www.python.org/ftp/python/3.10.6/Python-3.10.6.tgz
RUN mkdir -p /tmp/Python-3.10.6
RUN tar -xf /tmp/Python-3.10.6.tgz -C /tmp
RUN apt-get install -y libncurses5-dev libgdbm-dev libnss3-dev
RUN cd /tmp/Python-3.10.6 && ./configure --enable-optimizations
RUN cd /tmp/Python-3.10.6 && make && make altinstall
RUN update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.10 9
RUN update-alternatives --install /usr/bin/python python /usr/local/bin/python3.10 9
RUN update-alternatives --set python3 /usr/local/bin/python3.10
RUN update-alternatives --set python /usr/local/bin/python3.10
RUN update-alternatives --install /usr/bin/pip3 pip3 /usr/local/bin/pip3.10 9
RUN update-alternatives --install /usr/bin/pip pip /usr/local/bin/pip3.10 9
RUN update-alternatives --set pip3 /usr/local/bin/pip3.10
RUN update-alternatives --set pip /usr/local/bin/pip3.10
RUN ln -s /usr/local/bin/pip3.10 /usr/local/bin/pip
RUN ln -s /usr/local/bin/pip3.10 /usr/local/bin/pip3
RUN ln -s /usr/local/bin/python3.10 /usr/local/bin/python
RUN ln -s /usr/local/bin/python3.10 /usr/local/bin/python3

# Print python an pip version
RUN python -V && python3 -V && pip -V
RUN pip install pyyaml
RUN pip install ipython

# change pip source
RUN mkdir -p $HOME/.pip
RUN test -n "$IN_CHINA" && echo \
"[global]\n\
index-url = http://mirrors.aliyun.com/pypi/simple/\n\
[install]\n\
trusted-host=mirrors.aliyun.com" > $HOME/.pip/pip.conf


##############################################################################
# TensorFlow
##############################################################################
ENV TENSORFLOW_VERSION=2.12.*
RUN pip install tensorflow==${TENSORFLOW_VERSION}
RUN pip install psutil \
        yappi \
        cffi \
        ipdb \
        pandas \
        matplotlib
RUN pip install py3nvml \
        pyarrow \
        graphviz \
        astor \
        boto3 \
        tqdm \
        sentencepiece \
        msgpack \
        requests
RUN pip install sphinx \
        sphinx_rtd_theme \
        scipy \
        numpy \
        scikit-learn \
        nvidia-ml-py3 \
        mpi4py \
        cupy-cuda117


##############################################################################
# PyTorch
##############################################################################
ENV TENSORBOARDX_VERSION=2.6.1
RUN pip install torch torchvision torchaudio
RUN pip install tensorboardX==${TENSORBOARDX_VERSION}
RUN pip install datasets transformers peft accelerate bitsandbytes-cuda117
RUN pip install lightning==2.0.2
RUN pip install ninja numexpr jsonargparse 'jsonargparse[signatures]'
RUN pip install lm-dataformat ftfy tokenizers wandb

##############################################################################
# PyYAML build issue
# https://stackoverflow.com/a/53926898
##############################################################################
# RUN rm -rf /usr/lib/python3/dist-packages/yaml && \
#         rm -rf /usr/lib/python3/dist-packages/PyYAML-*
##############################################################################
## SSH daemon port inside container cannot conflict with host OS port
###############################################################################
ENV SSH_PORT=2222
RUN cat /etc/ssh/sshd_config > ${STAGE_DIR}/sshd_config && \
        sed "0,/^Port 22/s//Port ${SSH_PORT}/" ${STAGE_DIR}/sshd_config > /etc/ssh/sshd_config


##############################################################################
## Add deepspeed user
###############################################################################
# Add a deepspeed user with user id 8877
#RUN useradd --create-home --uid 8877 deepspeed
RUN useradd --create-home --uid 1000 --shell /bin/bash deepspeed
RUN usermod -aG sudo deepspeed
RUN echo "deepspeed ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# # Change to non-root privilege
USER deepspeed
ENV HOME=/home/deepspeed

RUN test -n "$IN_CHINA" && mkdir -p $HOME/.pip \
    && sudo cp /root/.pip/pip.conf $HOME/.pip/pip.conf \
    && sudo chown deepspeed:deepspeed $HOME/.pip/pip.conf
RUN test -n "${HTTPS_PROXY}" && \
    git config --global https.proxy ${HTTPS_PROXY}


##############################################################################
# DeepSpeed
##############################################################################
RUN git clone https://github.com/microsoft/DeepSpeed.git ${STAGE_DIR}/DeepSpeed
RUN sudo chown -R deepspeed:deepspeed ${STAGE_DIR}/DeepSpeed
RUN cd ${STAGE_DIR}/DeepSpeed && \
        git checkout . && \
        git checkout master && \
        ./install.sh --pip_sudo

RUN rm -rf ${STAGE_DIR}/DeepSpeed
RUN pip cache purge
RUN sudo -H -u root pip cache purge
RUN sudo apt-get clean
RUN sudo rm -rf /tmp/Python*
RUN sudo rm -rf /var/lib/apt/lists/*

RUN python -c "import deepspeed; print(deepspeed.__version__)"
COPY ./entry_deepspeed.sh $HOME/

WORKDIR $HOME
ENTRYPOINT bash entry_deepspeed.sh