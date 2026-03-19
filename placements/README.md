# placements/

ACM Placement rules that determine which clusters receive the generated policies.
The active placements are controlled by `kustomization.yaml`.

## Active placements

| File | Placement name | Targets |
|---|---|---|
| `cluster-hub.yaml` | `placement-hub-clusters` | The local ACM hub cluster (`name: local-cluster`) |
| `clusters-managed.yaml` | `placement-managed-clusters` | Every managed cluster except the hub — no cluster set filter |

The kustomization sets `namespace: policies` on all resources in this directory.

## How placements are used

PolicyGenerator `policySets` reference placements by name. When ACM processes a
generated policy, it evaluates the referenced Placement to decide which clusters
the policy applies to.

- **Hub placement** — used by AC policies that create hub-side resources
  (ClusterRoleBindings, MulticlusterRoleAssignments).
- **Managed placement** — used by both AC and CM policies that create resources
  on managed clusters (RoleBindings, Namespaces, Quotas, NetworkPolicies, etc.).

## Tolerations

Both placements include tolerations for `unavailable` and `unreachable` clusters so
that policies remain bound even when a managed cluster goes offline temporarily.

## Switching the managed-cluster placement

All placement variants live as top-level files in this directory. Switch by
commenting/uncommenting in `kustomization.yaml`:

```yaml
resources:
  - cluster-hub.yaml

  # Managed-cluster placement — uncomment ONE of the following:
  - clusters-managed.yaml                # All non-hub clusters (no clusterSet filter)
  # - clusters-managed-by-clusterset.yaml  # Specific ManagedClusterSet (edit clusterSets value)
  # - clusters-managed-by-label.yaml       # Opt-in by label (tenant-eligible=true)
```

### Available placements

| File | Strategy | Details |
|---|---|---|
| `clusters-managed.yaml` | Exclude hub only | No `clusterSets` filter — matches every ManagedCluster except `local-cluster`. Default. |
| `clusters-managed-by-clusterset.yaml` | ManagedClusterSet | Targets all clusters in the named set. Edit `clusterSets: [default]` to your set name. |
| `clusters-managed-by-label.yaml` | Label selector | Opt-in model. Only clusters labelled `tenant-eligible: "true"` are selected. Apply with `oc label managedcluster <name> tenant-eligible=true`. |

## Adding a new placement

Add a new YAML file to this directory, include it in `kustomization.yaml`, and
reference the placement name in the relevant `policyGenerator-*.yaml` under
`policySets[].placement.placementName`.

This pattern supports multiple placements for different policy groups — for example
a `placement-virt-clusters` targeting only clusters with OpenShift Virtualization,
referenced by a separate PolicySet.
