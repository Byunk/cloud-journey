---
title: "Kubernetes Resource Version"
excerpt: "Learn how Kubernetes uses the resourceVersion field for efficient change detection and concurrency control."
date: "2024-11-15"
---

- [Efficient Change Detection with Watch API](#efficient-change-detection-with-watch-api)
  - [Example](#example)
- [Resource Version](#resource-version)
  - [Hands-On: Verify Resource Version with `etcdctl`](#hands-on-verify-resource-version-with-etcdctl)
- [Reflector](#reflector)
- [References](#references)

When developing applications that interact with the Kubernetes API, you will notice that the `resourceVersion` field is always present in the metadata of Kubernetes resources. If you are implementing an operator or handling updates to Kubernetes objects, you might encounter the following error:

```bash
Kubectl error: the object has been modified; please apply your changes to the latest version and try again
```

This error is related to the concept of `resourceVersion`. In this article, we will discuss how Kubernetes manages resource changes and handles concurrency issues using the `resourceVersion` field.

## Efficient Change Detection with Watch API

Kubernetes clients can detect changes to resources using the watch API. To utilize the watch API, clients need the `resourceVersion` metadata, which can be obtained through a `list` or `get` API call. The `resourceVersion` is a monotonically increasing value used to track changes to resources, updating with every create, update, or delete event. If the watch API connection is interrupted, clients can resume watching from the last known `resourceVersion`.

### Example

1. Retrieve all Pods in the `test` namespace:

```txt
GET /api/v1/namespaces/test/pods
---
200 OK
Content-Type: application/json

{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {"resourceVersion": "10245"},
  "items": [...]
}
```

2. Watch for changes starting from `resourceVersion` 10245:

```txt
GET /api/v1/namespaces/test/pods?watch=1&resourceVersion=10245
---
200 OK
Transfer-Encoding: chunked
Content-Type: application/json

{
  "type": "ADDED",
  "object": {"kind": "Pod", "apiVersion": "v1", "metadata": {"resourceVersion": "10596", ...}}
}
{
  "type": "MODIFIED",
  "object": {"kind": "Pod", "apiVersion": "v1", "metadata": {"resourceVersion": "11020", ...}}
}
```

Etcd retains historical data for a limited time (typically 5 minutes). If the requested `resourceVersion` is no longer available, the server returns a `410 Gone` error. Clients must then restart the watch using a fresh `list` or `get` request.

To reduce the need for frequent list operations, Kubernetes has introduced the `BOOKMARK` event type. This event type contains only the `resourceVersion`, indicating that all changes up to that version have been processed by etcd.

```txt
GET /api/v1/namespaces/test/pods?watch=1&resourceVersion=10245&allowWatchBookmarks=true
---
200 OK
Transfer-Encoding: chunked
Content-Type: application/json

{
  "type": "ADDED",
  "object": {"kind": "Pod", "apiVersion": "v1", "metadata": {"resourceVersion": "10596", ...}}
}
{
  "type": "BOOKMARK",
  "object": {"kind": "Pod", "apiVersion": "v1", "metadata": {"resourceVersion": "12746"}}
}
```

Clients can receive `BOOKMARK` events by including `allowWatchBookmarks=true` in their watch request.

## Resource Version

The `resourceVersion` field in Kubernetes is used for [optimistic concurrency control](https://en.wikipedia.org/wiki/Optimistic_concurrency_control), tracking changes to objects, and ensuring data consistency when using the `get`, `list`, or `watch` APIs.

When a client requests a `resourceVersion` that is older than what the API server has, the server responds with a `410 Gone` status. If the requested version is not yet available, the server may return a `504 Gateway Timeout`. The `Retry-After` header may be included to indicate how long the client should wait before retrying. If a watch request is made with an unknown `resourceVersion`, the server can either wait until the version is available or return an error.

The `resourceVersion` corresponds to the `mod_revision` in etcd. In the future, Kubernetes may replace the `resourceVersion` with a more generic `Revision` field to support alternative versioning strategies.

The only reliable way to obtain the current `resourceVersion` is by querying the API server using a GET request. This value should be passed as-is in subsequent requests without modification.

For more information on `resourceVersion` behavior, refer to the Kubernetes documentation: [API Semantics](https://kubernetes.io/docs/reference/using-api/api-concepts/#resource-versions).

### Hands-On: Verify Resource Version with `etcdctl`

To verify that Kubernetes' `resourceVersion` matches the `mod_revision` in etcd, you can directly inspect etcd using `etcdctl`.

1. Create a Kubernetes cluster using `kind`:

```bash
kind create cluster --name test-cluster
```

2. Build the `etcdctl` binary and copy it to the control plane:

```bash
git clone https://github.com/etcd-io/etcd
cd etcd/etcdctl
GOOS=linux go build .

docker cp etcdctl test-cluster-control-plane:/usr/local/bin
```

3. Deploy Nginx and retrieve its `resourceVersion`:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/controllers/nginx-deployment.yaml
kubectl get deployment -ojson | grep "resourceVersion"
```

```bash
"resourceVersion": "738"
```

4. Use `etcdctl` to verify the stored value:

```bash
docker exec -it test-cluster-control-plane bash
apt-get update && apt-get install -y jq
alias e="etcdctl --endpoints 127.0.0.1:2379 --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --cacert=/etc/kubernetes/pki/etcd/ca.crt"
e get /registry/deployments/default --prefix -w json --keys-only | jq '.kvs[].key|=@base64d'
```

```bash
{
  "mod_revision": 738
}
```

The `mod_revision` in etcd matches the `resourceVersion` in Kubernetes.

## Reflector

The `Reflector` in the `client-go` library helps synchronize local caches with the Kubernetes API server using a list-then-watch approach. It handles changes efficiently by implementing the [3157-watch-list](https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3157-watch-list#proposal) mechanism.

Traditional LIST requests can be memory intensive. The proposal suggests using a streaming approach with WATCH instead of paging through etcd, reducing memory usage and load. The updated process is as follows:

1. **Initiate WATCH Request**: Use a WATCH request instead of LIST with a new query parameter.
2. **Synchronize with Resource Version (RV)**: Compute the appropriate RV and ensure the watch cache has processed changes up to this RV.
   - **Send Cached Objects**: Return currently stored objects from the watch cache.
   - **Process Updates**: Include any updates that occurred while synchronizing.
   - **Send Bookmark Event**: Indicate completion of synchronization with a bookmark event.
3. **Listen for Events**: Continue receiving events using the established WATCH request.

This approach significantly reduces memory usage and decreases the load on etcd.

For implementation details, refer to [client-go tools/cache/reflector.go](https://github.com/kubernetes/client-go/blob/main/tools/cache/reflector.go).

## References

- [Understanding Etcd Revisions and Resource Versions in Kubernetes](https://www.youtube.com/watch?v=i7RCoEjAMOo)
- [3157-watch-list Design Proposal](https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3157-watch-list)
- [Kubernetes API Conventions](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency)
