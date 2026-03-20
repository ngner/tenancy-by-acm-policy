# Creating a New Tenant

This guide walks through every option available when onboarding a new tenant. A tenant gets its own namespace on each managed cluster with isolated RBAC, resource quotas, networking and external connectivity — all delivered as ACM policies through ArgoCD.

Throughout this guide `**TENANT**` is used as a placeholder. Replace it with the actual tenant name (lowercase, DNS-safe).

---

## 1. Decide on tenant parameters

Fill in the table below before touching any YAML. Hub RBAC values go into the tenant-registry ConfigMap; managed-cluster values go into patch fields in the PolicyGenerator files.

### 1.1 Identity & RBAC


| Parameter          | Description                                                                                                       | Example              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- | -------------------- |
| **Tenant name**    | Namespace name on managed clusters, used as prefix everywhere                                                     | `starwars`           |
| **Admin group**    | IdP group granted `admin` in the namespace + `kubevirt.io:admin` on VMs + `acm-vm-fleet:admin` on the hub console | `starwars-admins`    |
| **Operator group** | IdP group granted `edit` in the namespace + `kubevirt.io:edit` on VMs + `acm-vm-fleet:view` on the hub console    | `starwars-operators` |


Roles are fixed per group tier:


| Group tier | Managed cluster namespace role | KubeVirt role       | ACM extended role       | ACM fleet console role |
| ---------- | ------------------------------ | ------------------- | ----------------------- | ---------------------- |
| Admin      | `admin`                        | `kubevirt.io:admin` | `acm-vm-extended:admin` | `acm-vm-fleet:admin`   |
| Operator   | `edit`                         | `kubevirt.io:edit`  | `acm-vm-extended:view`  | `acm-vm-fleet:view`    |


If you only need one group (e.g. no operator/view split), remove the operator RoleBinding and MulticlusterRoleAssignment blocks.

### 1.2 ResourceQuota vs ApplicationAwareResourceQuota vs LimitRange

These three APIs are often mixed up. They apply **together** in the same namespace but enforce **different rules**:


| API                                                                                                                              | Scope           | What it limits                                                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)**                                                 | Whole namespace | **Total** CPU/memory/storage **requests** and **limits** summed across **all** pods, plus pod count, PVC storage sum, etc. Uses plain keys like `requests.cpu`, `requests.memory`.                                         |
| **[ApplicationAwareResourceQuota](https://kubevirt.io/user-guide/operations/application_aware_resource_quota/)** (AAQ, KubeVirt) | Whole namespace | **Total** resources attributed to **VirtualMachineInstance** workload only, using special keys like `requests.cpu/vmi`, `requests.memory/vmi`. Lets you cap aggregate VM capacity separately from other pods.              |
| **[LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)**                                                        | Each object     | **One** pod’s containers and **one** PVC. In this repo we only set **max** (no defaults) so nothing injects CPU/memory for VM or service pods — they must specify requests themselves. Does **not** cap tenant-wide usage. |


**How they interact**

- A virt-launcher pod requests CPU/memory like any pod → those counts go toward **ResourceQuota**.
- The same usage is **also** tracked against **AAQ** using the `/vmi` resources. Both must have room for a new VM to schedule.
- **LimitRange** says e.g. “no container may request more than 32 CPUs” — that is a **per-VM / per-pod ceiling**, NOT “the tenant may only use 32 CPUs in total.” **Totals** come from ResourceQuota + AAQ.

**Mental model:** ResourceQuota and AAQ answer “**how much is the whole namespace allowed to consume?**” LimitRange answers “**how big is any single pod or PVC allowed to be?**”

The following sections **1.3–1.5** list the default numbers for each API in this repository.

### 1.3 ResourceQuota (namespace totals)

Default sizing assumes **up to 10 VMs** per tenant at **8 vCPU** and **32Gi** RAM each on average (see **AAQ** in section 1.4). **ResourceQuota** must cover **all** pod requests in the namespace: VM pods **plus** a small number of non-VMI pods (e.g. three auxiliary services). The template adds **+6 CPU** and **+12Gi** headroom on top of the **80 / 320Gi** VM aggregate → **86 CPU**, **332Gi**, **15 pods** (10 VMs + services + buffer), and **2000Gi** total PVC requests (tune per your VM disk profile).


| Parameter            | Field              | Default    | Description                                 |
| -------------------- | ------------------ | ---------- | ------------------------------------------- |
| **CPU requests**     | `requests.cpu`     | `"86"`     | Sum of CPU requests allowed for all pods    |
| **Memory requests**  | `requests.memory`  | `"332Gi"`  | Sum of memory requests allowed for all pods |
| **Pod count**        | `pods`             | `"15"`     | Max pods in the namespace                   |
| **Storage requests** | `requests.storage` | `"2000Gi"` | Sum of PVC storage requests                 |


You can also add per-StorageClass limits. Uncomment and set these in the patch:

```yaml
spec:
  hard:
    gold-storageclass.storageclass.storage.k8s.io/requests.storage: "500Gi"
    silver-storageclass.storageclass.storage.k8s.io/requests.storage: "500Gi"
```

### 1.4 ApplicationAwareResourceQuota (VM workload totals)

These `**/vmi` fields** apply only to **KubeVirt VMI-attributed** usage (evaluated by the AAQ controller). They cap **aggregate** VM capacity in the namespace — e.g. **80** CPU and **320Gi** memory total across all running VMIs (here: 10 × 8 vCPU and 10 × 32Gi). They do **not** replace the namespace **ResourceQuota** in section 1.3; both must allow a schedule.


| Parameter              | Field                 | Default   | Description                                    |
| ---------------------- | --------------------- | --------- | ---------------------------------------------- |
| **VM CPU requests**    | `requests.cpu/vmi`    | `"80"`    | Sum of vCPU across VMIs (example: 10 × 8)      |
| **VM memory requests** | `requests.memory/vmi` | `"320Gi"` | Sum of memory across VMIs (example: 10 × 32Gi) |
| **VM CPU limits**      | `limits.cpu/vmi`      | `"80"`    | Limit-side ceiling for VM workload             |
| **VM memory limits**   | `limits.memory/vmi`   | `"320Gi"` | Limit-side ceiling for VM workload             |


Set **ResourceQuota** `requests.cpu` / `requests.memory` **≥** the CPU/memory your VM pods will request, **plus** headroom for non-VMI pods. The repo template uses **86 / 332Gi** so ten “8×32Gi” VMs still fit alongside a few small services.

### 1.5 LimitRange (per pod and per PVC — maximums only)

**LimitRange** does **not** set how many VMs or how much CPU the tenant may run in total. This repository’s template **only sets `max`** — there are **no** `default`, `defaultRequest`, or `min` entries for containers.

**Why:** KubeVirt VM launcher pods and any tenant service pods should **always** declare their own `requests`/`limits`. Injecting defaults would blur VM vs helper pod sizing and can hide misconfiguration. The LimitRange exists solely to cap the **largest single compute pod** (e.g. one VM) at `**8`** CPU and `**32Gi**` memory, aligned with the planned max VM shape. **Ten** such VMs are allowed **only if** **ResourceQuota** and **AAQ** (sections 1.3–1.4) still have capacity.


| Parameter  | Field             | Template value | Notes                                                      |
| ---------- | ----------------- | -------------- | ---------------------------------------------------------- |
| Max CPU    | `max.cpu`         | `32`           | **Per container** — no single pod may request more         |
| Max memory | `max.memory`      | `128Gi`        | **Per container**                                          |
| Max PVC    | PVC `max.storage` | `1Ti`          | **Per PVC** — total storage cap is still **ResourceQuota** |


Patch the LimitRange manifest entry if you need different `max` values or optional extra `limits` entries (e.g. min/default) for a specific platform policy.

### 1.6 User-Defined Network (OVN — primary network isolation)

Each tenant gets a **primary** `UserDefinedNetwork` (UDN) via OVN-Kubernetes. The namespace is labelled with `k8s.ovn.org/primary-user-defined-network` automatically by the namespace template.

**Isolation:** A UDN is a **fully isolated logical network**. Tenant workloads on different UDNs do not have a data path between each other—that is a property of the UDN model. **Overlapping or identical CIDRs** in `spec.layer2.subnets[]` across tenants are valid; each tenant’s addresses exist **only inside their own UDN**.

**Still choose a subnet:** You define `spec.layer2.subnets[]` for IP addressing **within that tenant's network** (guests, internal services, operational clarity). Examples in this repo use different CIDRs for readability; you may use the same CIDR for every tenant if your standards allow it.

| Parameter      | Field                   | Description                                                      |
| -------------- | ----------------------- | ---------------------------------------------------------------- |
| **UDN subnet** | `spec.layer2.subnets[]` | CIDR(s) for this tenant’s UDN — **need not be unique** cluster-wide |


| Tenant        | Example UDN subnet (optional uniqueness for ops) |
| ------------- | ------------------------------------------------- |
| starwars      | `10.0.1.0/24`                                     |
| startrek      | `10.0.2.0/24`                                     |
| *your-tenant* | *your choice; may overlap other tenants’ UDNs*    |


### 1.7 MetalLB VRF / BGP (external connectivity)

Each tenant can get its own MetalLB BGP peering session in a dedicated VRF for isolated egress/ingress to external networks. This creates three resources per tenant.

#### BGPPeer


| Parameter        | Field              | Description                                                               |
| ---------------- | ------------------ | ------------------------------------------------------------------------- |
| **Peer ASN**     | `spec.peerASN`     | ASN of the upstream router for this tenant                                |
| **Peer address** | `spec.peerAddress` | IP address of the upstream BGP peer                                       |
| **VRF name**     | `spec.vrf`         | Dedicated VRF name (e.g. `starwars-vrf`)                                  |
| **Local ASN**    | `spec.myASN`       | Cluster-side ASN (default `64500`, shared across tenants in the template) |


#### IPAddressPool


| Parameter                    | Field              | Description                                                                 |
| ---------------------------- | ------------------ | --------------------------------------------------------------------------- |
| **Egress/Ingress addresses** | `spec.addresses[]` | CIDR or range of external IPs assigned to this tenant's services            |
| **Auto-assign**              | `spec.autoAssign`  | `true` by default — LoadBalancer services pick from this pool automatically |


#### BGPAdvertisement

Links the pool to the peer. No additional parameters — name references are derived from the BGPPeer and IPAddressPool names.

Example allocation plan:


| Tenant        | Peer ASN   | Peer address | VRF          | IP pool         |
| ------------- | ---------- | ------------ | ------------ | --------------- |
| starwars      | 64501      | 192.168.1.1  | starwars-vrf | 192.168.11.0/24 |
| startrek      | 64502      | 192.168.1.2  | startrek-vrf | 192.168.12.0/24 |
| *your-tenant* | *next ASN* | *next peer*  | *tenant-vrf* | *next pool*     |


If a tenant does **not** need external BGP connectivity, omit the entire `metallb-vrf-bgp.yaml` manifest entry from its policy block.

### 1.8 Optional additional control — AdminNetworkPolicy

**Primary** east/west isolation between tenant workloads on their primary UDNs comes from **UserDefinedNetwork** (section 1.6): separate UDNs do not forward traffic to each other, regardless of overlapping IP plans.

This repository also ships a cluster-wide **AdminNetworkPolicy** (`policy-tenant-isolation-anp`) as a **separate** control: it denies ingress and egress between namespaces labelled `customer-namespace: ""`. That is useful as defence in depth, for namespaces or interfaces that are not solely on an isolated UDN, or where you want an explicit API-level deny rule. You could omit or replace it in your own fork; it does **not** define UDN isolation.

No per-tenant YAML is required for the sample ANP — it matches the label applied by the namespace template. Removing or changing the policy is done by editing the policy manifest / generator, not by per-tenant patches.

---

## 2. Files to edit

| File                                                                 | What to add                                                                |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `policygen/AC-Access-Control/tenant-registry/tenant-configmap.yaml`  | A new key with the tenant's name, admin group, and operator group          |
| `policygen/AC-Access-Control/policyGenerator-managed.yaml`           | Managed cluster RoleBindings in the tenant namespace (patch-based)         |
| `policygen/CM-Configuration-Management/policyGenerator-managed.yaml` | Namespace, quotas, LimitRange, UDN, MetalLB (patch-based)                 |

Hub RBAC (fleet ClusterRoleBindings and MulticlusterRoleAssignments) is generated
automatically from the tenant-registry ConfigMap — no policy block or patches needed
in `policyGenerator-hub.yaml`.

---

## 3. Step-by-step

### 3.1 Add hub RBAC (AC — tenant-registry ConfigMap)

Add a new key to `policygen/AC-Access-Control/tenant-registry/tenant-configmap.yaml`.
The key is the tenant name; the value is a YAML string containing the IdP group names:

```yaml
data:
  TENANT: |
    adminGroup: TENANT-admins
    operatorGroup: TENANT-operators
```

That is the only change needed for hub RBAC. The `object-templates-raw` manifests in
`acm-finegrained-rbac/` use `lookup` and `range` to iterate every key in the
ConfigMap at policy evaluation time and automatically generate:

- Two **ClusterRoleBindings** per tenant (`acm-vm-fleet:admin` for the admin group,
  `acm-vm-fleet:view` for the operator group).
- Two **MulticlusterRoleAssignments** per tenant (`kubevirt.io:admin` +
  `acm-vm-extended:admin` for admins, `kubevirt.io:edit` + `acm-vm-extended:view`
  for operators), scoped to the tenant namespace on managed clusters via
  `placement-managed-clusters`.

No policy blocks or patches in `policyGenerator-hub.yaml` need to be touched.

### 3.2 Add managed cluster RoleBindings (AC — policyGenerator-managed.yaml)

```yaml
  - name: policy-tenant-TENANT-managed-rbac
    manifests:
      - path: rbac/rolebinding.yaml
        patches:
          - metadata:
              name: customer-TENANT-admin
              namespace: TENANT
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: admin
            subjects:
              - kind: Group
                apiGroup: rbac.authorization.k8s.io
                name: TENANT-admins
      - path: rbac/rolebinding.yaml
        patches:
          - metadata:
              name: customer-TENANT-operators
              namespace: TENANT
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: edit
            subjects:
              - kind: Group
                apiGroup: rbac.authorization.k8s.io
                name: TENANT-operators
```

### 3.3 Add managed cluster configuration (CM — policyGenerator-managed.yaml)

```yaml
  - name: policy-tenant-TENANT-config
    manifests:
      - path: namespace/namespace.yaml
        patches:
          - metadata:
              name: TENANT
      - path: quota/resource-quota.yaml
        patches:
          - metadata:
              name: TENANT-resource-quota
              namespace: TENANT
            spec:
              hard:
                requests.cpu: "86"          # 80 (VMs) + headroom for ~3 service pods
                requests.memory: "332Gi"    # 320Gi (VMs) + headroom
                pods: "15"                  # 10 VMs + 3 pods + buffer
                requests.storage: "2000Gi"  # tune per disk footprint
      - path: quota/application-aware-resource-quota.yaml
        patches:
          - metadata:
              name: TENANT-vm-resource-quota
              namespace: TENANT
            spec:
              hard:
                requests.cpu/vmi: "80"      # 10 VMs × 8 vCPU
                requests.memory/vmi: "320Gi" # 10 VMs × 32Gi
                limits.cpu/vmi: "80"
                limits.memory/vmi: "320Gi"
      - path: quota/limit-range.yaml
        patches:
          - metadata:
              name: TENANT-limit-range
              namespace: TENANT
      - path: network/user-defined-network.yaml
        patches:
          - metadata:
              name: TENANT-network
              namespace: TENANT
            spec:
              layer2:
                subnets:
                  - "10.0.X.0/24"         # <-- CIDR inside this tenant's UDN (may overlap other tenants)
      - path: network/metallb-bgp-peer.yaml
        patches:
          - metadata:
              name: TENANT-bgp-peer
            spec:
              peerASN: 64503              # <-- upstream ASN
              peerAddress: 192.168.1.X    # <-- upstream peer IP
              vrf: TENANT-vrf
      - path: network/metallb-ip-pool.yaml
        patches:
          - metadata:
              name: TENANT-ip-pool
            spec:
              addresses:
                - 192.168.X.0/24          # <-- external IP pool
      - path: network/metallb-bgp-advertisement.yaml
        patches:
          - metadata:
              name: TENANT-bgp-advertisement
            spec:
              ipAddressPools:
                - TENANT-ip-pool
              peers:
                - TENANT-bgp-peer
```

---

## 4. Commit and sync

Push the branch. ArgoCD will detect the change and sync the updated PolicyGenerator output. The generated policies propagate to all clusters matched by the placements.

Verify on the hub:

```bash
# Check the generated policies exist
oc get policy -n policies | grep TENANT

# Check compliance
oc get policy -n policies -l policy.open-cluster-management.io/policy=policy-tenant-TENANT-config
```

Verify on a managed cluster:

```bash
oc get namespace TENANT
oc get resourcequota -n TENANT
oc get limitrange -n TENANT
oc get userdefinednetwork -n TENANT
oc get rolebinding -n TENANT
```

---

## 5. Removing a tenant

1. **Hub RBAC** — remove the tenant's key from `policygen/AC-Access-Control/tenant-registry/tenant-configmap.yaml`. On the next policy evaluation the `object-templates-raw` will no longer generate that tenant's ClusterRoleBindings or MulticlusterRoleAssignments. The previously created hub resources must be cleaned up manually (or via a separate `mustnothave` policy) because `mustonlyhave` only enforces objects that the template produces.
2. **Managed RBAC** — delete the tenant's policy block from `policygen/AC-Access-Control/policyGenerator-managed.yaml`.
3. **Managed config** — delete the tenant's policy block from `policygen/CM-Configuration-Management/policyGenerator-managed.yaml`.

Push the changes. The CM Application has `prune: true` so ArgoCD will remove the generated policies for steps 2–3. ACM will then remove the resources from managed clusters.

The AC Application has `prune: false` — RBAC removals require a manual sync with pruning or direct cleanup to avoid accidental access revocation during refactoring.