FROM nvidia/cuda:11.7.1-devel-ubuntu18.04

ENV DEBIAN_FRONTEND noninteractive

##############################################################################
# Temporary Installation Directory
##############################################################################
ENV STAGE_DIR=/tmp
RUN mkdir -p ${STAGE_DIR}

##############################################################################
# add aliyun ubuntu repo
##############################################################################
RUN cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
EOF


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
## SSH daemon port inside container cannot conflict with host OS port
###############################################################################
ENV SSH_PORT=2222
RUN cat /etc/ssh/sshd_config > ${STAGE_DIR}/sshd_config && \
        sed "0,/^#Port 22/s//Port ${SSH_PORT}/" ${STAGE_DIR}/sshd_config > /etc/ssh/sshd_config

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

##############################################################################
# Python
##############################################################################
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHON_VERSION=3.10

# RUN git clone https://github.com/pyenv/pyenv.git $HOME/.pyenv
# RUN cd $HOME/.pyenv && src/configure && make -C src
RUN ls -laFh $HOME/
RUN curl https://pyenv.run | sh
ENV DS_HOME=/home/deepspeed
RUN echo 'export PYENV_ROOT="$DS_HOME/.pyenv"' >> $DS_HOME/.bashrc
RUN echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> $DS_HOME/.bashrc
RUN echo 'eval "$(pyenv init -)"' >> $DS_HOME/.bashrc
RUN echo 'export PYENV_ROOT="$DS_HOME/.pyenv"' >> $DS_HOME/.profile
RUN echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> $DS_HOME/.profile
RUN echo 'eval "$(pyenv init -)"' >> $DS_HOME/.profile
ENV PYENV_ROOT="$DS_HOME/.pyenv"
ENV PATH="$PYENV_ROOT/bin:$PATH"
RUN eval "$(pyenv init -)"

RUN pyenv install $PYTHON_VERSION
RUN pyenv global $PYTHON_VERSION
ENV PATH="$PYENV_ROOT/versions/3.10.12/bin:$PATH"

# Print python an pip version
RUN python -V && python3 -V && pip -V
RUN pip install pyyaml
RUN pip install ipython

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
        sklearn \
        scikit-learn \
        nvidia-ml-py3 \
        mpi4py \
        cupy-cuda117



##############################################################################
# PyTorch
##############################################################################
ENV PYTORCH_VERSION=1.13.1+cu117
ENV TORCHVISION_VERSION=0.14.1
ENV TORCHAUDIO_VERSION=0.13.1
ENV TENSORBOARDX_VERSION=2.6.1
RUN pip install torch==${PYTORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} --extra-index-url https://download.pytorch.org/whl/cu117
RUN pip install tensorboardX==${TENSORBOARDX_VERSION}
RUN pip install datasets transformers peft accelerate bitsandbytes
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
# DeepSpeed
##############################################################################
RUN git clone https://github.com/microsoft/DeepSpeed.git ${STAGE_DIR}/DeepSpeed
RUN sudo chown -R deepspeed:deepspeed ${STAGE_DIR}/DeepSpeed
RUN cd ${STAGE_DIR}/DeepSpeed && \
        git checkout . && \
        git checkout master && \
        ./install.sh
RUN rm -rf ${STAGE_DIR}/DeepSpeed
RUN python -c "import deepspeed; print(deepspeed.__version__)"

WORKDIR $HOME
