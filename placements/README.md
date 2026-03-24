# placements/

ACM Placement rules that determine which clusters receive the generated policies.
The active placements are controlled by `kustomization.yaml`.

## Policies placements (`placements/policies/`, namespace: `policies`)

| File | Placement name | Targets |
|---|---|---|
| `placement-hub.yaml` | `policies-placement-hub-clusters` | The local ACM hub cluster (`name: local-cluster`) |
| `placement-managed.yaml` | `policies-placement-managed-clusters` | Every managed cluster except the hub — no cluster set filter |

The kustomization sets `namespace: policies` on all resources in this directory.

## Tenancies placements (`placements/tenancies/`, namespace: `tenancies`)

The `tenancies/` subdirectory contains placements for policies deployed in the
`tenancies` namespace (e.g. the Tenant CR replication policy). It has its own
`ManagedClusterSetBinding` resources to bind `ManagedClusterSet`s to the
`tenancies` namespace, which is required for Placements there to select managed
clusters.

| File | Kind | Name | Purpose |
|---|---|---|---|
| `managed-cluster-set-binding.yaml` | ManagedClusterSetBinding | `default`, `managed` | Binds the `default` and `managed` ManagedClusterSets to the `tenancies` namespace |
| `placement-managed.yaml` | Placement | `tenancies-placement-managed-clusters` | Selects all non-hub managed clusters (excludes `local-cluster`) |
| `placement-hub.yaml` | Placement | `tenancies-placement-hub-clusters` | Selects the local ACM hub cluster (`name: local-cluster`) |

This separation supports multiple `tenancies-*` namespaces with different
cluster-set bindings, allowing distinct groups of tenants to target different
sets of managed clusters.

## How placements are used

PolicyGenerator `policySets` reference placements by name. When ACM processes a
generated policy, it evaluates the referenced Placement to decide which clusters
the policy applies to.

- **Hub placement** — used by AC and SC policies that create hub-side resources
  (ClusterRoleBindings, MulticlusterRoleAssignments, Tenant CRD).
- **Managed placement** — used by AC, CM, and SC policies that create resources
  on managed clusters (RoleBindings, Namespaces, Quotas, UDNs, MetalLB, Tenant CRs).

## Tolerations

Both placements include tolerations for `unavailable` and `unreachable` clusters so
that policies remain bound even when a managed cluster goes offline temporarily.

## Switching the managed-cluster placement

All placement variants live as top-level files in this directory. Switch by
commenting/uncommenting in `kustomization.yaml`:

```yaml
resources:
  - placement-hub.yaml

  # Managed-cluster placement — uncomment ONE of the following:
  - placement-managed.yaml                         # All non-hub clusters (no clusterSet filter)
  # - placement-managed-by-clusterset.yaml  # Specific ManagedClusterSet (edit clusterSets value)
  # - placement-managed-by-label.yaml       # Opt-in by label (tenant-eligible=true)
```

### Available placements

| File | Strategy | Details |
|---|---|---|
| `placement-managed.yaml` | Exclude hub only | No `clusterSets` filter — matches every ManagedCluster except `local-cluster`. Default. |
| `placement-managed-by-clusterset.yaml` | ManagedClusterSet | Targets all clusters in the named set. Edit `clusterSets: [default]` to your set name. |
| `placement-managed-by-label.yaml` | Label selector | Opt-in model. Only clusters labelled `tenant-eligible: "true"` are selected. Apply with `oc label managedcluster <name> tenant-eligible=true`. |

## Adding a new placement

Add a new YAML file to this directory, include it in `kustomization.yaml`, and
reference the placement name in the relevant `policygenerator-*.yaml` under
`policySets[].placement.placementName`.

This pattern supports multiple placements for different policy groups — for example
a `policies-placement-virt-clusters` targeting only clusters with OpenShift Virtualization,
referenced by a separate PolicySet.
