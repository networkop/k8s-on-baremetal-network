# Lab build instructions

1. Create a custom Simulation https://air.nvidia.com/catalog/build-your-own
2. Upload the dot and svg files as topology and diagram, select "Apply Template" in the `Advanced` section of the menu.
3. Enable SSH and connect to the `oob-mgmt-server` 
4. Connect to the `netq-ts` and generate a bootstrap token

```
$ ssh netq-ts
cumulus@netq-ts:~$ sudo -i
root@netq-ts:~# kubeadm  token create --print-join-command
kubeadm join 192.168.200.250:6443 --token x9whjh.gfrl6rli1n70sn2j     --discovery-token-ca-cert-hash sha256:1f17e2a9460ec49c23e04ab7e16b28f1727e19ba89271c65c32546c8db7d401d
```

5. SSH into `leaf1` and install and configure kubelet

```
sudo -i
systemctl enable --now docker@mgmt
# to test run
docker run hello-world

# following https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

CNI_VERSION="v0.8.2"
ARCH="amd64"
sudo mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz

DOWNLOAD_DIR=/usr/local/bin
sudo mkdir -p $DOWNLOAD_DIR

# make sure release is the same as on the controller node
RELEASE=v1.16.2
ARCH="amd64"
cd $DOWNLOAD_DIR
sudo curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet,kubectl}
sudo chmod +x {kubeadm,kubelet,kubectl}

# download systemd files and update kubelet to execute from mgmt VRF
RELEASE_VERSION="v0.4.0"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service
sudo mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" \
| sed "s:/usr/bin:ip vrf exec mgmt ${DOWNLOAD_DIR}:g" \
| sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# set the node-ip
apt install jq -y
nodeip=$(ip -j addr show dev eth0 | jq -r '.[0].addr_info[0].local')
echo "KUBELET_EXTRA_ARGS=\"--node-ip=${nodeip}\"" > /etc/default/kubelet

# hard-coding FRR to always run bgpd
sed -i s'/bgpd=no/bgpd=yes/' /etc/frr/daemons
systemctl restart frr
```

6. Use the join command printed at step #4 to join the new node `leaf1`

```
kubeadm join 192.168.200.250:6443 --token x9whjh.gfrl6rli1n70sn2j     --discovery-token-ca-cert-hash sha256:1f17e2a9460ec49c23e04ab7e16b28f1727e19ba89271c65c32546c8db7d401d --ignore-preflight-errors=all
```

7. Repeate steps 5-6 for `leaf2` with the only exception

Enable nvued process

```
systemctl enable --now nvued
```

8. SSH into `spine` and install and configure kubelet (same as leaf but without mgmt vrf)

```
sudo -i

# following https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

CNI_VERSION="v0.8.2"
ARCH="amd64"
sudo mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz

DOWNLOAD_DIR=/usr/local/bin
sudo mkdir -p $DOWNLOAD_DIR

# make sure release is the same as on the controller node
RELEASE=v1.16.2
ARCH="amd64"
cd $DOWNLOAD_DIR
sudo curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet,kubectl}
sudo chmod +x {kubeadm,kubelet,kubectl}


# download systemd files and DO NOT update kubelet to execute from mgmt VRF
RELEASE_VERSION="v0.4.0"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service
sudo mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" \
| sed "s:/usr/bin:${DOWNLOAD_DIR}:g" \
| sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

apt install jq -y

nodeip=$(ip -j addr show dev eth0 | jq -r '.[1].addr_info[0].local')

echo "KUBELET_EXTRA_ARGS=\"--node-ip=${nodeip}\"" > /etc/default/kubelet

```

9. Join the `spine` node

```
kubeadm join 192.168.200.250:6443 --token x9whjh.gfrl6rli1n70sn2j     --discovery-token-ca-cert-hash sha256:1f17e2a9460ec49c23e04ab7e16b28f1727e19ba89271c65c32546c8db7d401d --ignore-preflight-errors=all
```

10. From `netq-ts` check that all nodes are `Ready`

```
root@netq-ts:~# kubectl get nodes
NAME      STATUS   ROLES    AGE     VERSION
leaf1     Ready    <none>   7m9s    v1.16.2
leaf2     Ready    <none>   5m29s   v1.16.2
netq-ts   Ready    master   166d    v1.16.2
spine     Ready    <none>   50s     v1.16.2
```

10. Taint the new node to prevent Pods from running on it

```
kubectl taint node leaf1 baremetal=network:NoExecute
kubectl taint node leaf2 baremetal=network:NoExecute
kubectl taint node spine baremetal=network:NoExecute
```

11. Set up the environment (optional)

```
curl -sSL https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens | sudo tee /usr/local/bin/kubens
chmod +x /usr/local/bin/kubens

echo "alias k=kubectl" >> ~/.bashrc
```

12. Update any existing daemonsets that may tolerate the `NoExecute` taint

```

# edit any existing daemonsets to not ignore NoExecute
kubens kube-system
# remove ` - operator: Exists` from kube-proxy ds
k -n kube-system edit ds kube-proxy
tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - operator: Exists # remote this line
# the same for calico
k -n kube-system edit ds calico-node
tolerations:
      - effect: NoSchedule
        operator: Exists
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoExecute # remote this line
        operator: Exists # and this line


```

At this point, no Pods should be running on "network" nodes

```
root@netq-ts:~# k get pod -A -owide | grep leaf
root@netq-ts:~# k get pod -A -owide | grep spine
```

14. Cleanup

On all nodes run:
```
history -c
```

On the `oob-mgmt-server run:
```
passwd cumulus CumulusLinux!
sudo passwd --expire cumulus
```

15. Clone the Sim

Shut off the current sim and paste this in your browser replacing <id> with the current sim ID
```
https://air.nvidia.com/api/v1/simulation/autoprovision/?simulation_id=<id>
```

<!--
https://air.nvidia.com/api/v1/simulation/autoprovision/?simulation_id=86f05a32-896f-41bd-a6c9-3cdf2567d9e7
-->