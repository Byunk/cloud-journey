---
title: "CNI - the Container Network Interface"
excerpt: "Learn how CNI is used in Kubernetes networking."
date: "2024-11-15"
draft: true
---

- [High Level Overview](#high-level-overview)
- [Linux Network Namespace](#linux-network-namespace)
- [Container Network Interface (CNI)](#container-network-interface-cni)
 	- [How Containerd implements CNI](#how-containerd-implements-cni)
- [Reference](#reference)

## High Level Overview

Networking in Kubernetes is a complex topic. Let's start from why Kubernetes is needed. Kubernetes is a container orchestration tool that helps you manage a large number of containers. What is happening behind the scenes is that there are a couple of machines (nodes) beneath the Kubernetes cluster, and each node has a container runtime that runs the containers. The problem is that these containers need to communicate with each other as well as with the outside world.

For the simplest case, with a single node, the problem is solved by assigning a different port to each container. However, this solution does not scale well when you have multiple nodes. Coordinating the ports across multiple nodes is a nightmare. API servers need to know which port to connect to, and the port needs to be open on the firewall. The number of containers grow, the number of ports grow, and the complexity grows. Here is where Kubernetes networking comes in.

Before we dive into the details, let's first list the problems that Kubernetes networking should solve:

1. **Container-to-Container Communication**: Containers in the same pod should be able to communicate with each other.
2. **Pod-to-Pod Communication**: Containers in the same pod should be able to communicate with each other.
3. **Pod-to-Service Communication**: Containers in different pods should be able to communicate with each other.
4. **External-to-Service Communication**: External clients should be able to communicate with services.

Don't worry if you don't understand the terms. We will explain them in detail in the following sections.

To begin with, we have to know that Kubernetes assigns an IP address to each pod. Each IP address is unique across the cluster. This is the most important fundamental thing that we should only remember.

## Linux Network Namespace

[Linux network namespace](https://man7.org/linux/man-pages/man7/network_namespaces.7.html) is a powerful feature in Linux that allows you to **isolate** resources such as network devices, IPv4 and IPv6 protocol stacks, firewall rules, and routing tables. Kubernetes leverages this feature to provide network isolation between pods.

Let's see how it works. We're going to create a docker container to see how it works.

TODO: Add a diagram
TODO: Example with 3 network namespaces to demonstrate the isolation

```bash
docker run -it --rm --privileged --name demo ubuntu:22.04 bash
```

Install `iproute2` package to use `ip` command and `iputils-ping` package to use `ping` command.

```bash
apt update && apt install -y iproute2 iputils-ping
```

Create two network namespaces, `ns1` and `ns2`.

```bash
ip netns add ns1
ip netns add ns2
```

Each network namespace has its own network stack including a loopback interface. Let's see the network interfaces in the network namespaces. This is how container to container communication works in Kubernetes. They use loopback interface (simply localhost).

```bash
ip netns exec ns1 ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
...
```

A virtual network ([veth](https://man7.org/linux/man-pages/man4/veth.4.html)) is an abstraction that allows you to create a virtual network interface pair. It can be used to create a bridge between two network namespaces. Let's create a virtual network interface pair, `veth0` and `veth1`. Since `veth` devices are always created in interconnected pairs, we can create them in one command. Packets sent on one device will appear on the other device.

```bash
ip link add veth1 netns ns1 type veth peer veth2 netns ns2
```

Assign an IP address to each network namespace.

```bash
ip -n ns1 addr add 192.168.10.1/24 dev veth1
ip -n ns2 addr add 192.168.10.2/24 dev veth2
```

Bring up the network interfaces.

```bash
ip -n ns1 link set veth1 up
ip -n ns2 link set veth2 up
```

Adding routing rules to the network namespaces.

```bash
ip -n ns1 route add default via 192.168.10.1 dev veth1
ip -n ns2 route add default via 192.168.10.2 dev veth2
```

Now, we can test the network namespace. Let's ping from `ns1` to `ns2`.

```bash
ip netns exec ns1 ping 192.168.10.2 -c 5
...
5 packets transmitted, 5 received, 0% packet loss, time 4095ms
```

## Container Network Interface (CNI)

Here is where the [Container Network Interface (CNI)](https://github.com/containernetworking/cni) comes in. CNI plays a crucial role in Kubernetes networking, although technically CNI is not for Kubernetes only. Actually, Kubernetes does not provide an implementation for networking. Instead, it provides an interface that the particular container runtime should implement, and CNI is the standard for this interface. CNI defines the fundamental building blocks for container networking. For example,

- how to assign an IP address to a pod
- how to request ports on the node for the pod

CNI does not include the following:

- how to assign an IP address to a service: this is the responsibility of the apiserver
- how to assign an IP address to a node: this is the responsibility of the kubelet or the cloud-controller-manager

There are many different CNI plugins available. Their capabilities and features vary. Some of them provide only basic features like adding and removing network interfaces, while others provide more advanced features. Alos, it is possible to use multiple CNI plugins in a single cluster. This [link](https://kubernetes.io/docs/concepts/cluster-administration/addons/#networking-and-network-policy) provides a non-exhaustive list of networking addons.

CNI is composed of two parts: the CNI specification and the CNI plugins. The CNI specification defines the interface that the CNI plugins should implement. [SPEC.md](https://github.com/containernetworking/cni/blob/main/SPEC.md) is the official specification document and [libcni](https://github.com/containernetworking/cni/tree/main/libcni) is the actual implementation of the specification. The `libcni` is typically bundled into the CNI providers.

CNI plugins are programs that applies network configurations. For example, the [`bridge` plugin](https://www.cni.dev/plugins/current/main/bridge/) creates a bridge network interface and attaches the container to it. With the `bridge` plugin, the containers' network namespaces are connected to the host network namespace. Every containers receives an one end of the veth pair and the other end is attached to the bridge. An IP address is only assigned to the container's end of the veth pair. This is how network packets move between the pods and the host.

### How Containerd implements CNI

Let's dig into how [containerd](https://containerd.io/) implements CNI. Containerd is one of the most popular container runtimes that has built-in support for Kubernetes [container runtime interface (CRI)](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/cri-api/pkg/apis/runtime/v1/api.proto). It operates on the same node as the [Kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/). The `cri` plugin inside containerd handles all CRI service requests from the Kubelet and uses containerd internals to manage containers and container images.

![containerd architecture](https://github.com/containerd/containerd/blob/main/docs/cri/architecture.png)

Let's use an example to demonstrate how the `cri` plugin works for the case when Kubelet creates a single-container pod:

- Kubelet calls the `cri` plugin, via the CRI runtime service API, to create a pod;
- `cri` creates the pod’s network namespace, and then configures it using CNI;
- `cri` uses containerd internal to create and start a special [pause container](https://www.ianlewis.org/en/almighty-pause-container) (the sandbox container) and put that container inside the pod’s cgroups and namespace (steps omitted for brevity);
- Kubelet subsequently calls the `cri` plugin, via the CRI image service API, to pull the application container image;
- `cri` further uses containerd to pull the image if the image is not present on the node;
- Kubelet then calls `cri`, via the CRI runtime service API, to create and start the application container inside the pod using the pulled container image;
- `cri` finally uses containerd internal to create the application container, put it inside the pod’s cgroups and namespace, then to start the pod’s new application container.
After these steps, a pod and its corresponding application container is created and running.

TODO: Show the detailed steps with source code of Kubelet

`cni-go` which is a CNI implementation of containerd implements `Setup` function to setup the network in the namespace.

```go
// Setup setups the network in the namespace and returns a Result
func (c *libcni) Setup(ctx context.Context, id string, path string, opts ...NamespaceOpts) (*Result, error) {
	if err := c.Status(); err != nil {
		return nil, err
	}
	ns, err := newNamespace(id, path, opts...)
	if err != nil {
		return nil, err
	}
	result, err := c.attachNetworks(ctx, ns)
	if err != nil {
		return nil, err
	}
	return c.createResult(result)
}
```

It reaches `Attach` function at the end, which calls `AddNetworkList` function from `libcni` package.

```go
func (n *Network) Attach(ctx context.Context, ns *Namespace) (*types100.Result, error) {
	r, err := n.cni.AddNetworkList(ctx, n.config, ns.config(n.ifName))
	if err != nil {
		return nil, err
	}
	return types100.NewResultFromResult(r)
}
```

`Setup` is called by `containerd` in `run.go`.

```go
var Command = &cli.Command{
    ...
        if enableCNI {
			netNsPath, err := getNetNSPath(ctx, task)
			if err != nil {
				return err
			}

			if _, err := network.Setup(ctx, commands.FullID(ctx, container), netNsPath); err != nil {
				return err
			}
		}
    ...
}
```

Let's see how containerd configure network resources when creating a container. Start from [`SyncPod`](https://github.com/kubernetes/kubernetes/blob/e855753ca6e5ec8e061ca05231fcb16b9d5c686c/pkg/kubelet/kuberuntime/kuberuntime_manager.go#L1050) which is a core logic executed by Kubelet.

```go
// SyncPod syncs the running pod into the desired pod by executing following steps:
//
//  1. Compute sandbox and container changes.
//  2. Kill pod sandbox if necessary.
//  3. Kill any containers that should not be running.
//  4. Create sandbox if necessary.
//  5. Create ephemeral containers.
//  6. Create init containers.
//  7. Resize running containers (if InPlacePodVerticalScaling==true)
//  8. Create normal containers.
func (m *kubeGenericRuntimeManager) SyncPod(ctx context.Context, pod *v1.Pod, podStatus *kubecontainer.PodStatus, pullSecrets []v1.Secret, backOff *flowcontrol.Backoff) (result kubecontainer.PodSyncResult) 
```

Before creating a container, Kubelet creates a sandbox container which is a special container that holds the network namespace and other resources for the pod. The detailed implementation is up to the container runtime, and Kubelet executes it by calling [`createPodSandbox`](https://github.com/kubernetes/kubernetes/blob/e855753ca6e5ec8e061ca05231fcb16b9d5c686c/pkg/kubelet/kuberuntime/kuberuntime_sandbox.go#L41). In the case of containerd, it has the following [`Sandbox`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/store/sandbox/sandbox.go#L33) struct.

```go
// Sandbox contains all resources associated with the sandbox. All methods to
// mutate the internal state are thread safe.
type Sandbox struct {
	// Metadata is the metadata of the sandbox, it is immutable after created.
	Metadata
	// Status stores the status of the sandbox.
	Status StatusStorage
	// Container is the containerd sandbox container client.
	Container containerd.Container
	// Sandboxer is the sandbox controller name of the sandbox
	Sandboxer string
	// CNI network namespace client.
	// For hostnetwork pod, this is always nil;
	// For non hostnetwork pod, this should never be nil.
	NetNS *netns.NetNS
	// StopCh is used to propagate the stop information of the sandbox.
	*store.StopCh
	// Stats contains (mutable) stats for the (pause) sandbox container
	Stats *stats.ContainerStats
	// Endpoint is the sandbox endpoint, for task or streaming api connection
	Endpoint Endpoint
}
```

`createPodSandbox` calls [`RunPodSandbox`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/sandbox_run.go#L51) in the CRI. It generates a sandbox object and starts to setup the network. Firstly, it creates a network namespace with [`NewNetNS`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/pkg/netns/netns_linux.go#L55). It creats linux network namespace and stores it in mount point.

Technically, it calls [`unshare`](https://man7.org/linux/man-pages/man1/unshare.1.html) system call to create a new network namespace. Also, we can grap the network namespace by calling `ip netns list`. Let's see.

Create a [kind](https://kind.sigs.k8s.io/) cluster.

```bash
kind create cluster -n kubernetes-networking
```

```bash
docker exec -it kubernetes-networking-control-plane sh -c "apt update && apt install -y iproute2 && ip netns list"
cni-054be080-0c57-fa67-7348-ba2bc66c40f4 (id: 1)
cni-41c40abe-5516-a11d-6a05-25f2593e89b7 (id: 2)
cni-f95d103e-c16e-6f0e-a98d-f2ea8e195642 (id: 3)
```

Also, we can see the network namespace by calling `ls /run/netns/`.

```bash
docker exec -it kubernetes-networking-control-plane ls /run/netns/
cni-054be080-0c57-fa67-7348-ba2bc66c40f4
cni-41c40abe-5516-a11d-6a05-25f2593e89b7
cni-f95d103e-c16e-6f0e-a98d-f2ea8e195642
```

Let's create a pod.

```bash
kubectl run nginx --image nginx
```

And check the network namespace.

```bash
docker exec -it kubernetes-networking-control-plane sh -c "apt update && apt install -y iproute2 && ip netns list"
...
cni-8aeb4b7a-63dc-b43f-ec25-bc25c0db959b (id: 4)
```

Let's get back to the `RunPodSandbox`. It finally calls [`setupPodNetwork`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/sandbox_run.go#L446) to setup the network.

```go
// Setup network for sandbox.
// Certain VM based solutions like clear containers (Issue containerd/cri-containerd#524)
// rely on the assumption that CRI shim will not be querying the network namespace to check the
// network states such as IP.
// In future runtime implementation should avoid relying on CRI shim implementation details.
// In this case however caching the IP will add a subtle performance enhancement by avoiding
// calls to network namespace of the pod to query the IP of the veth interface on every
// SandboxStatus request.
if err := c.setupPodNetwork(ctx, &sandbox); err != nil {
    return nil, fmt.Errorf("failed to setup network for sandbox %q: %w", id, err)
}
```

It's the most important part of what we're looking for.

```go
// setupPodNetwork setups up the network for a pod
func (c *criService) setupPodNetwork(ctx context.Context, sandbox *sandboxstore.Sandbox) error {
	var (
		id        = sandbox.ID
		config    = sandbox.Config
		path      = sandbox.NetNSPath
		netPlugin = c.getNetworkPlugin(sandbox.RuntimeHandler)
		err       error
		result    *cni.Result
	)
	if netPlugin == nil {
		return errors.New("cni config not initialized")
	}
	if c.config.UseInternalLoopback {
		err := c.bringUpLoopback(path)
		if err != nil {
			return fmt.Errorf("unable to set lo to up: %w", err)
		}
	}
	opts, err := cniNamespaceOpts(id, config)
	if err != nil {
		return fmt.Errorf("get cni namespace options: %w", err)
	}
	log.G(ctx).WithField("podsandboxid", id).Debugf("begin cni setup")
	netStart := time.Now()
	if c.config.CniConfig.NetworkPluginSetupSerially {
		result, err = netPlugin.SetupSerially(ctx, id, path, opts...)
	} else {
		result, err = netPlugin.Setup(ctx, id, path, opts...)
	}
	networkPluginOperations.WithValues(networkSetUpOp).Inc()
	networkPluginOperationsLatency.WithValues(networkSetUpOp).UpdateSince(netStart)
	if err != nil {
		networkPluginOperationsErrors.WithValues(networkSetUpOp).Inc()
		return err
	}
	logDebugCNIResult(ctx, id, result)
	// Check if the default interface has IP config
	if configs, ok := result.Interfaces[defaultIfName]; ok && len(configs.IPConfigs) > 0 {
		sandbox.IP, sandbox.AdditionalIPs = selectPodIPs(ctx, configs.IPConfigs, c.config.IPPreference)
		sandbox.CNIResult = result
		return nil
	}
	return fmt.Errorf("failed to find network info for sandbox %q", id)
}
```

First, it brings up the loopback interface.

```go
// https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/sandbox_run_linux.go#L26
func (c *criService) bringUpLoopback(netns string) error {
	if err := ns.WithNetNSPath(netns, func(_ ns.NetNS) error {
		link, err := netlink.LinkByName("lo")
		if err != nil {
			return err
		}
		return netlink.LinkSetUp(link)
	}); err != nil {
		return fmt.Errorf("error setting loopback interface up: %w", err)
	}
	return nil
}

// https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/vendor/github.com/vishvananda/netlink/link_linux.go#L372
// LinkSetUp enables the link device.
// Equivalent to: `ip link set $link up`
func LinkSetUp(link Link) error {
	return pkgHandle.LinkSetUp(link)
}
```

Next, it fetches the CNI namespace options. It includes port mappings, CNI bandwidth, DNS configuration, and cgroup parent.

Then it calls `Setup` function of the CNI plugin, which we have already seen. It returns the result of the network setup.

```go
// Result contains the network information returned by CNI.Setup
//
// a) Interfaces list. Depending on the plugin, this can include the sandbox
//
//	(eg, container or hypervisor) interface name and/or the host interface
//	name, the hardware addresses of each interface, and details about the
//	sandbox (if any) the interface is in.
//
// b) IP configuration assigned to each  interface. The IPv4 and/or IPv6 addresses,
//
//	gateways, and routes assigned to sandbox and/or host interfaces.
//
// c) DNS information. Dictionary that includes DNS information for nameservers,
//
//	domain, search domains and options.
type Result struct {
	Interfaces map[string]*Config
	DNS        []types.DNS
	Routes     []*types.Route
	raw        []*types100.Result
}
```

Finally, it selects the IP address for the pod. It is possible to have a preference among IPv4 and IPv6 addresses. Refer to [Cluster networking types](https://kubernetes.io/docs/concepts/cluster-administration/networking/#cluster-network-ipfamilies) for more information. [`selectPodIPs`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/sandbox_run.go#L484) is responsible for selecting the IP address based on the preference, and its result is stored in `sandbox.IP` and `sandbox.AdditionalIPs`.

Again, back to `RunPodSandbox`. It interally calls [`Create`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/podsandbox/sandbox_run.go#L289) and [`Start`](https://github.com/containerd/containerd/blob/7a804489fdd528cc052071ce47d0217f3c6bcea9/internal/cri/server/podsandbox/sandbox_run.go#L59) from Sandbox Controller. It 'really' creates a container.

After creating a sandbox container, Kubelet determines the IP address of the pod in [`determinePodSandboxIPs`](https://github.com/kubernetes/kubernetes/blob/e855753ca6e5ec8e061ca05231fcb16b9d5c686c/pkg/kubelet/kuberuntime/kuberuntime_sandbox.go#L313).

TODO: DNS

## Reference

- <https://kubernetes.io/docs>
- <https://github.com/kubernetes/design-proposals-archive/blob/main/network/networking.md>
