# tenancy-by-acm-policy

Use ACM PolicyGenerator with ArgoCD openshift-gitops to deliver multi-tenant isolation across managed OpenShift clusters. Tenancy boundaries — namespaces, RBAC, quotas, network isolation, MetalLB VRF/BGP — are all expressed as PolicyGenerator manifests and delivered through the default ArgoCD instance on the hub. No ACM Channels, Subscriptions or Applications are used.

Policies are organised by NIST SP 800-53 control family:
- **AC-Access-Control** — ACM fine-grained RBAC (`MulticlusterRoleAssignment`) for KubeVirt/VM access on managed clusters, hub `ClusterRoleBinding`s for ACM fleet console visibility, and managed-cluster `RoleBinding`s for tenant namespace admin/edit access.
- **CM-Configuration-Management** — Defines and adds new Tenant CRD and it's replication to managed clusters. Creates tenant namespaces, ResourceQuotas, ApplicationAwareResourceQuotas (VM limits), LimitRanges, UserDefinedNetworks (OVN-isolated primary networks), MetalLB BGP peering, and an optional cluster-wide AdminNetworkPolicy as an additional control (not what isolates UDNs).

A custom `Tenant` CRD (`dusty-seahorse.io/v1alpha1`) in `tenancy-base/` provides the single source of truth for each tenant's identity, RBAC groups, quotas, and network settings. A hub-side policy in the `tenancies` namespace uses `{{hub range hub}}` templates to replicate every `Tenant` CR to managed clusters. Managed-cluster policies then iterate those local Tenant CRs with `{{ range }}` to create namespaces, quotas, network resources, and RoleBindings. Hub-side ACM fine-grained RBAC policies generate `MulticlusterRoleAssignment`s and `ClusterRoleBinding`s directly from the Tenant CRs — adding a tenant is just creating a CR.

Apply in two phases — the PolicyGenerator plugin must be running before the Applications can sync. The `argocd/apply.sh` script handles both phases and auto-detects the current git branch for `targetRevision` (see [argocd/TESTING-BRANCHES.md](argocd/TESTING-BRANCHES.md)):

```bash
argocd/apply.sh
```

Or manually:

```bash
# Phase 1: patch the default ArgoCD with the policygen plugin and wait
oc apply -f argocd/openshift-gitops-policygen.yaml
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops

# Phase 2: create the project and applications
oc apply -f argocd/
```

Update the ACM subscription image tag in `argocd/openshift-gitops-policygen.yaml` to match your installed version (currently set to v2.16).

## Cluster placement

Two sets of placements control which clusters receive policies:

- **`placements/`** (namespace `policies`) — hub and managed-cluster placements used by AC and CM PolicyGenerators.
- **`placements/tenancies/`** (namespace `tenancies`) — placement for the Tenant CR replication policy, with its own `ManagedClusterSetBinding`. This separation allows multiple `tenancies-*` namespaces with different cluster-set bindings.

The default managed-cluster placement selects **every managed cluster except the hub** (`local-cluster`). To switch strategies, change which file is active in `placements/kustomization.yaml`:

```yaml
resources:
  - cluster-hub.yaml
  # Managed-cluster placement — uncomment ONE:
  - clusters-managed.yaml                   # All non-hub clusters (default)
  # - clusters-managed-by-clusterset.yaml   # Specific ManagedClusterSet
  # - clusters-managed-by-label.yaml        # Opt-in by label
```

| File | Selects | When to use |
|---|---|---|
| `clusters-managed.yaml` | Every cluster except `local-cluster`, any cluster set | Simplest — all spoke clusters get tenancy |
| `clusters-managed-by-clusterset.yaml` | All clusters in a named `ManagedClusterSet` | You organise clusters into sets (`default`, `production`, etc.) |
| `clusters-managed-by-label.yaml` | Clusters matching a label selector | Opt-in model — label a cluster `tenant-eligible=true` to include it |

You can also add your own placement files alongside these and reference them in `kustomization.yaml`. As long as the Placement name matches what the PolicyGenerator `policySets` expect, it will work. This makes it straightforward to add new placements for different policy namespaces or cluster groups.

The hub placement (`placements/cluster-hub.yaml`) is fixed to `local-cluster` and normally does not need changing.

![Tenancy by ACM Policy](pictures/architecture.jpg)


## Further reading

- [Tenancy model](docs/tenancy-model.md) — namespace, RBAC, UDN-centric network isolation (and optional AdminNetworkPolicy), ACM VM console access, and VMware vCloud Director equivalents
- [Creating a new tenant](docs/new-tenant.md) — step-by-step with all configurable options (see [§1.2 ResourceQuota vs AAQ vs LimitRange](docs/new-tenant.md#12-resourcequota-vs-applicationawareresourcequota-vs-limitrange))
- [Tenant CRD reference](tenancy-base/README.md) — CRD spec fields, minimal/full examples, and how policies consume Tenant CRs

---

NOTE: If you fork and change this locally then. First find and replace the repo URL with yours.

```bash
grep -r tenancy-by-acm-policy argocd/
argocd/appproject.yaml:    - https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-ac.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-cm.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-placements.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-tenancy-base.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
```