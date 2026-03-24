# CM-Configuration-Management

Policies in the **CM (Configuration Management)** family, mapped to NIST SP 800-53
control **CM-6 Configuration Settings**. These policies provision and configure tenant
namespaces on managed clusters.

## PolicyGenerators

### policygenerator-hub.yaml

Targets the hub cluster (`policies-placement-hub-clusters`) and creates hub-side
configuration policies.

### policygenerator-managed.yaml

Targets managed clusters (`policies-placement-managed-clusters`) and depends on
`tenancy-managed-tenant-replication` (tenancies namespace) being Compliant — ensuring the Tenant
CRD and replicated Tenant CRs are present before downstream resources are created.

- **Namespace** with labels for tenant identification (`customer-namespace`) and
  primary user-defined network opt-in (`k8s.ovn.org/primary-user-defined-network`).
- **ResourceQuota** — **namespace totals** (summed `requests.cpu` / `requests.memory` / pods / PVC storage for every pod). Default **86** CPU, **332Gi** RAM, **15** pods, **2000Gi** storage: room for **10** average VMs (see AAQ) plus a few non-VMI service pods.
- **ApplicationAwareResourceQuota** (**AAQ**) — **VM workload totals** only (`requests.cpu/vmi`, `requests.memory/vmi`). Default **80** CPU / **320Gi** (10 x 8 vCPU x 32Gi). Complements ResourceQuota; a new VM must fit **both**.
- **LimitRange** — **max only** for containers and PVCs (no default/min): caps any one VM pod at **8** CPU / **32Gi** and any PVC at **1Ti**; VM and service pods must set their own requests explicitly.
- **UserDefinedNetwork** providing an L2 overlay subnet per tenant via OVN-Kubernetes (if `network.udnSubnet` is set in the Tenant CR).
- **MetalLB VRF/BGP** resources (BGPPeer, IPAddressPool, BGPAdvertisement) for
  per-tenant external (north/south) connectivity (if `network.metallb` is set in the Tenant CR).

`orderManifests: true` ensures namespaces exist before quotas and network resources
are applied.

## Manifests

| Directory | File | Resource |
|---|---|---|
| `namespace/` | `namespaces-from-crd.yaml` | `object-templates-raw` — creates a Namespace per Tenant CR |
| `quota/` | `quotas-from-crd.yaml` | `object-templates-raw` — creates ResourceQuota, AAQ, and LimitRange per Tenant CR |
| `quota/` | `hyperconverged-aaq-enabled.yaml` | Enables the AAQ feature gate on HyperConverged |
| `network/` | `udn-from-crd.yaml` | `object-templates-raw` — creates UserDefinedNetwork per Tenant CR (conditional on spec fields) |
| `metallb/` | `bgp-peer-from-crd.yaml` | `object-templates-raw` — creates MetalLB BGPPeer per Tenant CR |
| `metallb/` | `ip-address-pool-from-crd.yaml` | `object-templates-raw` — creates MetalLB IPAddressPool per Tenant CR |
| `metallb/` | `bgp-advertisement-from-crd.yaml` | `object-templates-raw` — creates MetalLB BGPAdvertisement per Tenant CR |
| `network-policy/` | `admin-network-policy.yaml` | AdminNetworkPolicy — cluster-wide deny between tenant namespaces |

## Adding a tenant

Create a `Tenant` CR in the `tenancies` namespace on the hub. The hub-side policy
re-evaluates, replicates the new Tenant CR to managed clusters, and all managed-cluster
resources (namespaces, quotas, network) are generated from it automatically.
