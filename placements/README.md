# placements/

ACM Placement rules that determine which clusters receive the generated policies.

## Files

| File | Placement name | Targets |
|---|---|---|
| `cluster-hub.yaml` | `placement-hub-clusters` | The local ACM hub cluster (`name: local-cluster`) |
| `clusters-managed.yaml` | `placement-managed-clusters` | All clusters in the `default` ManagedClusterSet |

## How placements are used

PolicyGenerator `policySets` reference placements by name. When ACM processes a
generated policy, it evaluates the referenced Placement to decide which clusters
the policy applies to.

- **Hub placement** -- used by AC policies that create hub-side resources
  (ClusterRoleBindings, MulticlusterRoleAssignments).
- **Managed placement** -- used by both AC and CM policies that create resources
  on managed clusters (RoleBindings, Namespaces, Quotas, NetworkPolicies, etc.).

## Tolerations

Both placements include tolerations for `unavailable` and `unreachable` clusters so
that policies remain bound even when a managed cluster goes offline temporarily.

## Adding a new placement

Create a new YAML file with a `Placement` resource, add it to `kustomization.yaml`,
and reference the placement name in the relevant `policyGenerator-*.yaml` under
`policySets[].placement.placementName`.

The kustomization sets `namespace: policies` on all resources in this directory.
