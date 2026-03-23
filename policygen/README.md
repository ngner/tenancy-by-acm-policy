# policygen/

Root of the ACM PolicyGenerator sources. Each subdirectory corresponds to a
NIST SP 800-53 control family and is rendered independently by its own ArgoCD
Application.

## Structure

```
policygen/
├── AC-Access-Control/               Access enforcement (AC-3)
│   ├── kustomization.yaml           Registers policyGenerator-*.yaml as kustomize generators
│   ├── policyGenerator-hub.yaml     Hub-side fine-grained RBAC: ClusterRoleBindings + MulticlusterRoleAssignments
│   ├── policyGenerator-managed.yaml Managed cluster RoleBindings (depends on policy-tenant-bridge)
│   ├── acm-finegrained-rbac/        object-templates-raw: ClusterRoleBindings, MCRAs (+ legacy bridge-generator)
│   └── rbac/                        object-templates-raw: managed cluster RoleBindings from Tenant CRs
│
└── CM-Configuration-Management/     Configuration settings (CM-6)
    ├── kustomization.yaml           Registers policyGenerator-tenancies.yaml + policyGenerator-managed.yaml
    ├── policyGenerator-tenancies.yaml  Deploys Tenant CRD + replicates Tenant CRs to managed clusters
    ├── policyGenerator-managed.yaml    Namespaces, quotas, network for managed clusters
    ├── bridge/                      Tenant CRD deploy + hub-range Tenant CR replication
    ├── namespace/                   Namespace creation from Tenant CRs
    ├── quota/                       ResourceQuota, ApplicationAwareResourceQuota, LimitRange from Tenant CRs
    ├── network/                     UserDefinedNetwork and MetalLB VRF/BGP from Tenant CRs
    └── network-policy/              Optional AdminNetworkPolicy (additional control)
```

## How PolicyGenerator works

Each `kustomization.yaml` lists `policyGenerator-*.yaml` files under `generators:`.
When kustomize runs with `--enable-alpha-plugins`, it invokes the PolicyGenerator
binary (installed in the ArgoCD repo-server) which reads the generator YAML and
outputs ACM `Policy`, `PlacementBinding`, and `PolicySet` resources.

All policies use `object-templates-raw` manifests that iterate Tenant CRs at
evaluation time using `lookup` and `range`. A single manifest dynamically produces
resources for every tenant — no per-tenant policy blocks or patches are needed.

A policy in the `tenancies` namespace uses `{{hub range hub}}` hub templates to
replicate every `Tenant` CR from the hub to managed clusters. Managed-cluster
policies then iterate those local Tenant CRs with standard `{{ range }}` to create
namespaces, quotas, network resources, and RoleBindings. Hub-side ACM fine-grained
RBAC policies (`MulticlusterRoleAssignment`, `ClusterRoleBinding`) are generated
directly from the Tenant CRs on the hub.

## Adding a new control family

1. Create a new subdirectory (e.g. `SC-Security-Communication/`)
2. Add template YAMLs and a `policyGenerator-*.yaml`
3. Create a `kustomization.yaml` listing the generators
4. Add a corresponding ArgoCD Application in `argocd/`
