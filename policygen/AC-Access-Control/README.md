# AC-Access-Control

Policies in the **AC (Access Control)** family, mapped to NIST SP 800-53 control
**AC-3 Access Enforcement**. These policies govern who can access tenant resources
on both the ACM hub and managed clusters.

## PolicyGenerators

### policyGenerator-hub.yaml

Targets the hub cluster (`placement-hub-clusters`) and creates ACM fine-grained
RBAC resources directly from Tenant CRs:

- **ClusterRoleBindings** for ACM console access via `acm-vm-fleet:{admin,view}` roles,
  giving tenant groups visibility into their fleet through the ACM UI.
- **MulticlusterRoleAssignments** that grant `kubevirt.io:{admin,edit}` and
  `acm-vm-extended:{admin,view}` roles scoped to the tenant namespace on managed clusters.
  These are ACM fine-grained RBAC resources evaluated on the hub and propagated to
  matching clusters.

A legacy `bridge-generator.yaml` manifest also produces a `tenant-bridge` ConfigMap
that serialises each Tenant CR's `.spec`. This ConfigMap is retained for debugging
but is no longer the data transfer mechanism — Tenant CRs are replicated to managed
clusters directly by `policy-tenant-bridge` in the `tenancies` namespace.

All hub RBAC is driven by **Tenant CRs** in the `tenancies` namespace. The
`object-templates-raw` manifests use `lookup` and `range` to iterate all Tenant
CRs at evaluation time, generating resources for every tenant automatically. No
per-tenant policy blocks or patches are needed.

### policyGenerator-managed.yaml

Targets managed clusters (`placement-managed-clusters`) and creates:

- **RoleBindings** in each tenant namespace granting `admin` to the tenant's admin
  group and `edit` to the operator group.

This policy depends on `policy-tenant-bridge` (tenancies namespace) being Compliant,
which ensures the Tenant CRD and replicated Tenant CRs are present before RoleBindings
are created. Managed-cluster policies iterate the local Tenant CRs directly using
`{{ range }}` and `lookup`.

## Manifests

| Directory | File | Purpose |
|---|---|---|
| `acm-finegrained-rbac/` | `bridge-generator.yaml` | `object-templates-raw` — reads all Tenant CRs, writes the `tenant-bridge` ConfigMap (legacy, retained for debugging) |
| `acm-finegrained-rbac/` | `hub-fleet-crbs.yaml` | `object-templates-raw` — iterates Tenant CRs and generates fleet ClusterRoleBindings (ACM fine-grained RBAC) |
| `acm-finegrained-rbac/` | `hub-mcra-virt.yaml` | `object-templates-raw` — iterates Tenant CRs and generates MulticlusterRoleAssignments (ACM fine-grained RBAC) |
| `rbac/` | `managed-rolebindings.yaml` | `object-templates-raw` — iterates local Tenant CRs to generate RoleBindings on managed clusters |

## Adding a tenant

Create a `Tenant` CR in the `tenancies` namespace on the hub:

```yaml
apiVersion: dusty-seahorse.io/v1alpha1
kind: Tenant
metadata:
  name: newtenant
  namespace: tenancies
spec:
  adminGroup: newtenant-admins
  operatorGroup: newtenant-operators
```

No further edits are required. The hub policy re-evaluates, the Tenant CR is
replicated to managed clusters, and all ClusterRoleBindings, MulticlusterRoleAssignments,
and managed-cluster RoleBindings are created automatically.
