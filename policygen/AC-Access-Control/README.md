# AC-Access-Control

Policies in the **AC (Access Control)** family, mapped to NIST SP 800-53 control
**AC-3 Access Enforcement**. These policies govern who can access tenant resources
on both the ACM hub and managed clusters.

## PolicyGenerators

### policygenerator-hub.yaml

Targets the hub cluster (`policies-placement-hub-clusters`) and creates ACM fine-grained
RBAC resources directly from Tenant CRs:

- **ClusterRoleBindings** granting `acm-vm-fleet:view` to all three tenant groups
  (admin, user, viewer) — the documented minimum for fleet virtualization console
  access (RHACM Scenario 2). `acm-vm-fleet:admin` is not used as it is only
  required for cross-cluster live migration.
- **MulticlusterRoleAssignments** that grant `kubevirt.io:{admin,edit,view}` and
  `acm-vm-extended:{admin,view}` roles scoped to the tenant namespace on managed
  clusters. These are ACM fine-grained RBAC resources evaluated on the hub and
  propagated to matching clusters.

### policygenerator-managed.yaml

Targets managed clusters (`policies-placement-managed-clusters`) and creates:

- **RoleBindings** in each tenant namespace granting `admin` to the Tenant-Admin
  group, `edit` to the Tenant-User group, and `view` to the Tenant-Viewer group.

This policy depends on `tenancy-managed-tenant-replication` (tenancies namespace) being Compliant,
which ensures the Tenant CRD and replicated Tenant CRs are present before RoleBindings
are created. Managed-cluster policies iterate the local Tenant CRs directly using
`{{ range }}` and `lookup`.

## Manifests

| Directory | File | Purpose |
|---|---|---|
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
  adminGroup: newtenant-tenant-admin
  userGroup: newtenant-tenant-user
  viewerGroup: newtenant-tenant-viewer
```

No further edits are required. The hub policy re-evaluates, the Tenant CR is
replicated to managed clusters, and all ClusterRoleBindings, MulticlusterRoleAssignments,
and managed-cluster RoleBindings are created automatically.
