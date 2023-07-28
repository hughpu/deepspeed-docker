set -e
# sudo cp /etc/ssh/sshd_config /tmp/sshd_config && sudo sed "0,/^Port 22/s//Port 2222/" /tmp/sshd_config > tmp_sshd_config && sudo mv tmp_sshd_config /etc/ssh/sshd_config
sudo service ssh start
bash