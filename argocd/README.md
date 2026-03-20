# argocd/

ArgoCD resources for deploying the tenancy policies onto an ACM hub cluster using
the default `openshift-gitops` ArgoCD instance.

## Files

| File | Kind | Purpose |
|---|---|---|
| `openshift-gitops-policygen.yaml` | ArgoCD | Patches the default ArgoCD instance to install the PolicyGenerator kustomize plugin in the repo-server |
| `appproject.yaml` | AppProject | Scoped project (`tenancy-policy`) restricting sync to ACM policy resource types in the `policies` namespace |
| `application-ac.yaml` | Application | Syncs `policygen/AC-Access-Control` -- tenant RBAC and ACM fine-grained access |
| `application-cm.yaml` | Application | Syncs `policygen/CM-Configuration-Management` — namespaces, quotas, UDNs, MetalLB, optional AdminNetworkPolicy |
| `application-placements.yaml` | Application | Syncs `placements/` -- the Placement rules referenced by generated policies |

## PolicyGenerator plugin setup

The `openshift-gitops-policygen.yaml` adds an init container to the ArgoCD repo-server
that copies the `PolicyGenerator` binary from the ACM subscription image. This enables
kustomize to process `PolicyGenerator` manifests when ArgoCD renders the Application
sources.

Key settings applied to the ArgoCD instance:

- `kustomizeBuildOptions: --enable-alpha-plugins` -- enables kustomize exec plugins
- `KUSTOMIZE_PLUGIN_HOME` env var -- tells kustomize where to find the plugin binary
- Shared `kustomize` volume -- transfers the binary from the init container to the repo-server

The init container image tag (`v2.16`) must match the installed ACM version.

## Apply order

The policygen plugin must be active before the Applications can sync, so apply in two phases:

```bash
# Phase 1: plugin + wait
oc apply -f argocd/openshift-gitops-policygen.yaml
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops

# Phase 2: project + applications
oc apply -f argocd/appproject.yaml
oc apply -f argocd/application-placements.yaml
oc apply -f argocd/application-ac.yaml
oc apply -f argocd/application-cm.yaml
```

## Sync behaviour

| Application | Auto-sync | Prune | Self-heal |
|---|---|---|---|
| `tenancy-access-control` | Yes | No | No |
| `tenancy-configuration-management` | Yes | Yes | Yes |
| `tenancy-placements` | Yes | Yes | Yes |

Access Control has pruning and self-heal disabled to prevent accidental removal of RBAC
bindings during policy refactoring.
