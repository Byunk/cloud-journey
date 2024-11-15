# Multi-Cluster Mesh with Kind

> This example is tested only on Linux. Additional configurations may be needed in different environments.

## Requirements

- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [yq (>=4.2.0)](https://github.com/mikefarah/yq)

## Multi Primary Clusters

Create Kind clusters.

```bash
kind create cluster --name cluster1
kind create cluster --name cluster2
```

Since Kind does not have a built-in external load balancer, we have to install a 3rd party load balancer (e.g., MetalLB) to ensure IP assignment to Gateways. In this document, we will use [MetalLB](https://metallb.universe.tf/).

Define environment variables.

```bash
export CTX_CLUSTER1=kind-cluster1
export CTX_CLUSTER2=kind-cluster2
export ISTIO_PATH=${$(which istioctl)%/bin/istioctl}
```

To provide MetalLB with an address range, inspect the Docker kind network.

```bash
$ docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' kind
172.18.0.0/16
```

Apply MetalLB manifest.

```bash
kubectl --context $CTX_CLUSTER1 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
kubectl --context $CTX_CLUSTER2 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
```

Wait until MetalLB pods are ready.

```bash
kubectl --context $CTX_CLUSTER1 wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s
kubectl --context $CTX_CLUSTER2 wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s
```

Allocate proper IP addresses for MetalLB.

```bash
cat << EOF | kubectl --context $CTX_CLUSTER1 apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ip-config
  namespace: metallb-system
spec:
  addresses:
  # Change with your subnet IP
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-config
  namespace: metallb-system
EOF
cat << EOF | kubectl --context $CTX_CLUSTER2 apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ip-config
  namespace: metallb-system
spec:
  addresses:
  # Change with your subnet IP
  - 172.18.255.150-172.18.255.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-config
  namespace: metallb-system
EOF
```

Configure a multi-primary Istio mesh. It deploys east-west gateways and exposes all services on the gateways for each cluster.

```bash
./scripts/install-multi-primary.sh --skip-secret
```

Enable endpoint discovery.

```bash
export IP1=https://$(kubectl --context $CTX_CLUSTER1 get po -l component=kube-apiserver -n kube-system -ojsonpath='{.items[*].status.hostIP}'):6443
export IP2=https://$(kubectl --context $CTX_CLUSTER2 get po -l component=kube-apiserver -n kube-system -ojsonpath='{.items[*].status.hostIP}'):6443
istioctl create-remote-secret \
    --context=$CTX_CLUSTER1 \
    --name=cluster1 \
    --server $IP1 | \
    kubectl apply -f - --context=$CTX_CLUSTER2
istioctl create-remote-secret \
    --context=$CTX_CLUSTER2 \
    --name=cluster2 \
    --server $IP2 | \
    kubectl apply -f - --context=$CTX_CLUSTER1
```

Verify Installation.

```bash
./scripts/verify-mc.sh
```

Clean up.

```bash
./scripts/cleanup-mc.sh
```

## Reference

- [Istio platform setup guide for Kind](https://istio.io/latest/docs/setup/platform-setup/kind/)
- [Install Multi Primary On Different Networks](https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/)
- [LoadBalancer for Kind](https://kind.sigs.k8s.io/docs/user/loadbalancer/)
