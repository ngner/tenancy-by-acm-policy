# CM-Configuration-Management

Policies in the **CM (Configuration Management)** family, mapped to NIST SP 800-53
control **CM-6 Configuration Settings**. These policies provision and configure tenant
namespaces on managed clusters.

## PolicyGenerator

### policyGenerator-managed.yaml

Targets managed clusters (`placement-managed-clusters`) and creates:

- **Bridge copy** — the `bridge-copier` manifest creates a `tenancies` namespace on
  each managed cluster and copies the hub's `tenant-bridge` ConfigMap into it as
  `tenant-data` using `{{hub copyConfigMapData hub}}`. All subsequent manifests
  read this local ConfigMap.
- **Namespace** with labels for tenant identification (`customer-namespace`) and
  primary user-defined network opt-in (`k8s.ovn.org/primary-user-defined-network`).
- **ResourceQuota** — **namespace totals** (summed `requests.cpu` / `requests.memory` / pods / PVC storage for every pod). Default **86** CPU, **332Gi** RAM, **15** pods, **2000Gi** storage: room for **10** average VMs (see AAQ) plus a few non-VMI service pods.
- **ApplicationAwareResourceQuota** (**AAQ**) — **VM workload totals** only (`requests.cpu/vmi`, `requests.memory/vmi`). Default **80** CPU / **320Gi** (10 × 8 vCPU × 32Gi). Complements ResourceQuota; a new VM must fit **both**.
- **LimitRange** — **max only** for containers and PVCs (no default/min): caps any one VM pod at **8** CPU / **32Gi** and any PVC at **1Ti**; VM and service pods must set their own requests explicitly.
- **UserDefinedNetwork** providing an L2 overlay subnet per tenant via OVN-Kubernetes (if `network.udnSubnet` is set in the Tenant CR).
- **MetalLB VRF/BGP** resources (BGPPeer, IPAddressPool, BGPAdvertisement) for
  per-tenant external (north/south) connectivity (if `network.metallb` is set in the Tenant CR).

A cluster-wide **AdminNetworkPolicy** (`tenant-isolation`) is included as an **additional** control (explicit deny between `customer-namespace` namespaces). It is **not** what provides UDN isolation; remove or replace it if you rely solely on UDN separation and other policies.

`orderManifests: true` ensures the bridge ConfigMap is copied before namespaces are
created, which must exist before quotas and network resources are applied.

## Manifests

| Directory | File | Resource |
|---|---|---|
| `bridge/` | `bridge-copier.yaml` | Copies `tenant-bridge` ConfigMap from hub to `tenant-data` in `tenancies` namespace on managed clusters |
| `namespace/` | `namespaces-from-crd.yaml` | `object-templates-raw` — creates a Namespace per tenant from the bridge ConfigMap |
| `quota/` | `quotas-from-crd.yaml` | `object-templates-raw` — creates ResourceQuota, AAQ, and LimitRange per tenant |
| `network/` | `network-from-crd.yaml` | `object-templates-raw` — creates UDN and MetalLB resources per tenant (conditional on CRD fields) |
| `network-policy/` | `admin-network-policy.yaml` | Optional AdminNetworkPolicy — extra deny between tenant namespaces |

## Adding a tenant

Create a `Tenant` CR in the `tenancies` namespace on the hub. The bridge ConfigMap
updates automatically, is copied to managed clusters, and all managed-cluster resources
(namespaces, quotas, network) are generated from it.
