# deepspeed-docker
This repo is modified from `https://github.com/microsoft/DeepSpeed/blob/master/docker/Dockerfile` and reference to `https://github.com/jeffra/deepspeed-kdd20`
## I. Build the image 
### 1. General build command 
```cmd
git clone https://github.com/hughpu/deepspeed-docker.git \
    && cd deepspeed-docker \
    && docker build -t deepspeed:latest -f Dockerfile .
```

### 2. Build where mirrors can be speed up by aliyun
```cmd
git clone https://github.com/hughpu/deepspeed-docker.git \
    && cd deepspeed-docker \
    && docker build --build-arg IN_CHINA="1" -t deepspeed:latest -f Dockerfile .
```

### 3. Build where mirrors can be speed up by aliyun and using proxy
```cmd
git clone https://github.com/hughpu/deepspeed-docker.git \
    && cd deepspeed-docker \
    && docker build --network host --build-arg https_proxy=http://127.0.0.1:7890 --build-arg IN_CHINA="1" --build-arg no_proxy="127.0.0.1,localhost,mirrors.aliyun.com" -f Dockerfile -t deepspeed:latest .
```  
*you can change the `-f Dockerfile` to `-f Dockerfile-cu114` to build the lower cuda version*  
----
## II. Start the image
after you build the image `deepspeed:latest` following above instructions. you can start the container with,
```cmd
bash ./start_deepspeed_container.sh
```  
The script `start_deepspeed_container.sh` got 2 volume mapping,  
1. **data path**: which is set to local `$HOME/deepspeed` and can be found inside container at `/data`. This is going to be used as workspace to put the training, inference scripts, datasets as well as output checkpoint and logs.
2. **ssh path**: which is set to local `$HOME/deepspeed_ssh` and can be found at `/home/deepspeed/.ssh` inside container. Please add all the public key `id_rsa.pub` from every node machine to `authorized_keys` file under this path of each node, to enable no password authentication between nodes, which is required by deepspeed. Please config the connection to all nodes with the file `config` under this path as well, the name of these config can be put in the `hostfile` needed by deepspeed.