# Creating a New Tenant

This guide walks through every option available when onboarding a new tenant. A tenant gets its own namespace on each managed cluster with isolated RBAC, resource quotas, networking and external connectivity — all delivered as ACM policies through ArgoCD.

Adding a tenant requires **no YAML edits or git commits**. Create a `Tenant` CR in the `tenancies` namespace on the hub and all policies regenerate automatically.

Throughout this guide `**TENANT**` is used as a placeholder. Replace it with the actual tenant name (lowercase, DNS-safe).

---

## 1. Decide on tenant parameters

Fill in the table below before creating the Tenant CR. All fields except `adminGroup` and `userGroup` have sensible defaults.

### 1.1 Identity & RBAC


| Parameter          | Description                                                                                                       | Example              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- | -------------------- |
| **Tenant label**   | All provisioned objects carry `tenant: <name>` for selection and auditing                                         | `tenant: starwars`   |
| **Tenant name**    | Tenant CR name and default workload namespace on managed clusters; prefix for groups, MetalLB, realms | `starwars`           |
| **Workload namespace** | Optional override for the managed-cluster namespace (`spec.workloadNamespace`). Defaults to tenant name. Use `{tenant}-ns` if you want a suffix. | `starwars` or `starwars-ns` |
| **Workload profile** | What to provision: `vms` (default), `containers`, `both`, or `clusters` (CaaS / HCP) | `vms` or `clusters` |
| **Tenant-Admin group**    | IdP group granted `admin` in the namespace + `kubevirt.io:admin` on VMs + `acm-vm-fleet:view` on the hub console  | `starwars-tenant-admin`  |
| **Tenant-User group**     | IdP group granted `edit` in the namespace + `kubevirt.io:edit` on VMs + `acm-vm-fleet:view` on the hub console    | `starwars-tenant-user`   |
| **Tenant-Viewer group**   | IdP group granted `view` in the namespace + `kubevirt.io:view` on VMs + `acm-vm-fleet:view` on the hub console    | `starwars-tenant-viewer` |


Roles are fixed per group tier:


| Group tier       | Managed cluster namespace role | KubeVirt role       | ACM extended role       | ACM fleet console role |
| ---------------- | ------------------------------ | ------------------- | ----------------------- | ---------------------- |
| Tenant-Admin     | `admin`                        | `kubevirt.io:admin` | `acm-vm-extended:admin` | `acm-vm-fleet:view`    |
| Tenant-User      | `edit`                         | `kubevirt.io:edit`  | `acm-vm-extended:view`  | `acm-vm-fleet:view`    |
| Tenant-Viewer    | `view`                         | `kubevirt.io:view`  | `acm-vm-extended:view`  | `acm-vm-fleet:view`    |


The `viewerGroup` field is optional. If omitted, no viewer-tier resources are created. If you only need one group, remove the unused tiers from the Tenant CR.

### 1.2a Cluster-as-a-Service (`workloadProfile: clusters`)

For HCP / CaaS tenants:

- Hub policy creates namespace `{tenant}-hcp` (override with `spec.clusterAsAService.hcpNamespace`) and a hub ResourceQuota sized for **one HA HCP** (defaults: 12 CPU / 32Gi / 150 pods).
- Spoke VM namespaces, AAQ, virt MCRAs, `acm-vm-fleet:view`, and VMaaS portal bindings are **not** applied.
- Portal marker `portal-caas` is bound for future CaaS console UI.
- Example: [`examples/tenant-acme-caas.yaml`](../examples/tenant-acme-caas.yaml).

HostedCluster automation is a follow-on (Slice B). For a customer who also needs VMs, create a **second** Tenant CR (e.g. `acme-vms`) and optionally reuse IdP/groups (Slice C).

### 1.2 ResourceQuota vs ApplicationAwareResourceQuota vs LimitRange

These three APIs are often mixed up. They apply **together** in the same namespace but enforce **different rules**:


| API                                                                                                                              | Scope           | What it limits                                                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)**                                                 | Whole namespace | **Total** CPU/memory/storage **requests** and **limits** summed across **all** pods, plus pod count, PVC storage sum, etc. Uses plain keys like `requests.cpu`, `requests.memory`.                                         |
| **[ApplicationAwareResourceQuota](https://kubevirt.io/user-guide/operations/application_aware_resource_quota/)** (AAQ, KubeVirt) | Whole namespace | **Total** resources attributed to **VirtualMachineInstance** workload only, using special keys like `requests.cpu/vmi`, `requests.memory/vmi`. Lets you cap aggregate VM capacity separately from other pods.              |
| **[LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)**                                                        | Each object     | **One** pod's containers and **one** PVC. In this repo we only set **max** (no defaults) so nothing injects CPU/memory for VM or service pods — they must specify requests themselves. Does **not** cap tenant-wide usage. |


**How they interact**

- A virt-launcher pod requests CPU/memory like any pod → those counts go toward **ResourceQuota**.
- The same usage is **also** tracked against **AAQ** using the `/vmi` resources. Both must have room for a new VM to schedule.
- **LimitRange** says e.g. "no container may request more than 32 CPUs" — that is a **per-VM / per-pod ceiling**, NOT "the tenant may only use 32 CPUs in total." **Totals** come from ResourceQuota + AAQ.

**Mental model:** ResourceQuota and AAQ answer "**how much is the whole namespace allowed to consume?**" LimitRange answers "**how big is any single pod or PVC allowed to be?**"

The following sections **1.3–1.5** list the default numbers for each API in this repository.

### 1.3 ResourceQuota (namespace totals)

Default sizing assumes **up to 10 VMs** per tenant at **8 vCPU** and **32Gi** RAM each on average (see **AAQ** in section 1.4). **ResourceQuota** must cover **all** pod requests in the namespace: VM pods **plus** a small number of non-VMI pods (e.g. three auxiliary services). The template adds **+6 CPU** and **+12Gi** headroom on top of the **80 / 320Gi** VM aggregate → **86 CPU**, **332Gi**, **15 pods** (10 VMs + services + buffer), and **2000Gi** total PVC requests (tune per your VM disk profile).


| Parameter            | CRD field              | Default    | Description                                 |
| -------------------- | ---------------------- | ---------- | ------------------------------------------- |
| **CPU requests**     | `resourceQuota.cpu`    | `"86"`     | Sum of CPU requests allowed for all pods    |
| **Memory requests**  | `resourceQuota.memory` | `"332Gi"`  | Sum of memory requests allowed for all pods |
| **Pod count**        | `resourceQuota.pods`   | `"15"`     | Max pods in the namespace                   |
| **Storage requests** | `resourceQuota.storage`| `"2000Gi"` | Sum of PVC storage requests                 |


### 1.4 ApplicationAwareResourceQuota (VM workload totals)

These `**/vmi` fields** apply only to **KubeVirt VMI-attributed** usage (evaluated by the AAQ controller). They cap **aggregate** VM capacity in the namespace — e.g. **80** CPU and **320Gi** memory total across all running VMIs (here: 10 × 8 vCPU and 10 × 32Gi). They do **not** replace the namespace **ResourceQuota** in section 1.3; both must allow a schedule.


| Parameter              | CRD field         | Default   | Description                                    |
| ---------------------- | ----------------- | --------- | ---------------------------------------------- |
| **VM CPU requests**    | `vmQuota.cpu`     | `"80"`    | Sum of vCPU across VMIs (example: 10 × 8)      |
| **VM memory requests** | `vmQuota.memory`  | `"320Gi"` | Sum of memory across VMIs (example: 10 × 32Gi) |


Set **ResourceQuota** `resourceQuota.cpu` / `resourceQuota.memory` **≥** the CPU/memory your VM pods will request, **plus** headroom for non-VMI pods. The repo template uses **86 / 332Gi** so ten "8×32Gi" VMs still fit alongside a few small services.

### 1.5 LimitRange (per pod and per PVC — maximums only)

**LimitRange** does **not** set how many VMs or how much CPU the tenant may run in total. This repository's template **only sets `max`** — there are **no** `default`, `defaultRequest`, or `min` entries for containers.

**Why:** KubeVirt VM launcher pods and any tenant service pods should **always** declare their own `requests`/`limits`. Injecting defaults would blur VM vs helper pod sizing and can hide misconfiguration. The LimitRange exists solely to cap the **largest single compute pod** (e.g. one VM) at `**8`** CPU and `**32Gi**` memory, aligned with the planned max VM shape. **Ten** such VMs are allowed **only if** **ResourceQuota** and **AAQ** (sections 1.3–1.4) still have capacity.


| Parameter  | CRD field             | Default | Notes                                                      |
| ---------- | --------------------- | ------- | ---------------------------------------------------------- |
| Max CPU    | `limitRange.maxCpu`   | `32`    | **Per container** — no single pod may request more         |
| Max memory | `limitRange.maxMemory`| `128Gi` | **Per container**                                          |
| Max PVC    | `limitRange.maxStorage`| `1Ti`  | **Per PVC** — total storage cap is still **ResourceQuota** |


### 1.6 User-Defined Network (OVN — primary network isolation)

Each tenant gets a **primary** `UserDefinedNetwork` (UDN) via OVN-Kubernetes. The namespace is labelled with `k8s.ovn.org/primary-user-defined-network` automatically by the namespace template.

**Isolation:** A UDN is a **fully isolated logical network**. Tenant workloads on different UDNs do not have a data path between each other—that is a property of the UDN model. **Overlapping or identical CIDRs** in `spec.layer2.subnets[]` across tenants are valid; each tenant's addresses exist **only inside their own UDN**.

**Still choose a subnet:** You define the CIDR for IP addressing **within that tenant's network** (guests, internal services, operational clarity). Examples in this repo use different CIDRs for readability; you may use the same CIDR for every tenant if your standards allow it.

| Parameter      | CRD field            | Description                                                      |
| -------------- | -------------------- | ---------------------------------------------------------------- |
| **UDN subnet** | `network.udnSubnet`  | CIDR for this tenant's UDN — **need not be unique** cluster-wide. **Default `10.128.0.0/16`** if omitted (policy applies the default; override per tenant as needed). |

Every tenant with a matching `workloadProfile` receives a primary UDN and namespace label automatically. Omitting `udnSubnet` from the Tenant CR still provisions a UDN using the default CIDR.

### 1.7 MetalLB VRF / BGP (external connectivity)

Each tenant can get its own MetalLB BGP peering session in a dedicated VRF for isolated egress/ingress to external networks. This creates three resources per tenant (BGPPeer, IPAddressPool, BGPAdvertisement).

| Parameter        | CRD field                   | Description                                                               |
| ---------------- | --------------------------- | ------------------------------------------------------------------------- |
| **Peer ASN**     | `network.metallb.peerASN`   | ASN of the upstream router for this tenant                                |
| **Peer address** | `network.metallb.peerAddress`| IP address of the upstream BGP peer                                      |
| **VRF name**     | `network.metallb.vrf`       | Dedicated VRF name (e.g. `starwars-vrf`)                                  |
| **Local ASN**    | `network.metallb.myASN`     | Cluster-side ASN (default `64500`, shared across tenants)                 |
| **IP pool**      | `network.metallb.addresses` | CIDR or range of external IPs assigned to this tenant's services          |

If the `network.metallb` section is omitted from the Tenant CR, no MetalLB resources are created.

### 1.8 Managed cluster capabilities

Tenant policies only propagate to spokes labelled with at least one capability:

| Label | Use for |
|-------|---------|
| `tenancy.acm.io/capability-container=true` | Container / application workloads |
| `tenancy.acm.io/capability-vm=true` | VM workloads (requires CNV on the spoke) |

Label before creating tenants. Dual-capability clusters carry both labels. See [placements/capabilities/README.md](../placements/capabilities/README.md).

---

## 2. Create the Tenant CR

Create a `Tenant` CR in the `tenancies` namespace on the hub. Only `adminGroup` and `userGroup` are required — all other fields have defaults from the CRD schema. The `viewerGroup` field is optional.

Minimal example:

```yaml
apiVersion: dusty-seahorse.io/v1alpha1
kind: Tenant
metadata:
  name: TENANT
  namespace: tenancies
spec:
  adminGroup: TENANT-tenant-admin
  userGroup: TENANT-tenant-user
  viewerGroup: TENANT-tenant-viewer
```

Full example with all fields: see [`examples/tenant-starwars.yaml`](../examples/tenant-starwars.yaml).

You can create the CR via the CLI or by pasting YAML directly into the OpenShift console (Home > Search > `Tenant`).

**No other files need editing.** All hub and managed-cluster policies iterate Tenant CRs automatically via the bridge ConfigMap pattern.

---

## 3. What happens next

Once the Tenant CR is created, the policy evaluation cycle produces the following chain:

1. **Hub policy** reads all Tenant CRs and generates a bridge ConfigMap (`tenant-bridge` in `policies` namespace).
2. **Hub policy** generates ClusterRoleBindings and MulticlusterRoleAssignments for every tenant.
3. **Managed-cluster policy** copies the bridge ConfigMap to each managed cluster (`tenant-data` in `tenancies` namespace).
4. **Managed-cluster policies** iterate the local ConfigMap and create:
   - Namespace with tenant labels
   - ResourceQuota, ApplicationAwareResourceQuota, LimitRange
   - UserDefinedNetwork (if `network.udnSubnet` is set)
   - MetalLB BGPPeer, IPAddressPool, BGPAdvertisement (if `network.metallb` is set)
   - RoleBindings for Tenant-Admin, Tenant-User and Tenant-Viewer groups
5. **Hub Keycloak policy** (`tenancy-hub-keycloak-realms`, when `manageRealm` and `seedUsers` are true) bootstraps demo users (display name last name = title-cased tenant, e.g. `Admin Lexx`):

   | Username | Display name | Password | Group |
   |----------|--------------|----------|-------|
   | `admin@<tenant>.local` | `Admin <Tenant>` | `spec.identity.keycloak.seedPassword` (default `password`) | `<tenant>-tenant-admin` |
   | `user@<tenant>.local` | `User <Tenant>` | same | `<tenant>-tenant-user` |
   | `viewer@<tenant>.local` | `Viewer <Tenant>` | same | `<tenant>-tenant-viewer` (if `viewerGroup` set) |

   Set `requirePasswordChange: true` to force a password change on first login.

   See [`policygen/SC-System-and-Communications-Protection/keycloak/README.md`](../policygen/SC-System-and-Communications-Protection/keycloak/README.md) for OIDC client and theme notes.

---

## 4. Verify

On the hub:

```bash
oc get tenants -n tenancies
oc get cm tenant-bridge -n policies -o yaml
oc get policy -n policies | grep TENANT
```

On a managed cluster:

```bash
oc get cm tenant-data -n tenancies -o yaml
oc get namespace TENANT
oc get resourcequota -n TENANT
oc get limitrange -n TENANT
oc get userdefinednetwork -n TENANT
oc get rolebinding -n TENANT
```

### 4.1 Tenant console login and first VM

Tenant **workload namespaces exist on managed clusters only** (not on the ACM hub). After SSO login on the hub:

| `workloadProfile` | Console perspectives | Notes |
|-------------------|---------------------|-------|
| `vms` or `both` | **VMaaS** (requires `tenant-vmaas-gui` plugin) | Default landing for VM tenants; lists VMs via fleet search |
| `containers` or `both` | **Developer** | Gated on `portal-developer` marker in `tenancies` |
| `clusters` | **CaaS** marker (`portal-caas`) | Hub `{tenant}-hcp` namespace; no spoke VM quotas / virt MCRAs / VMaaS. Console plugin TBD |
| Platform admins | Fleet Management, Admin | Tenants do not see Fleet Management when vmaas perspective policy is active |

**Prerequisites for tenant console access:**

1. Hub policies synced: `tenant-portal-markers.yaml`, `hub-tenant-console-rbac.yaml`, `policy-console-perspective-rbac-vmaas.yaml` (see [`docs/tenant-console-portal.md`](tenant-console-portal.md)).
2. VMaaS plugin deployed: `demo-setups/content/tenant-vmaas-gui/deployment/enable-vmaas.sh` (VM / both tenants).
3. UDN is provisioned automatically (default `10.128.0.0/16`; override via `spec.network.udnSubnet`).

Starter VMs are provisioned automatically for `vms` / `both` tenants when
`spec.seedStarterVm.enabled` is true (the default). The hub **tenant-vm-seed-reconciler**
CronJob creates a ManifestWork with a RHEL9 starter VM (`TENANT-starter`,
`cloud-user` / `redhat`). Opt out with `seedStarterVm.enabled: false` or uncheck
**Provision starter VM automatically** in the Create Tenant form.

Manual override (or retry) if needed:

```bash
cd demo-setups/use-cases/acm-tenancy-workloads
./seed-tenant-vm-via-hub.sh -t TENANT -c virtualisation-cluster
```

### 4.2 Onboarding checklist

| Step | Action |
|------|--------|
| 1 | Label managed clusters with capability labels (`tenancy.acm.io/capability-vm` / `capability-container`) |
| 2 | Create Tenant CR (`workloadProfile`, groups, quotas) |
| 3 | Optional: override `network.udnSubnet` (default `10.128.0.0/16`) |
| 4 | Wait for policies Compliant on hub and target spokes |
| 5 | Keycloak realm + OAuth IdP (if using SSO) |
| 6 | Starter VM — automatic via seed reconciler when `seedStarterVm` enabled (default for vms/both) |
| 7 | Deploy VMaaS plugin (`enable-vmaas.sh`) for VM tenants |
| 8 | Verify tenant login: correct perspectives, no Fleet Management |

---

## 5. Removing a tenant

Delete the Tenant CR from the hub (ACM console or CLI):

```bash
oc delete tenant TENANT -n tenancies
```

On the next policy / reconciler cycle:

| Resource | Auto-cleaned? | How |
|----------|---------------|-----|
| Bridge / managed-cluster templates | Yes | Tenant drops out of `lookup` range; CM policies stop producing spoke resources |
| **KeycloakRealmImport** | Yes | `tenancy-hub-keycloak-realms` uses `pruneObjectBehavior: DeleteAll` |
| **OAuth IdP** (`{tenant}-idp`) | Yes | Identity reconciler CronJob removes IdPs whose `openshift-{tenant}` client has no Tenant CR |
| **Client secret** (`openshift-config/{tenant}-client-secret`) | Yes | Reconciler deletes default secret after removing orphan IdP |
| **Portal RoleBindings** (`tenancies/*-portal-vmaas`, `*-portal-developer`) | Yes | Dropped when tenant leaves `hub-tenant-console-rbac` template range (after Argo sync) |
| **Custom theme** (ConfigMap + Keycloak mount) | No — kept on purpose | Mounted once by `apply-themes.sh --no-tenant`. Survives tenant delete so recreate still shows the login CSS. Remove only with `apply-themes.sh -d -t TENANT --purge-themes`. |
| **Hub ClusterRoleBindings / MCRAs** | No | AC Application has `prune: false` — remove manually or sync with prune |

**Custom identity fields:** IdP/secret cleanup assumes default naming (`openshift-{tenant}` client, `{tenant}-client-secret`). Tenants with custom `clientId` or `clientSecretRef.name` may need manual OAuth/secret cleanup after delete.

**Keycloak DB:** Deleting `KeycloakRealmImport` removes the CR only; RHBK does not drop the realm from the database. The identity reconciler CronJob deletes orphan DB realms (no Tenant CR and no import CR) via the Keycloak Admin API on each run.

**Legacy theme-only tenants** (no `spec.identity`, created via `apply-themes.sh -r`): deleting the Tenant CR triggers policy realm-import prune; OAuth IdP cleanup uses the same `openshift-{tenant}` rule when the Tenant CR is gone.

Previously created hub RBAC (see below) still requires manual cleanup:

- Hub ClusterRoleBindings and MulticlusterRoleAssignments are no longer produced by templates. The AC Application has `prune: false` — remove manually or sync with pruning to avoid leaving fleet bindings in place.
