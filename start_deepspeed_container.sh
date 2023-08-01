set -e
name=deepspeed
image=deepspeed

local_data_path=$HOME/deepspeed
local_ssh_path=$HOME/deepspeed_ssh
container_ssh_path=/home/deepspeed/.ssh
container_data_path=/data

echo "Starting docker container: $name with image: $image"
sudo docker run -itd --name $name \
    --net=host --shm-size="1gb" \
    --mount type=bind,source=$local_data_path,target=$container_data_path \
    --gpus all $image
sudo docker cp $local_ssh_path $name:$container_ssh_path
sudo docker exec $name bash -c "sudo chown -R deepspeed:deepspeed $container_ssh_path"
sudo docker exec $name bash -c "sudo chmod -R 777 $container_data_path"
