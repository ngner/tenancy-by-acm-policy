# tenancy-base/

Cross-cutting tenancy infrastructure deployed to the hub cluster by the
`tenancy-base` ArgoCD Application. Resources here are prerequisites consumed
by multiple policy families (AC, CM, and any future families).

## Contents

| File | Kind | Purpose |
|---|---|---|
| `kustomization.yaml` | Kustomization | Lists resources and sets `namespace: tenancies` |
| `tenant-crd.yaml` | CustomResourceDefinition | Defines the `Tenant` CRD (`dusty-seahorse.io/v1alpha1`) |

## Tenant CRD

The `Tenant` custom resource is the single source of truth for a tenant's
identity, RBAC groups, resource limits, and network configuration. Hub-side
ACM fine-grained RBAC policies iterate all `Tenant` objects in the `tenancies`
namespace using `object-templates-raw` and dynamically generate
`ClusterRoleBinding`s (fleet console access) and `MulticlusterRoleAssignment`s
(KubeVirt/VM access on managed clusters). Tenant CRs are also replicated to
managed clusters where further policies create namespaces, quotas, network
resources, and RoleBindings.

### Spec fields

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `displayName` | string | No | — | Human-readable name shown in the console |
| `owner` | string | No | — | Contact email or team identifier |
| `adminGroup` | string | **Yes** | — | IdP group granted admin access |
| `operatorGroup` | string | **Yes** | — | IdP group granted operator/edit access |
| `resourceQuota.cpu` | string | No | `"86"` | Total CPU requests for all pods |
| `resourceQuota.memory` | string | No | `"332Gi"` | Total memory requests for all pods |
| `resourceQuota.pods` | string | No | `"15"` | Maximum pod count |
| `resourceQuota.storage` | string | No | `"2000Gi"` | Total PVC storage |
| `vmQuota.cpu` | string | No | `"80"` | Aggregate vCPU across all VMIs |
| `vmQuota.memory` | string | No | `"320Gi"` | Aggregate memory across all VMIs |
| `limitRange.maxCpu` | string | No | `"32"` | Max CPU per container |
| `limitRange.maxMemory` | string | No | `"128Gi"` | Max memory per container |
| `limitRange.maxStorage` | string | No | `"1Ti"` | Max size per PVC |
| `network.udnSubnet` | string | No | — | CIDR for the tenant's primary UDN |
| `network.metallb.myASN` | integer | No | `64500` | Cluster-side BGP ASN |
| `network.metallb.peerASN` | integer | No | — | Upstream BGP router ASN |
| `network.metallb.peerAddress` | string | No | — | Upstream BGP peer IP |
| `network.metallb.vrf` | string | No | — | Dedicated VRF name |
| `network.metallb.addresses` | string[] | No | — | External IP ranges for services |

### Creating a tenant

Create a `Tenant` CR in the `tenancies` namespace. Only `adminGroup` and
`operatorGroup` are required; everything else has sensible defaults.

Minimal example:

```yaml
apiVersion: dusty-seahorse.io/v1alpha1
kind: Tenant
metadata:
  name: starwars
  namespace: tenancies
spec:
  adminGroup: starwars-admins
  operatorGroup: starwars-operators
```

Full example with all fields: see [`examples/tenant-starwars.yaml`](../examples/tenant-starwars.yaml).

You can create the CR via the CLI or by pasting YAML directly into the
OpenShift console (Home > Search > `Tenant`).

### How policies consume Tenant CRs

**Hub-targeted policies** (ACM fine-grained RBAC) use `object-templates-raw`
with `lookup` and `range` to iterate every `Tenant` in the `tenancies`
namespace directly, generating `ClusterRoleBinding`s and
`MulticlusterRoleAssignment`s:

```yaml
object-templates-raw: |
  {{- range $tenant := (lookup "dusty-seahorse.io/v1alpha1" "Tenant" "tenancies" "").items }}
  ...
  {{- end }}
```

**Tenant CR replication** — a policy in the `tenancies` namespace uses
`{{hub range hub}}` hub templates to replicate every Tenant CR to managed
clusters. The Tenant CRD is deployed first so managed clusters can store
the replicated CRs.

**Managed-cluster policies** iterate the local Tenant CRs using the same
`lookup` and `range` pattern to create namespaces, quotas, network resources,
and RoleBindings:

```yaml
object-templates-raw: |
  {{- range $tenant := (lookup "dusty-seahorse.io/v1alpha1" "Tenant" "tenancies" "").items }}
  ...
  {{- end }}
```

The `Tenant` CR is the **sole data source** for all tenant configuration.
Adding or removing a `Tenant` CR automatically adds or removes all associated
RBAC and configuration resources on the next policy evaluation cycle — no
manifest edits required.
