# policygen/

Root of the ACM PolicyGenerator sources. Each subdirectory corresponds to a
NIST SP 800-53 control family and is rendered independently by its own ArgoCD
Application.

## Structure

```
policygen/
├── AC-Access-Control/             Access enforcement (AC-3)
│   ├── kustomization.yaml         Registers policyGenerator-*.yaml as kustomize generators
│   ├── policyGenerator-hub.yaml   Hub-side RBAC + MulticlusterRoleAssignments
│   ├── policyGenerator-managed.yaml  Managed cluster RoleBindings
│   ├── acm-finegrained-rbac/      Templates for ACM fleet ClusterRoleBindings and MCRAs
│   └── rbac/                      Template for namespace-scoped RoleBindings
│
└── CM-Configuration-Management/   Configuration settings (CM-6)
    ├── kustomization.yaml         Registers policyGenerator-managed.yaml as a generator
    ├── policyGenerator-managed.yaml  Namespaces, quotas, network config for managed clusters
    ├── namespace/                  Namespace template
    ├── quota/                      ResourceQuota, ApplicationAwareResourceQuota, LimitRange
    ├── network/                    UserDefinedNetwork and MetalLB VRF/BGP templates
    └── network-policy/             AdminNetworkPolicy for cross-tenant isolation
```

## How PolicyGenerator works

Each `kustomization.yaml` lists `policyGenerator-*.yaml` files under `generators:`.
When kustomize runs with `--enable-alpha-plugins`, it invokes the PolicyGenerator
binary (installed in the ArgoCD repo-server) which reads the generator YAML and
outputs ACM `Policy`, `PlacementBinding`, and `PolicySet` resources.

The generator YAML files use a template+patch model:
- **Base templates** (in subdirectories) define the resource structure with placeholder values
- **Patches** in the generator YAML override specific fields per tenant

This avoids duplicating entire manifests for each tenant.

## Adding a new control family

1. Create a new subdirectory (e.g. `SC-Security-Communication/`)
2. Add template YAMLs and a `policyGenerator-*.yaml`
3. Create a `kustomization.yaml` listing the generators
4. Add a corresponding ArgoCD Application in `argocd/`
