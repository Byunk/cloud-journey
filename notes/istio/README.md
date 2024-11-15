# Istio

## References

- [architecture](https://istio.io/latest/docs/ops/deployment/architecture/)

## Networking

- Istio only supports cross-network communication to workloads with an Istio proxy since it exposes services with TLS passthrough
- A [`topology.istio.io/network`](https://istio.io/latest/docs/reference/config/labels/#TopologyNetwork) is used to identify the network for one or more pods. This is internally used to group pods so that Istio assumes that the pods within same groups are directly reachable from one another. For pods in different networks, an Istio Gateway (e.g. east-west gateway) is typically used to establish connectivitiy.

## Debugging

- [Troubleshooting Istio](https://github.com/istio/istio/wiki/Troubleshooting-Istio)
- [Troubleshooting Multicluster](https://istio.io/latest/docs/ops/diagnostic-tools/multicluster/)
- [Common Problems](https://istio.io/latest/docs/ops/common-problems/network-issues/)

[Envoy Access Log](https://istio.io/latest/docs/tasks/observability/telemetry/) is the primary way to debug Istio.

### Troubleshooting Multi-networks

These troubleshooting steps assume you're following the [Helloworld verification](https://istio.io/latest/docs/setup/install/multicluster/verify/).

`istioctl remote-clusters` is a good starting point for investigating a multi-cluster mesh. It lists all the connected remote instances.

```bash
$ istioctl remote-clusters
NAME         SECRET                                        STATUS     ISTIOD
cluster2     istio-system/istio-remote-secret-cluster2     synced     istiod-9b89dcc88-j8kqt
```

If the remote cluster is synced well, the next step would be to investigate the proxy configuration related to the pod. Let's find the endpoints the `sleep` service has for `helloworld`. We expected that the result should contain two endpoints, one for the local cluster and one for the remote cluster. And the endpoint for the remote should be equal to the remote cluster's east-west gateway IP.

```bash
$ istioctl --context $CTX_CLUSTER1 proxy-config endpoints $(kubectl --context $CTX_CLUSTER1 get po -l app=sleep -n sample -o jsonpath='{.items[*].metadata.name}') -n sample | grep helloworld
10.244.0.22:5000                                        HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
172.18.255.151:15443                                    HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
```

Also, `istioctl proxy-status` shows the overall status of the proxied services in the mesh.

```bash
$ istioctl --context $CTX_CLUSTER1 proxy-status
NAME                                                   CLUSTER      CDS        LDS        EDS        RDS          ECDS         ISTIOD                     VERSION
helloworld-v1-867747c89-2h5cm.sample                   cluster1     SYNCED     SYNCED     SYNCED     SYNCED       NOT SENT     istiod-9b89dcc88-nxxws     1.20.2
helloworld-v2-7f46498c69-hq4qj.sample                  cluster2     SYNCED     SYNCED     SYNCED     SYNCED       NOT SENT     istiod-9b89dcc88-nxxws     1.20.2
```

Retrieve network information.

```bash
istioctl x internal-debug networkz
```
