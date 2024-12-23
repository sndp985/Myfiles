#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Step 1: Update the system
echo "Updating system packages..."
dnf update -y

echo "Disabling SELinux..."
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Step 2: Install required dependencies
echo "Installing required packages..."
dnf install -y epel-release
dnf install -y vim git curl wget yum-utils device-mapper-persistent-data lvm2 bash-completion

echo "Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# Step 3: Configure firewall
echo "Configuring firewall rules..."
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd --reload

# Step 4: Enable IP forwarding and configure sysctl
echo "Configuring sysctl..."
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# Step 5: Install container runtime (CRI-O)
echo "Installing CRI-O..."
OS="$(. /etc/os-release && echo $VERSION_ID)"
CRIO_VERSION="1.26"
cat <<EOF > /etc/yum.repos.d/crio.repo
[crio]
name=CRI-O Repository
baseurl=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/CentOS_9_Stream
gpgcheck=1
enabled=1
gpgkey=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/CentOS_9_Stream/repodata/repomd.xml.key
EOF

dnf install -y cri-o
systemctl enable crio
systemctl start crio

# Step 6: Add Kubernetes repository
echo "Adding Kubernetes repository..."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

echo "Installing Kubernetes components..."
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable kubelet

# Step 7: Initialize Kubernetes cluster (on the control plane node only)
echo "Initializing Kubernetes cluster..."
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: stable-1.27
controlPlaneEndpoint: "$(hostname -I | awk '{print $1}'):6443"
networking:
  podSubnet: "192.168.0.0/16"
EOF

kubeadm init --config=kubeadm-config.yaml --cri-socket /var/run/crio/crio.sock

# Step 8: Configure kubectl for the current user
echo "Setting up kubectl for the current user..."
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Step 9: Install a pod network add-on (Calico)
echo "Installing Calico pod network..."
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O
kubectl apply -f calico.yaml

# Step 10: Output join command for worker nodes
echo "Saving join command for worker nodes..."
kubeadm token create --print-join-command > /root/kubeadm_join_command.sh
chmod +x /root/kubeadm_join_command.sh

echo "Kubernetes cluster installation with Calico and CRI-O is complete."
echo "Run the following command on worker nodes to join the cluster:"
cat /root/kubeadm_join_command.sh

kubeadm join <control-plane-ip>:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash> --cri-socket /var/run/crio/crio.sock

