# policygen/

Root of the ACM PolicyGenerator sources. Each subdirectory corresponds to a
NIST SP 800-53 control family and is rendered independently by its own ArgoCD
Application.

## Structure

```
policygen/
├── AC-Access-Control/             Access enforcement (AC-3)
│   ├── kustomization.yaml         Registers policyGenerator-*.yaml as kustomize generators
│   ├── policyGenerator-hub.yaml   Hub-side bridge ConfigMap + RBAC + MulticlusterRoleAssignments
│   ├── policyGenerator-managed.yaml  Managed cluster RoleBindings
│   ├── acm-finegrained-rbac/      object-templates-raw: bridge generator, ClusterRoleBindings, MCRAs
│   └── rbac/                      object-templates-raw: managed cluster RoleBindings from bridge ConfigMap
│
└── CM-Configuration-Management/   Configuration settings (CM-6)
    ├── kustomization.yaml         Registers policyGenerator-managed.yaml as a generator
    ├── policyGenerator-managed.yaml  Bridge copier, namespaces, quotas, network for managed clusters
    ├── bridge/                    Copies bridge ConfigMap from hub to managed clusters
    ├── namespace/                 Namespace creation from bridge ConfigMap
    ├── quota/                     ResourceQuota, ApplicationAwareResourceQuota, LimitRange from bridge ConfigMap
    ├── network/                   UserDefinedNetwork and MetalLB VRF/BGP from bridge ConfigMap
    └── network-policy/            Optional AdminNetworkPolicy (additional control)
```

## How PolicyGenerator works

Each `kustomization.yaml` lists `policyGenerator-*.yaml` files under `generators:`.
When kustomize runs with `--enable-alpha-plugins`, it invokes the PolicyGenerator
binary (installed in the ArgoCD repo-server) which reads the generator YAML and
outputs ACM `Policy`, `PlacementBinding`, and `PolicySet` resources.

All policies use `object-templates-raw` manifests that iterate Tenant CRs (on the
hub) or the bridge ConfigMap (on managed clusters) at evaluation time using `lookup`
and `range`. A single manifest dynamically produces resources for every tenant —
no per-tenant policy blocks or patches are needed.

The bridge ConfigMap pattern works around ACM's `{{hub ... hub}}` limitation (no
`range`/`if`/`:=`): a hub policy generates a ConfigMap from Tenant CRs, then
`{{hub copyConfigMapData hub}}` replicates it to managed clusters where standard
`{{ range }}` can iterate it.

## Adding a new control family

1. Create a new subdirectory (e.g. `SC-Security-Communication/`)
2. Add template YAMLs and a `policyGenerator-*.yaml`
3. Create a `kustomization.yaml` listing the generators
4. Add a corresponding ArgoCD Application in `argocd/`
