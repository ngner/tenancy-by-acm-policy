# Tenancy Model

This document describes how the policies in this repository create tenant isolation, how tenants access their virtual machines through the ACM console, and how each construct maps to an equivalent in VMware vCloud Director.

---

## 1. Personas and roles

Five personas interact with the tenancy platform. The first three are per-tenant roles implemented by the RBAC templates in this repository. The last two are platform-wide roles managed outside the tenant boundary.

| Persona | Scope | Can do | Cannot do |
|---|---|---|---|
| **Tenant-Viewer** | Per-tenant namespace | View VMs and namespace resources in the ACM console | Start, stop, edit, create or delete VMs or any other resources |
| **Tenant-User** | Per-tenant namespace | Start, stop, restart and access VMs; create and delete VMs (`kubevirt.io:edit`); view namespace resources | Create storage, secrets, or services directly; change quotas or RBAC |
| **Tenant-Admin** | Per-tenant namespace | Create and manage VMs, storage (PVCs, DataVolumes), secrets, services; full VM lifecycle | Change resource quotas, RBAC roles, network policies, or the tenant definition; run non-VM container workloads (Deployments, Jobs, etc.) |
| **Service Provider Operator** | Platform-wide | Create new tenancies; adjust quotas and tenant parameters | Change policies, tenancy architecture, or platform components |
| **Service Provider Platform Admin** | Platform-wide | Change policies; add new components to the tenancy construct | Access namespaced tenant workloads directly |

**Tenant-Admin** maps to the `adminGroup` field in the Tenant CRD and receives three roles via MulticlusterRoleAssignment: `tenant-ns:admin` (a custom least-privilege ClusterRole for PVC/Secret/ConfigMap/Service/DataVolume CRUD and Pod/Event read-only), `kubevirt.io:admin` for VM operations, and `acm-vm-extended:admin` for ACM console VM management. On the hub, a ClusterRoleBinding grants `acm-vm-fleet:view` for console visibility.

**Tenant-User** maps to the `userGroup` field and receives `tenant-ns:user` (read-only on namespace resources, no Secret access), `kubevirt.io:edit` (VM CRUD including start/stop/restart), and `acm-vm-extended:view`. On the hub, `acm-vm-fleet:view` grants console visibility.

**Tenant-Viewer** maps to the optional `viewerGroup` field and receives `tenant-ns:viewer` (minimal read-only, no Secrets), `kubevirt.io:view` (read-only VM access), and `acm-vm-extended:view`. If `viewerGroup` is omitted from the Tenant CR, no viewer-tier resources are created.

**Service Provider** roles are not per-tenant RBAC bindings. They are implemented through cluster-admin access, ArgoCD RBAC, and ACM hub console permissions. The tenancy construct enforces separation: a Service Provider Platform Admin can modify policies and tenancy definitions but has no RoleBinding in tenant namespaces; a Tenant-Admin can manage VM workloads in their namespace but cannot alter quotas, RBAC, network policies, or the Tenant CRD.

---

## 2. Tenant segregation layers

A tenant boundary is formed by **four core** controls that apply to every managed cluster: **namespace**, **RBAC**, **primary network (UserDefinedNetwork)** and **Resource quotas**.

**Network isolation between tenants comes primarily from UserDefinedNetworks (UDNs):** each tenant's workloads attach to a UDN that is a **fully isolated** logical network in OVN-Kubernetes.


### Layer 1: Namespace

`policygen/CM-Configuration-Management/namespace/namespaces-from-crd.yaml`

The Kubernetes namespace is the primary unit of containment. Every tenant gets exactly one namespace per managed cluster, named after the tenant. Labels include:

- `customer-namespace: ""` — marks the namespace as a tenant workload boundary.
- `k8s.ovn.org/primary-user-defined-network: ""` — opts the namespace into using its **UserDefinedNetwork** as the primary pod/VM network (see Layer 3).

All other controls — RBAC, quotas, network policies — are scoped to this namespace unless cluster-scoped.

### Layer 2: RBAC

All tenant RBAC is delivered via **MulticlusterRoleAssignment (MCRA)** from the ACM hub — no RoleBindings are created directly on managed clusters. Custom least-privilege ClusterRoles replace the broad built-in `admin`/`edit`/`view` roles to restrict tenants to VM-related operations only.

Custom ClusterRoles are deployed to managed clusters via policy (`policygen/AC-Access-Control/rbac/custom-clusterroles.yaml`). MCRAs bind them to tenant groups scoped to the tenant namespace (`policygen/AC-Access-Control/acm-finegrained-rbac/hub-mcra-virt.yaml`).

Up to three tiers are provisioned per tenant:

- **Tenant-Admin group** — `tenant-ns:admin` (PVC/Secret/ConfigMap/Service/DataVolume CRUD; Pod/Event read), `kubevirt.io:admin`, `acm-vm-extended:admin`
- **Tenant-User group** — `tenant-ns:user` (read-only on PVCs, ConfigMaps, Services, Pods, Events, DataVolumes; no Secrets), `kubevirt.io:edit`, `acm-vm-extended:view`
- **Tenant-Viewer group** — `tenant-ns:viewer` (minimal read-only; no Secrets), `kubevirt.io:view`, `acm-vm-extended:view` (optional)

These RoleBindings grant no visibility into other tenants' namespaces and no cluster-level permissions. The custom ClusterRoles intentionally exclude Role/RoleBinding management, Deployment/StatefulSet/DaemonSet/Job CRUD, NetworkPolicy CRUD, ServiceAccount management, and other permissions that are unnecessary for VM-focused tenants.

### Layer 3: Primary network isolation — UserDefinedNetwork

`policygen/CM-Configuration-Management/network/udn-from-crd.yaml`

Each tenant receives a dedicated `UserDefinedNetwork` (UDN). It is configured as the **primary** network for the namespace, so VM interfaces attach to this network by default.

**Why this isolates tenants:** OVN-Kubernetes implements each UDN as its **own isolated virtual network**. Each UDN is an additional OVN Layer 2 Network isolated from the other networks in the cluster.

**Address spaces:** You still define `spec.layer2.subnets[]` (or equivalent) for addressing **inside that tenant's network** (guest IPs, services, operations). That choice is **independent of isolation**: tenants **may reuse** the same CIDR ranges; overlap **does not** merge networks or create routing between UDNs.

### Layer 4: External connectivity — MetalLB BGP

`policygen/CM-Configuration-Management/metallb/`

Each tenant can receive its own MetalLB BGP peering session in a dedicated VRF for isolated ingress and egress to external networks. This creates three resources per tenant:

- **BGPPeer** — establishes a BGP session with the upstream router
- **IPAddressPool** — assigns a range of external IPs to the tenant's services
- **BGPAdvertisement** — advertises the tenant's service IPs via the BGP session

External connectivity is separate from isolation between tenants. MetalLB VRF/BGP provides **north/south** traffic paths; UDN provides **east/west** isolation.

### Isolation summary

```mermaid
flowchart TD
    subgraph hub [ACM Hub]
        policy[ACM Policy Engine]
    end
    subgraph managed [Managed Cluster]
        subgraph tenantA ["Namespace: starwars"]
            vmA[VMs]
            quotaA["RQ + AAQ + LimitRange"]
            udnA["UDN A\n(primary isolated network)"]
            rbacA["MCRA RoleBindings\n(tenant-ns:* + kubevirt.io:*)"]
            metallbA["MetalLB BGP\n(VRF + BGPPeer + IPPool)"]
        end
        subgraph tenantB ["Namespace: startrek"]
            vmB[VMs]
            quotaB["RQ + AAQ + LimitRange"]
            udnB["UDN B\n(primary isolated network)"]
            rbacB["MCRA RoleBindings\n(tenant-ns:* + kubevirt.io:*)"]
            metallbB["MetalLB BGP\n(VRF + BGPPeer + IPPool)"]
        end
        tenantA -."no path between UDNs".- tenantB
    end
    external["External Network\n(upstream routers)"]
    policy -->|"enforces (remediationAction: enforce)"| managed
    metallbA ---|"ingress / egress via BGP"| external
    metallbB ---|"ingress / egress via BGP"| external
```

### Resource caps (sizing, not isolation)

Quotas and LimitRanges **do not replace** network or RBAC isolation; they cap **how much** a tenant may consume in their own namespace:

| Control | What it bounds |
| --- | --- |
| **ResourceQuota** | **Total** CPU/memory/pods/storage **requests** summed over **all** pods and PVCs in the namespace. |
| **ApplicationAwareResourceQuota** (**AAQ**) | **Total** CPU/memory attributed to **KubeVirt VMIs** only (the `…/vmi` counters). Parallel to ResourceQuota — both must allow a new VM to schedule. |
| **LimitRange** | **Per** object **maximums only** here (no defaults): caps the **largest** single container pod and **per-PVC** size so VM launcher and service pods must declare their own requests. |

For the full distinction and default numbers, see **[Creating a new tenant — section 1.2](new-tenant.md#12-resourcequota-vs-applicationawareresourcequota-vs-limitrange)**.

---

## 3. VM console access via ACM

Tenant users access their VMs through the ACM hub console without needing a direct login to any managed cluster. This is enabled by a two-tier RBAC model that the hub policies establish.

### Tier 1 — ACM console visibility (hub cluster)

`policygen/AC-Access-Control/policygenerator-hub.yaml`

A `ClusterRoleBinding` on the hub grants each tenant group the `acm-vm-fleet:view` role — the documented minimum for fleet virtualization console access (RHACM Scenario 2):

| Group tier | Hub ClusterRole | Effect |
|---|---|---|
| Tenant-Admin | `acm-vm-fleet:view` | Fleet virtualization console visibility |
| Tenant-User | `acm-vm-fleet:view` | Fleet virtualization console visibility |
| Tenant-Viewer | `acm-vm-fleet:view` | Fleet virtualization console visibility |

This controls what the tenant sees in the ACM UI. Without it, the tenant group has no console visibility even if they have direct cluster access. The stronger `acm-vm-fleet:admin` role is only required for cross-cluster live migration and is intentionally not granted to tenant groups.

### Tier 2 — VM operations (managed clusters, via MulticlusterRoleAssignment)

`policygen/AC-Access-Control/acm-finegrained-rbac/hub-mcra-virt.yaml` (generated via `object-templates-raw` from Tenant CRs)

A `MulticlusterRoleAssignment` (`rbac.open-cluster-management.io/v1beta1`) is created on the hub and evaluated by ACM's fine-grained RBAC controller. It propagates RoleBindings to every cluster matched by the Placement, scoped to the tenant namespace. All tenant namespace RBAC — including both VM operations and general namespace resource access — is delivered through this mechanism.

| Group tier | Namespace role | KubeVirt role | ACM extended role |
|---|---|---|---|
| Tenant-Admin | `tenant-ns:admin` | `kubevirt.io:admin` | `acm-vm-extended:admin` |
| Tenant-User | `tenant-ns:user` | `kubevirt.io:edit` | `acm-vm-extended:view` |
| Tenant-Viewer | `tenant-ns:viewer` | `kubevirt.io:view` | `acm-vm-extended:view` |

- `tenant-ns:admin`/`user`/`viewer` — custom least-privilege ClusterRoles scoped to VM-supporting resources (PVCs, Secrets, ConfigMaps, Services, DataVolumes, Pods, Events). Admin gets CRUD on storage and config resources; user and viewer get read-only. These replace the broad built-in `admin`/`edit`/`view` ClusterRoles.
- `kubevirt.io:admin`/`edit`/`view` — allows the ACM console to proxy the VM's VNC and serial console on behalf of the user (admin/edit); also grants power operations (start, stop, restart, live migrate). The `view` role grants read-only access.
- `acm-vm-extended:admin`/`view` — grants access to extended VM management actions exposed through the ACM console (snapshots, clone, etc.).

The tenant group **never needs a kubeconfig or direct API access** to the managed cluster. The ACM console acts as a proxy, and the `MulticlusterRoleAssignment` ensures the necessary authorisation is in place on the target cluster.

### Console access flow

```mermaid
sequenceDiagram
    participant user as "Tenant User\n(IdP group: starwars-tenant-admin)"
    participant acm as "ACM Hub Console"
    participant hub as "Hub RBAC\n(ClusterRoleBinding)"
    participant mcra as "MulticlusterRoleAssignment\n(hub → managed)"
    participant kv as "Managed Cluster\n(KubeVirt)"

    user->>acm: Login via SSO
    acm->>hub: Verify acm-vm-fleet:view membership
    hub-->>acm: Authorised — show starwars fleet
    acm->>mcra: Resolve effective permissions for starwars namespace
    mcra-->>acm: tenant-ns:admin + kubevirt.io:admin + acm-vm-extended:admin on managed clusters
    user->>acm: Open VM console
    acm->>kv: Proxy VNC/serial (authorised by kubevirt.io:admin RoleBinding)
    kv-->>user: Console session
```

### What each role allows

| Action | acm-vm-fleet:view (hub) | kubevirt.io:admin (managed) | kubevirt.io:edit (managed) | kubevirt.io:view (managed) |
|---|:---:|:---:|:---:|:---:|
| See VMs in ACM console | Y | — | — | — |
| Start / stop / restart VM | — | Y | Y | N |
| Open VNC / serial console | — | Y | Y | N |
| Edit VM spec | — | Y | Y | N |
| Delete VM | — | Y | N | N |
| View VM (read-only) | — | Y | Y | Y |

Note: `acm-vm-fleet:admin` (not shown) is only required for cross-cluster live migration and is not granted to tenant groups.

---

## 4. VMware vCloud Director equivalents

This section is aimed at teams migrating from or familiar with vCloud Director. The table maps constructs in this repository to their nearest vCD counterpart.

| OCP / ACM / KubeVirt construct | VMware vCloud Director equivalent | Notes |
|---|---|---|
| Kubernetes **Namespace** | **vCD Organization (Org)** | Primary tenancy boundary and administrative unit. One per tenant. |
| **ResourceQuota** | **Org VDC Allocation Pool / Pay-As-You-Go model** | **Namespace total** — caps summed CPU/memory/pods/PVC storage for **all** workloads in the tenant. |
| **ApplicationAwareResourceQuota** (AAQ) | **VM-only reservation / VM quota** within an Org VDC | **VMI aggregate** — caps total VM compute using `/vmi` counters; complements ResourceQuota; does not replace it. |
| **LimitRange** | **Max VM size / max disk per vApp component** | **Per object** — here, **max only** (no default sizing); workloads declare their own reservations. |
| **UserDefinedNetwork** (OVN) | **Isolated Org VDC network** | **Primary inter-tenant isolation** for workloads on that network — logically separate from other tenants; **overlapping IP plans** across Orgs/UDNs are normal and do not break isolation. |
| **MetalLB BGPPeer + IPAddressPool + VRF** | **vCD Edge Gateway + External Network** | Per-tenant north/south connectivity; distinct from UDN-to-UDN isolation. |
| **Custom ClusterRole** (`tenant-ns:admin` / `user` / `viewer`) | **vCD Org Administrator / vApp Author role** | Least-privilege namespace access for VM-supporting resources (PVCs, Secrets, Services, DataVolumes). Bound via MCRA, not direct RoleBindings. No cross-tenant visibility. |
| **ACM MulticlusterRoleAssignment** (`kubevirt.io:admin` + `tenant-ns:admin`) | **vCD Organization Administrator** with VDC rights | Propagates all tenant namespace permissions — VM management and supporting resource access — across clusters, scoped to the tenant namespace. Equivalent to giving an Org Admin the right to manage VMs within their Org VDC. |
| **ACM fleet ClusterRoleBinding** (`acm-vm-fleet:view`) | **vCD Tenant Portal access** for Org Administrators | Grants visibility into the management console (ACM / vCD tenant portal) for the tenant's group. Without it, the tenant cannot see the console even with underlying cluster rights. |
| **KubeVirt VM console** (ACM proxied via `kubevirt.io:admin`) | **vCD VM Remote Console (VMRC)** via tenant portal | Browser-based VM console access proxied through the management plane. Neither the ACM user nor the vCD tenant user needs direct hypervisor access. |
| **ACM Policy** (`remediationAction: enforce`) | **vCD Defined Entities / Org Policies** | Declarative enforcement — if a resource drifts from the desired state, ACM re-applies it. vCD Defined Entities provide similar schema-enforced resource governance within an Org. |

### Conceptual mapping

```mermaid
flowchart LR
    subgraph vcd [VMware vCloud Director]
        org[Organization]
        vdc["Org VDC\n(Allocation Pool)"]
        edgegw["Edge Gateway\n(per-Org IP pool, BGP)"]
        orgnet["Org VDC Network\n(isolated logical network)"]
        vmrc["VM Remote Console\n(VMRC)"]
        orgadmin["Org Admin role\n(portal access)"]
    end
    subgraph ocp [OCP / ACM / KubeVirt]
        ns[Namespace]
        quota["ResourceQuota +\nApplicationAwareResourceQuota"]
        metallb["MetalLB BGPPeer +\nIPAddressPool + VRF"]
        udn["UserDefinedNetwork\n(primary isolation)"]
        console["KubeVirt console\n(ACM proxied)"]
        fleetrole["acm-vm-fleet:view\n+ MulticlusterRoleAssignment"]
    end

    org <--> ns
    vdc <--> quota
    edgegw <--> metallb
    orgnet <--> udn
    vmrc <--> console
    orgadmin <--> fleetrole
```

---

## 5. Future considerations

- **`kubevirt.io:edit` grants VM CRUD** — the Tenant-User persona is intended for day-to-day VM operations (start, stop, restart, console access) but `kubevirt.io:edit` also permits creating and deleting VMs. If that distinction is important, a custom KubeVirt ClusterRole would be needed. This is a separate effort since the standard `kubevirt.io:*` roles are operator-provided.
- **Orphan cleanup** — if migrating from a previous RBAC model that used direct RoleBindings (referencing the built-in `admin`/`edit`/`view` ClusterRoles), those RoleBindings will need a one-time cleanup on managed clusters. A temporary `mustnothave` policy can automate this.
