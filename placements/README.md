# placements/

ACM Placement rules that determine which clusters receive tenant policies.
All placements are deployed to the **`tenancies`** namespace (same as Policy CRs
and Tenant CRs).

See [capabilities/README.md](capabilities/README.md) for cluster capability labels.

For a full map of Argo apps, PolicySets, and placements, see
[docs/placements-cheatsheet.md](../docs/placements-cheatsheet.md).

## Active placements (`placements/tenancies/`)

| File | Placement name | Targets |
|---|---|---|
| `placement-hub.yaml` | `tenancies-placement-hub-clusters` | Hub (`local-cluster`) |
| `placement-managed-by-capability.yaml` | `tenancies-placement-managed-clusters` | `capability-container` **or** `capability-vm` |
| `placement-managed-vm-capability.yaml` | `tenancies-placement-managed-vm-clusters` | `capability-vm` only |

## Legacy (`placements/policies/`)

Deprecated — retained in Git for reference only. No longer applied by Argo CD.
Use `placements/tenancies/` instead.

## How placements are used

- **Hub placement** — Tenant CRD, Keycloak, OAuth, hub RBAC (MCRAs, CRBs).
- **Managed placement** — Container-side spoke resources (namespaces, quotas, UDN).
- **VM placement** — VM-side spoke resources and `kubevirt.io:*` MCRAs.

## Switching strategy

In `placements/tenancies/kustomization.yaml`, swap capability files for a legacy
`placement-managed.yaml` if needed. See root [README.md](../README.md#cluster-placement).
