#! /bin/bash

# Install multi-primary mesh on different network (network1, network2)
# Refer to https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/
#
# Usage:
# export CTX_CLUSTER1="cluster1"
# export CTX_CLUSTER2="cluster2"
# ./install-multi-primary.sh
# 

set -e

CURR_DIR=$(dirname "$0")
source "${CURR_DIR}/common.sh"

check.command "kubectl"

# Validate env variables
check.env "CTX_CLUSTER1"
check.env "CTX_CLUSTER2"

CONTEXTS=($CTX_CLUSTER1 $CTX_CLUSTER2)
SKIP_SECRET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-secret)
      SKIP_SECRET=true
      shift 1
      ;;
    *)
      print.message "ERROR" "Unknown parameter $1"
      exit 1
      ;;
  esac
done

function create_namespace {
  for i in $(seq 1 2); do
    local context=${CONTEXTS[$i - 1]}
    local network="network$i"
    local cluster="cluster$i"
    local mesh="mesh1"
    cat << EOF | kubectl --context $context apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
  labels:
    topology.istio.io/network: $network
EOF
  done
}

function install_istio {
  for i in $(seq 1 2); do
    local context=${CONTEXTS[$i - 1]}
    local network="network$i"
    local cluster="cluster$i"
    local mesh="mesh1"
    cat << EOF | istioctl install --context="${context}" -f - -y
---
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: $mesh
      multiCluster:
        clusterName: $cluster
      network: $network
      logging:
        level: default:debug
EOF
  # install east-west gateway
  cat << EOF | istioctl --context="${context}" install -y -f -
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  revision: ""
  profile: empty
  components:
    ingressGateways:
    - name: istio-eastwestgateway
      label:
        istio: eastwestgateway
        app: istio-eastwestgateway
        topology.istio.io/network: $network
      enabled: true
      k8s:
        env:
        # traffic through this gateway should be routed inside the network
        - name: ISTIO_META_REQUESTED_NETWORK_VIEW
          value: $network
        service:
          ports:
          - name: status-port
            port: 15021
            targetPort: 15021
          - name: tls
            port: 15443
            targetPort: 15443
          - name: tls-istiod
            port: 15012
            targetPort: 15012
          - name: tls-webhook
            port: 15017
            targetPort: 15017
  values:
    gateways:
      istio-ingressgateway:
        injectionTemplate: gateway
    global:
      network: $network
EOF
  # Expose services
  cat << EOF | kubectl --context="${context}" apply -n istio-system -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: cross-network-gateway
spec:
  selector:
    istio: eastwestgateway
  servers:
  - port:
      number: 15443
      name: tls
      protocol: TLS
    tls:
      mode: AUTO_PASSTHROUGH
    hosts:
    - "*.local"
EOF
  done
}

function create_remote_secret {
  istioctl create-remote-secret \
    --context="${CTX_CLUSTER1}" \
    --name=cluster1 \
    | kubectl apply -f - --context="${CTX_CLUSTER2}"
  istioctl create-remote-secret \
    --context="${CTX_CLUSTER2}" \
    --name=cluster2 \
    --server="http://mirrord-proxy-agent.mirrord:8443" \
    | kubectl apply -f - --context="${CTX_CLUSTER1}"
}

function main {
  create_namespace
  source "${CURR_DIR}/configure-trust.sh"
  install_istio
  if $SKIP_SECRET; then
    create_remote_secret
  fi
}

main