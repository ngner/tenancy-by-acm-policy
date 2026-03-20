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
│   ├── tenant-registry/           ConfigMap listing all tenants (consumed by object-templates-raw)
│   ├── acm-finegrained-rbac/      object-templates-raw manifests for ClusterRoleBindings and MCRAs
│   └── rbac/                      Template for namespace-scoped RoleBindings
│
└── CM-Configuration-Management/   Configuration settings (CM-6)
    ├── kustomization.yaml         Registers policyGenerator-managed.yaml as a generator
    ├── policyGenerator-managed.yaml  Namespaces, quotas, network config for managed clusters
    ├── namespace/                  Namespace template
    ├── quota/                      ResourceQuota, ApplicationAwareResourceQuota, LimitRange
    ├── network/                    UserDefinedNetwork (primary isolation) and MetalLB VRF/BGP
    └── network-policy/             Optional AdminNetworkPolicy (additional control)
```

## How PolicyGenerator works

Each `kustomization.yaml` lists `policyGenerator-*.yaml` files under `generators:`.
When kustomize runs with `--enable-alpha-plugins`, it invokes the PolicyGenerator
binary (installed in the ArgoCD repo-server) which reads the generator YAML and
outputs ACM `Policy`, `PlacementBinding`, and `PolicySet` resources.

The generator YAML files use two approaches depending on the target:

- **Hub policies (AC-Access-Control)** — `object-templates-raw` manifests that
  iterate the `tenant-registry` ConfigMap (or `Tenant` CRs from
  `tenancy-base/`) at evaluation time using `lookup` and `range`. A single
  manifest dynamically produces resources for every tenant.
- **Managed-cluster policies** — a template+patch model where base templates
  (in subdirectories) define the resource structure with placeholder values and
  patches in the generator YAML override specific fields per tenant.

Both approaches avoid duplicating entire manifests for each tenant.

## Adding a new control family

1. Create a new subdirectory (e.g. `SC-Security-Communication/`)
2. Add template YAMLs and a `policyGenerator-*.yaml`
3. Create a `kustomization.yaml` listing the generators
4. Add a corresponding ArgoCD Application in `argocd/`
