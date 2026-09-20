# Cluster capability labels

Managed clusters are included in tenancy when labelled with at least one
capability. Placements use **OR** semantics across predicates (container **or**
VM capability).

| Label | Meaning |
|-------|---------|
| `tenancy.acm.io/capability-container=true` | Spoke can host container/application tenant workloads |
| `tenancy.acm.io/capability-vm=true` | Spoke runs OpenShift Virtualization (CNV); VM tenant RBAC and AAQ apply |

A dual-capability cluster carries **both** labels. A cluster with **neither**
label is excluded from tenant namespace and policy propagation.

## Label clusters

```bash
# Container-only spoke (e.g. aws-us)
oc label managedcluster aws-us \
  tenancy.acm.io/capability-container=true --overwrite

# VM + container spoke (e.g. virtualisation-cluster with CNV)
oc label managedcluster virtualisation-cluster \
  tenancy.acm.io/capability-container=true \
  tenancy.acm.io/capability-vm=true --overwrite
```

Remove a capability:

```bash
oc label managedcluster aws-us tenancy.acm.io/capability-container-
```

## What each placement selects

All placements are in the **`tenancies`** namespace.

| Placement | Selects |
|-----------|---------|
| `tenancies-placement-managed-clusters` | `capability-container` **or** `capability-vm` |
| `tenancies-placement-managed-vm-clusters` | `capability-vm` only |

Base CM/AC policies and `tenant-ns:*` MCRAs use the managed placement.
`kubevirt.io:*` and `acm-vm-extended:*` MCRAs use the VM placement.

## Tenant workload profile

Per-tenant `spec.workloadProfile` (`containers`, `vms`, `both`; default `vms`)
gates which resources policies create on capable clusters:

| Profile | Namespaces / quotas / network | RBAC |
|---------|------------------------------|------|
| `vms` | VM placement only (AAQ + VM quotas) | `kubevirt.io:*`, `tenant-ns:*` on VM placement; fleet console view |
| `containers` | Managed placement (ResourceQuota, no AAQ) | `tenant-ns:*` on managed placement only |
| `both` | Both policy sets where applicable | VM + container RBAC as above |

Capability labels gate **which clusters** participate; workload profile gates
**what** each tenant receives on those clusters.
