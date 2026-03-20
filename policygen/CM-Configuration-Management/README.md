# CM-Configuration-Management

Policies in the **CM (Configuration Management)** family, mapped to NIST SP 800-53
control **CM-6 Configuration Settings**. These policies provision and configure tenant
namespaces on managed clusters.

## PolicyGenerator

### policyGenerator-managed.yaml

Targets managed clusters (`placement-managed-clusters`) and creates per-tenant:

- **Namespace** with labels for tenant identification (`customer-namespace`) and
  primary user-defined network opt-in (`k8s.ovn.org/primary-user-defined-network`).
- **ResourceQuota** — **namespace totals** (summed `requests.cpu` / `requests.memory` / pods / PVC storage for every pod). Default **86** CPU, **332Gi** RAM, **15** pods, **2000Gi** storage: room for **10** average VMs (see AAQ) plus a few non-VMI service pods.
- **ApplicationAwareResourceQuota** (**AAQ**) — **VM workload totals** only (`requests.cpu/vmi`, `requests.memory/vmi`). Default **80** CPU / **320Gi** (10 × 8 vCPU × 32Gi). Complements ResourceQuota; a new VM must fit **both**.
- **LimitRange** — **max only** for containers and PVCs (no default/min): caps any one VM pod at **8** CPU / **32Gi** and any PVC at **1Ti**; VM and service pods must set their own requests explicitly.
- **UserDefinedNetwork** providing an L2 overlay subnet per tenant via OVN-Kubernetes.
- **MetalLB VRF/BGP** resources (BGPPeer, IPAddressPool, BGPAdvertisement) for
  per-tenant external (north/south) connectivity.

A cluster-wide **AdminNetworkPolicy** (`tenant-isolation`) is included as an **additional** control (explicit deny between `customer-namespace` namespaces). It is **not** what provides UDN isolation; remove or replace it if you rely solely on UDN separation and other policies.

## Templates

| Directory | Template | Resource |
|---|---|---|
| `namespace/` | `namespace.yaml` | Namespace with tenant labels |
| `quota/` | `resource-quota.yaml` | ResourceQuota |
| `quota/` | `application-aware-resource-quota.yaml` | ApplicationAwareResourceQuota (KubeVirt) |
| `quota/` | `limit-range.yaml` | LimitRange |
| `network/` | `user-defined-network.yaml` | UserDefinedNetwork (isolated UDN; subnet is addressing inside the tenant) |
| `network/` | `metallb-bgp-peer.yaml` | BGPPeer (VRF-scoped BGP session) |
| `network/` | `metallb-ip-pool.yaml` | IPAddressPool (tenant external IPs) |
| `network/` | `metallb-bgp-advertisement.yaml` | BGPAdvertisement (links pool to peer) |
| `network-policy/` | `admin-network-policy.yaml` | Optional AdminNetworkPolicy — extra deny between tenant namespaces |

## Adding a tenant

Add a new policy block in `policyGenerator-managed.yaml` that patches the templates
with tenant-specific values: namespace name, quota limits, UDN subnet (need not be unique across tenants), MetalLB BGP peer/ASN/VRF, and IP pool. Use the existing `starwars` and `startrek` blocks as reference.
