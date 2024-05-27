#!/bin/bash

# 版本
version=1.23.0

# 准备基础环境
check() {
  systemctl stop firewalld
  systemctl disable firewalld
  sed -i "s/^SELINUX=*/SELINUX=disabled/g" /etc/selinux/config
  setenforce 0
  swapoff -a
  sed -i 's/.*swap.*/#&/g' /etc/fstab
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system
}

# 安装docker
install_docker() {
  yum -y install wget
  if [ "$?" -ne 0 ]
  then
      echo -e "\033[31m ========== ERROR: 安装wget失败，请检查yum ========== \033[0m"
      exit 1
  fi
  wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
   yum install -y https://download.docker.com/linux/fedora/30/x86_64/stable/Packages/containerd.io-1.2.6-3.3.fc30.x86_64.rpm
  yum -y install docker-ce
  if [ "$?" -ne 0 ]
  then
      echo -e "\033[31m ========== ERROR: 安装docker失败，请检查yum ========== \033[0m"
      exit 1
  fi

  # 启动docker,并设置docker开机自启
  systemctl start docker
  systemctl enable docker

  # 配置加速，并设置驱动
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://6ze43vnb.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

  # 加载daemon并重启docker
  systemctl daemon-reload
  systemctl restart docker
}

# 安装kubernetes
install_kubernetes() {
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  yum install -y kubelet-${version} kubeadm-${version} kubectl-${version}
  systemctl enable kubelet
}

# 主函数
main() {
  check
  install_docker
  install_kubernetes

  if [ "$1" -eq 1 ]
  then
    echo -e "\033[32m  ===== 开始进行初始化 ===== \033[0m"

    kubeadm init  --apiserver-advertise-address=$2 --image-repository registry.aliyuncs.com/google_containers --kubernetes-version v${version} --control-plane-endpoint ${2}:6443 --service-cidr=10.1.0.0/16 --pod-network-cidr=10.244.0.0/16
    if [ "$?" -ne 0 ]
    then
      echo -e "\033[31m ===== ERROR: 初始化失败 ===== \033[0m"
      exit 1
    fi

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

  else 
      echo -e "\033[32m ===== kubeadm,kubectl,kubelet安装完成 =====\033[0m"
  fi
}

case $1 in
1)
  if [ "$1" -eq 1 ]
  then
    if [ -z "$2" ]
    then
    echo "===== 用法 $0 <1> <your ip> ====="
    echo "===== 1代表master身份,需要再后面传入IP,如果不加1则为node身份 ====="
    fi
  fi
  main "$1" "$2"
  ;;
2)
  main "$1"
  ;;
*)
  echo "===== 用法 $0 <1|2> <your ip> ====="
  echo "===== 1代表master身份,需要再后面传入IP ====="
  ;;
esac 
