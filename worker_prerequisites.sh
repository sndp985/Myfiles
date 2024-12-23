set -e
dnf update -y
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
swapoff -a
sed -i '/swap/d' /etc/fstab

# Install dependencies
dnf install -y epel-release
dnf install -y vim git curl wget yum-utils bash-completion
