#######################
# === All Systems === #
#######################
# Ensure system is fully patched
sudo yum -y makecache fast
sudo yum -y update

# Disable swap
sudo swapoff -a

# comment out swap mount in /etc/fstab
sudo vi /etc/fstab

# Disable default iptables configuration as it will break kubernetes services (API, coredns, etc...)
sudo sh -c "cp /etc/sysconfig/iptables /etc/sysconfig/iptables.ORIG && iptables --flush && iptables --flush && iptables-save > /etc/sysconfig/iptables"
sudo systemctl restart iptables.service

# Load/Enable br_netfilter kernel module and make persistent
sudo modprobe br_netfilter
sudo sh -c "echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables"
sudo sh -c "echo '1' > /proc/sys/net/bridge/bridge-nf-call-ip6tables"
sudo sh -c "echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf"
sudo sh -c "echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.conf"

# Install dependencies for docker-ce
sudo yum -y install yum-utils device-mapper-persistent-data lvm2

# Add the docker-ce repository
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Add the Kubernetes Repository
sudo sh -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF'

# Update yum cache after adding repository
sudo yum -y makecache fast

# Install latest supported docker runtime (18.06 is the latest runtime supported by Kubernetes v1.13.2)
sudo yum -y install docker-ce-18.06.1.ce

# Install Kubernetes
sudo yum -y install kubelet kubeadm kubectl

# Enable kubectl bash-completion
sudo yum -y install bash-completion
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc

# Enable docker and kubelet services
sudo systemctl enable docker.service
sudo systemctl enable kubelet.service

# reboot
sudo reboot

# Check what cgroup driver that docker is using
sudo docker info | grep -i cgroup

# Add the cgroup driver from the previous step to the kublet config as an extra argument
sudo sed -i "s/^\(KUBELET_EXTRA_ARGS=\)\(.*\)$/\1\"--cgroup-driver=$(sudo docker info | grep -i cgroup | cut -d" " -f3)\2\"/" /etc/sysconfig/kubelet



#######################
# === Master Only === #
#######################
# Initialize the Kubernetes master using the public IP address of the master as the apiserver-advertise-address. Set the pod-network-cidr to the cidr address used in the network overlay (flannel, weave, etc...) configuration.
curl -s https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml | grep -E '"Network": "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}"' | cut -d'"' -f4
sudo kubeadm init --apiserver-advertise-address=${master_ip_address} --pod-network-cidr=${NETWORK_OVERLAY_CIDR_NET}

# Copy the cluster configuration to the regular users home directory
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy the Flannel Network Overlay
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# check the readiness of nodes
kubectl get nodes

# check that coredns, apiserver, etcd, and flannel pods are running
kubectl get pods --all-namespaces

# List k8s bootstrap tokens
sudo kubeadm token list

# Generate a new k8s bootstrap token !ONLY! if all other tokens have expired
sudo kubeadm token create

# Decode the Discovery Token CA Cert Hash
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'



########################
# === Workers Only === #
########################
# Join worker node to k8s cluster using the token and discovery-token-ca-cert-hash from master
sudo kubeadm join ${MASTER_HOSTNAME}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH}



#########################
# === Reset Cluster === #
#########################
# Reset Cluster
sudo kubeadm reset

# Clean up iptable remnants
sudo sh -c "iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X"

# Clean up network overlay remnants
sudo ip link delete cni0
sudo ip link delete flannel.1



###########################
# === Troubleshooting === #
###########################
# If exposed deployment intermittently responds with "no route to host", run the following on the troublesome host
sudo sh -c "iptables --flush && iptables --flush" && sudo systemctl restart docker.service

# If the previous command fixes the intermittent problem, there is most likely an iptables rule preventing incoming traffic to the ingress controller

sudo sh -c "cp /etc/sysconfig/iptables /etc/sysconfig/iptables.ORIG && iptables --flush && iptables --flush && iptables-save > /etc/sysconfig/iptables"
sudo systemctl restart iptables.service
sudo systemctl restart docker.service


