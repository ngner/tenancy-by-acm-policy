# AC-Access-Control

Policies in the **AC (Access Control)** family, mapped to NIST SP 800-53 control
**AC-3 Access Enforcement**. These policies govern who can access tenant resources
on both the ACM hub and managed clusters.

## PolicyGenerators

### policyGenerator-hub.yaml

Targets the hub cluster (`placement-hub-clusters`) and creates:

- **ClusterRoleBindings** for ACM console access via `acm-vm-fleet:{admin,view}` roles,
  giving tenant groups visibility into their fleet through the ACM UI.
- **MulticlusterRoleAssignments** that grant `kubevirt.io:{admin,edit}` and
  `acm-vm-extended:{admin,view}` roles scoped to the tenant namespace on managed clusters.
  These are ACM fine-grained RBAC resources evaluated on the hub and propagated to
  matching clusters.

Hub RBAC is driven by a **tenant-registry ConfigMap**. The `object-templates-raw`
manifests use `lookup` and `range` to iterate the ConfigMap at evaluation time,
generating resources for every tenant automatically. No per-tenant policy blocks
or patches are needed.

### policyGenerator-managed.yaml

Targets managed clusters (`placement-managed-clusters`) and creates:

- **RoleBindings** in each tenant namespace granting `admin` to the tenant's admin
  group and `edit` to the operator group.

## Manifests

| Directory | File | Purpose |
|---|---|---|
| `tenant-registry/` | `tenant-configmap.yaml` | ConfigMap listing all tenants and their IdP groups (single source of truth for hub RBAC) |
| `acm-finegrained-rbac/` | `hub-fleet-crbs.yaml` | `object-templates-raw` — iterates the tenant registry and generates fleet ClusterRoleBindings |
| `acm-finegrained-rbac/` | `hub-mcra-virt.yaml` | `object-templates-raw` — iterates the tenant registry and generates MulticlusterRoleAssignments |
| `rbac/` | `rolebinding.yaml` | Namespace-scoped RoleBinding template (used by `policyGenerator-managed.yaml` with patches) |

## Adding a tenant

Add a new key to `tenant-registry/tenant-configmap.yaml`:

```yaml
data:
  newtenant: |
    adminGroup: newtenant-admins
    operatorGroup: newtenant-operators
```

Then add the managed-cluster RoleBindings in `policyGenerator-managed.yaml` (these
still use the patch-based approach). See the existing `starwars` and `startrek`
blocks as examples.

Commit and push — ArgoCD syncs the change, the hub policy re-evaluates, and all
ClusterRoleBindings and MulticlusterRoleAssignments for the new tenant are created
automatically.
