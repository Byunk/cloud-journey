#!/bin/bash

# Clean up clusters $CTX_CLUSTER1 and $CTX_CLUSTER2

CURR_DIR=$(dirname "$0")
source "${CURR_DIR}/common.sh"

# Validate env variables
check.env "CTX_CLUSTER1"
check.env "CTX_CLUSTER2"

CONTEXTS=($CTX_CLUSTER1 $CTX_CLUSTER2)
for context in "${CONTEXTS[@]}"; do
	istioctl uninstall --context="${context}" -y --purge
	kubectl delete ns istio-system --context="${context}"
	kubectl delete ns sample --context="${context}"
	kubectl delete ns mirrord --context="${context}"
done

print.message "INFO" "Cleanup finished"