# tenancy-by-acm-policy

Use ACM PolicyGenerator with ArgoCD openshift-gitops to deliver multi-tenant isolation across managed OpenShift clusters. Tenancy boundaries — namespaces, RBAC, quotas, network isolation, MetalLB VRF/BGP — are all expressed as PolicyGenerator manifests and delivered through the default ArgoCD instance on the hub. No ACM Channels, Subscriptions or Applications are used.

Policies are organised by NIST SP 800-53 control family:
- **AC-Access-Control** — Hub and managed cluster RBAC, ACM fine-grained RBAC, MulticlusterRoleAssignments for KubeVirt workloads.
- **CM-Configuration-Management** — Tenant namespaces, ResourceQuotas, ApplicationAwareResourceQuotas (VM limits), LimitRanges, UserDefinedNetworks (OVN-isolated primary networks), MetalLB BGP peering, and an optional cluster-wide AdminNetworkPolicy as an additional control (not what isolates UDNs).

Templates use a base+patch model so adding a new tenant is just a new policy block in the generator YAML — no manifest duplication.

Apply in two phases — the PolicyGenerator plugin must be running before the Applications can sync:

```bash
# Phase 1: patch the default ArgoCD with the policygen plugin and wait
oc apply -f argocd/openshift-gitops-policygen.yaml
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops

# Phase 2: create the project and applications
oc apply -f argocd/
```

Update the ACM subscription image tag in `argocd/openshift-gitops-policygen.yaml` to match your installed version (currently set to v2.16).

## Cluster placement

The managed-cluster placement controls which clusters receive tenant policies. By default it selects **every managed cluster except the hub** (`local-cluster`). No `clusterSets` filter is applied, so it works across all ManagedClusterSets associated with the policies namespace without configuration.

To switch strategies, change which file is active in `placements/kustomization.yaml`:

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

---

NOTE: If you fork and change this locally then. First find and replace the repo URL with yours.

```bash
grep -r tenancy-by-acm-policy argocd/
argocd/appproject.yaml:    - https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-ac.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-cm.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
argocd/application-placements.yaml:    repoURL: https://github.com/ngner/tenancy-by-acm-policy.git
```