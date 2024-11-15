#!/bin/bash
set -e

CURR_DIR=$(dirname "$0")
source "${CURR_DIR}/common.sh"

check.env "CTX_CLUSTER1"
check.env "CTX_CLUSTER2"
check.env "ISTIO_PATH"

mkdir -p "$CURR_DIR/../certs"
pushd "$CURR_DIR/../certs"

make -f "$ISTIO_PATH/tools/certs/Makefile.selfsigned.mk" root-ca
make -f "$ISTIO_PATH/tools/certs/Makefile.selfsigned.mk" cluster1-cacerts
make -f "$ISTIO_PATH/tools/certs/Makefile.selfsigned.mk" cluster2-cacerts

kubectl create secret generic cacerts -n istio-system \
      --from-file=cluster1/ca-cert.pem \
      --from-file=cluster1/ca-key.pem \
      --from-file=cluster1/root-cert.pem \
      --from-file=cluster1/cert-chain.pem \
      --dry-run=client -o yaml \
      | kubectl --context=$CTX_CLUSTER1 apply -f -

kubectl create secret generic cacerts -n istio-system \
      --from-file=cluster2/ca-cert.pem \
      --from-file=cluster2/ca-key.pem \
      --from-file=cluster2/root-cert.pem \
      --from-file=cluster2/cert-chain.pem \
      --dry-run=client -o yaml \
      | kubectl --context=$CTX_CLUSTER2 apply -f -

popd

echo "Configuration finished"