#!/bin/bash

# Verify a multi-cluster mesh setup
# Refer to https://istio.io/latest/docs/setup/install/multicluster/verify/
#
# It is successful if Hello version is toggled between v1 and v2
# For example:
#   Hello version: v2, instance: helloworld-v2-758dd55874-6x4t8
#   Hello version: v1, instance: helloworld-v1-86f77cd7bd-cpxhv
#   ...
#
# Usage:
# export CTX_CLUSTER1="cluster1"
# export CTX_CLUSTER2="cluster2"
# ./verify-mc-installation.sh
#

set -e

CURR_DIR=$(dirname "$0")
source "${CURR_DIR}/common.sh"

check.env "CTX_CLUSTER1"
check.env "CTX_CLUSTER2"

REQUEST=15

while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--request)
      REQUEST="$2"
      shift 2
      ;;
    *)
      print.message "ERROR" "Unknown parameter $1"
      exit 1
      ;;
  esac
done

CONTEXTS=($CTX_CLUSTER1 $CTX_CLUSTER2)
for i in $(seq 1 2); do
    context=${CONTEXTS[$i - 1]}
    network="network$i"
    cluster="cluster$i"
    cat << EOF | kubectl --context $context apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: sample
  labels:
    istio-injection: enabled
    topology.istio.io/network: $network
    topology.istio.io/cluster: $cluster
EOF
    # Deploy the HelloWorld Service
    cat << EOF | kubectl --context $context apply -f - -n sample
apiVersion: v1
kind: Service
metadata:
  name: helloworld
  labels:
    app: helloworld
    service: helloworld
spec:
  ports:
  - port: 5000
    name: http
  selector:
    app: helloworld
EOF
    # Deploy HelloWolrd
    if [[ $context == "${CONTEXTS[0]}" ]]; then
        version="v1"
    else
        version="v2"
    fi
    cat << EOF | kubectl --context $context apply -f - -n sample
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-$version
  labels:
    app: helloworld
    version: $version
spec:
  replicas: 1
  selector:
    matchLabels:
      app: helloworld
      version: $version
  template:
    metadata:
      labels:
        app: helloworld
        version: $version
    spec:
      containers:
      - name: helloworld
        image: docker.io/istio/examples-helloworld-$version
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent #Always
        ports:
        - containerPort: 5000
EOF

    # Deploy Sleep
    cat << EOF | kubectl --context $context apply -f - -n sample
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sleep
---
apiVersion: v1
kind: Service
metadata:
  name: sleep
  labels:
    app: sleep
    service: sleep
spec:
  ports:
  - port: 80
    name: http
  selector:
    app: sleep
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sleep
  template:
    metadata:
      labels:
        app: sleep
    spec:
      terminationGracePeriodSeconds: 0
      serviceAccountName: sleep
      containers:
      - name: sleep
        image: curlimages/curl
        command: ["/bin/sleep", "infinity"]
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - mountPath: /etc/sleep/tls
          name: secret-volume
      volumes:
      - name: secret-volume
        secret:
          secretName: sleep-secret
          optional: true
EOF
done

echo "Wait to ensure all the pods are successfully running."
for context in "${CONTEXTS[@]}"; do
kubectl --context ${context} wait -n sample \
        --for=condition=ready pod \
        --selector=app=helloworld \
        --timeout=90s
done

for context in "${CONTEXTS[@]}"; do
    print.message "INFO" "Send $REQUEST requests from $context"
    for I in $(seq 1 "$REQUEST")
    do 
        kubectl exec --context="${context}" -n sample -c sleep "$(kubectl get pod --context="${context}" -n sample -l app=sleep -o jsonpath='{.items[0].metadata.name}')" -- curl -sS helloworld.sample:5000/hello
    done
done
