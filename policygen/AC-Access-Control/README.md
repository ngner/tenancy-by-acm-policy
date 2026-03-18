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

### policyGenerator-managed.yaml

Targets managed clusters (`placement-managed-clusters`) and creates:

- **RoleBindings** in each tenant namespace granting `admin` to the tenant's admin
  group and `edit` to the operator group.

## Templates

| Directory | Template | Resource |
|---|---|---|
| `acm-finegrained-rbac/` | `acm-fleet-clusterrolebinding.yaml` | ClusterRoleBinding for ACM console fleet roles |
| `acm-finegrained-rbac/` | `multiclusterroleassignment-virt.yaml` | MulticlusterRoleAssignment for KubeVirt + extended roles |
| `rbac/` | `rolebinding.yaml` | Namespace-scoped RoleBinding |

Templates use placeholder values (e.g. `TENANT-ROLE`, `TENANT-NAMESPACE`) that are
overridden by the `patches` block in each PolicyGenerator policy entry.

## Adding a tenant

Add a new policy block in both `policyGenerator-hub.yaml` and
`policyGenerator-managed.yaml`, patching the templates with the tenant's group names,
namespace, and desired roles. See the existing `starwars` and `startrek` blocks as
examples.
