# Tenant console portal (VMaaS + Developer + CaaS)

Hub policies that control **which console perspectives** tenant IdP groups see, independent of Fleet Management and platform admin views.

## Design

Each portal capability uses a **marker ConfigMap** in `tenancies` and a **RoleBinding** per tenant tier group. Console SAR checks the marker **and** excludes platform admins (`missing: clusteroperators list`), so cluster-admin wildcard access does not expose tenant perspectives.

| Marker | Role | Bound when `workloadProfile` | Console effect |
|--------|------|------------------------------|----------------|
| `portal-vmaas` | `tenant-portal-vmaas` | `vms`, `both` | VMaaS plugin perspective (default landing) |
| `portal-developer` | `tenant-portal-developer` | `containers`, `both` | OpenShift **Developer** perspective (non-admins only) |
| `portal-caas` | `tenant-portal-caas` | `clusters` | CaaS portal marker (console plugin / perspective TBD) |

**Split from Fleet Management:** `acm` (Fleet Management) requires `clusteroperators` list (platform only). Tenants keep `acm-vm-fleet:view` for fleet VM API/search; portal visibility is separate.

## Files

| File | Purpose |
|------|---------|
| `console/tenant-portal-markers.yaml` | ConfigMaps + Roles |
| `console/policy-console-perspective-rbac-vmaas.yaml` | Perspective visibility rules |
| `acm-finegrained-rbac/hub-tenant-console-rbac.yaml` | Per-tenant RoleBindings from Tenant CRs |

## Workload profiles

| Profile | VMaaS default | Developer | CaaS marker | Fleet API (`acm-vm-fleet:view`) | Hub HCP ns |
|---------|---------------|-----------|-------------|-------------------------------|------------|
| `vms` | Yes | No | No | Yes | No |
| `containers` | No | Yes | No | No | No |
| `both` | Yes (default) | Yes | No | Yes | No |
| `clusters` | No | No | Yes | No | `{tenant}-hcp` |

## Cluster-as-a-Service notes

For `workloadProfile: clusters`, hub policy `tenancy-hub-caas-hcp-namespaces` creates `{tenant}-hcp` (override via `spec.clusterAsAService.hcpNamespace`) with a ResourceQuota. Spoke VM namespaces, AAQ, virt MCRAs, and VMaaS portal bindings are not applied.

## Future: tenant admin observability

Add `portal-observability` ConfigMap + Role + bindings (e.g. only `*-tenant-admin` groups), then expose nav in `tenant-vmaas-gui` gated on the same SAR pattern.

## Rollback

Swap `policy-console-perspective-rbac-vmaas.yaml` back to `policy-console-perspective-rbac.yaml` in `policygenerator-hub.yaml` and remove `hub-tenant-console-rbac.yaml` from AC hub generator.
