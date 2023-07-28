set -e
name=deepspeed
image=deepspeed-cu114

local_data_path=$HOME/deepspeed
local_ssh_path=$HOME/deepspeed_ssh
container_ssh_path=/home/deepspeed/.ssh
container_data_path=/data

echo "Starting docker container: $name with image: $image"
sudo docker run -itd --name $name \
    --net=host \
    --mount type=bind,source=$local_data_path,target=$container_data_path \
    --mount type=bind,source=$local_ssh_path,target=$container_ssh_path \
    --gpus all $image
sudo docker exec $name bash -c "chmod -R 777 $container_ssh_path"
sudo docker exec $name bash -c "chmod -R 777 $container_data_path"
