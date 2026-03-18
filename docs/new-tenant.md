# Creating a New Tenant

This guide walks through every option available when onboarding a new tenant. A tenant gets its own namespace on each managed cluster with isolated RBAC, resource quotas, networking and external connectivity — all delivered as ACM policies through ArgoCD.

Throughout this guide **`TENANT`** is used as a placeholder. Replace it with the actual tenant name (lowercase, DNS-safe).

---

## 1. Decide on tenant parameters

Fill in the table below before touching any YAML. Every value maps directly to a patch field in the PolicyGenerator files.

### 1.1 Identity & RBAC

| Parameter | Description | Example |
|---|---|---|
| **Tenant name** | Namespace name on managed clusters, used as prefix everywhere | `starwars` |
| **Admin group** | IdP group granted `admin` in the namespace + `kubevirt.io:admin` on VMs + `acm-vm-fleet:admin` on the hub console | `starwars-admins` |
| **Operator group** | IdP group granted `edit` in the namespace + `kubevirt.io:edit` on VMs + `acm-vm-fleet:view` on the hub console | `starwars-operators` |

Roles are fixed per group tier:

| Group tier | Managed cluster namespace role | KubeVirt role | ACM extended role | ACM fleet console role |
|---|---|---|---|---|
| Admin | `admin` | `kubevirt.io:admin` | `acm-vm-extended:admin` | `acm-vm-fleet:admin` |
| Operator | `edit` | `kubevirt.io:edit` | `acm-vm-extended:view` | `acm-vm-fleet:view` |

If you only need one group (e.g. no operator/view split), remove the operator RoleBinding and MulticlusterRoleAssignment blocks.

### 1.2 Resource quotas

| Parameter | Field | Default | Description |
|---|---|---|---|
| **CPU requests** | `requests.cpu` | `"4"` | Total CPU cores the tenant can request |
| **Memory requests** | `requests.memory` | `"16Gi"` | Total memory the tenant can request |
| **Pod count** | `pods` | `"10"` | Maximum number of pods |
| **Storage requests** | `requests.storage` | `"1000Gi"` | Total PVC storage |

You can also add per-StorageClass limits. Uncomment and set these in the patch:

```yaml
spec:
  hard:
    gold-storageclass.storageclass.storage.k8s.io/requests.storage: "500Gi"
    silver-storageclass.storageclass.storage.k8s.io/requests.storage: "500Gi"
```

### 1.3 VM quotas (ApplicationAwareResourceQuota)

These limits apply specifically to KubeVirt VirtualMachineInstance workloads and are evaluated by the AAQ controller independently of the standard ResourceQuota.

| Parameter | Field | Default | Description |
|---|---|---|---|
| **VM CPU requests** | `requests.cpu/vmi` | `"4"` | Total vCPUs across all running VMs |
| **VM memory requests** | `requests.memory/vmi` | `"16Gi"` | Total memory across all running VMs |
| **VM CPU limits** | `limits.cpu/vmi` | `"4"` | CPU limit ceiling for VMs |
| **VM memory limits** | `limits.memory/vmi` | `"16Gi"` | Memory limit ceiling for VMs |

Set VM quotas lower than or equal to the main ResourceQuota — the AAQ quota is a subset, not additive.

### 1.4 LimitRange

Container defaults applied when a pod does not specify its own resource requests/limits.

| Parameter | Field | Default |
|---|---|---|
| Default CPU | `default.cpu` | `500m` |
| Default memory | `default.memory` | `512Mi` |
| Default request CPU | `defaultRequest.cpu` | `100m` |
| Default request memory | `defaultRequest.memory` | `256Mi` |
| Max CPU | `max.cpu` | `2` |
| Max memory | `max.memory` | `4Gi` |
| Min CPU | `min.cpu` | `50m` |
| Min memory | `min.memory` | `64Mi` |
| Max PVC size | PVC `max.storage` | `500Gi` |
| Min PVC size | PVC `min.storage` | `1Gi` |

Override any of these by adding a `spec.limits` patch block to the LimitRange manifest entry. If you don't patch it, the template defaults above are used.

### 1.5 User-Defined Network (OVN L2 overlay)

Each tenant gets a primary UserDefinedNetwork providing an isolated Layer 2 subnet via OVN-Kubernetes. The namespace is labelled with `k8s.ovn.org/primary-user-defined-network` automatically by the namespace template.

| Parameter | Field | Description |
|---|---|---|
| **UDN subnet** | `spec.layer2.subnets[]` | The private CIDR for the tenant's overlay network |

Pick a `/24` (or larger) from your internal UDN address plan. Subnets must not overlap across tenants.

| Tenant | UDN subnet |
|---|---|
| starwars | `10.0.1.0/24` |
| startrek | `10.0.2.0/24` |
| *your-tenant* | *next available* |

### 1.6 MetalLB VRF / BGP (external connectivity)

Each tenant can get its own MetalLB BGP peering session in a dedicated VRF for isolated egress/ingress to external networks. This creates three resources per tenant.

#### BGPPeer

| Parameter | Field | Description |
|---|---|---|
| **Peer ASN** | `spec.peerASN` | ASN of the upstream router for this tenant |
| **Peer address** | `spec.peerAddress` | IP address of the upstream BGP peer |
| **VRF name** | `spec.vrf` | Dedicated VRF name (e.g. `starwars-vrf`) |
| **Local ASN** | `spec.myASN` | Cluster-side ASN (default `64500`, shared across tenants in the template) |

#### IPAddressPool

| Parameter | Field | Description |
|---|---|---|
| **Egress/Ingress addresses** | `spec.addresses[]` | CIDR or range of external IPs assigned to this tenant's services |
| **Auto-assign** | `spec.autoAssign` | `true` by default — LoadBalancer services pick from this pool automatically |

#### BGPAdvertisement

Links the pool to the peer. No additional parameters — name references are derived from the BGPPeer and IPAddressPool names.

Example allocation plan:

| Tenant | Peer ASN | Peer address | VRF | IP pool |
|---|---|---|---|---|
| starwars | 64501 | 192.168.1.1 | starwars-vrf | 192.168.11.0/24 |
| startrek | 64502 | 192.168.1.2 | startrek-vrf | 192.168.12.0/24 |
| *your-tenant* | *next ASN* | *next peer* | *tenant-vrf* | *next pool* |

If a tenant does **not** need external BGP connectivity, omit the entire `metallb-vrf-bgp.yaml` manifest entry from its policy block.

### 1.7 Network isolation

Cross-tenant network isolation is handled by a single cluster-wide **AdminNetworkPolicy** (`policy-tenant-isolation-anp`). It denies all ingress and egress between namespaces labelled `customer-namespace: ""`. This label is set automatically by the namespace template.

No per-tenant configuration is needed — the ANP applies to every tenant namespace by label. Adding a new tenant namespace with the correct label automatically brings it under the isolation policy.

---

## 2. Files to edit

Three PolicyGenerator files need a new block each:

| File | What to add |
|---|---|
| `policygen/AC-Access-Control/policyGenerator-hub.yaml` | Hub RBAC: fleet ClusterRoleBindings + MulticlusterRoleAssignments |
| `policygen/AC-Access-Control/policyGenerator-managed.yaml` | Managed cluster RoleBindings in the tenant namespace |
| `policygen/CM-Configuration-Management/policyGenerator-managed.yaml` | Namespace, quotas, LimitRange, UDN, MetalLB |

No template files need editing — all tenant-specific values go in the `patches` blocks.

---

## 3. Step-by-step

### 3.1 Add hub RBAC (AC — policyGenerator-hub.yaml)

Add a new policy block in the `policies:` list. Copy an existing tenant block and replace:

```yaml
  - name: policy-tenant-TENANT-hub-rbac
    manifests:
      # ClusterRoleBinding: ACM console access for TENANT-admins
      - path: acm-finegrained-rbac/acm-fleet-clusterrolebinding.yaml
        patches:
          - metadata:
              name: customer-TENANT-acm-fleet-admin
            roleRef:
              name: acm-vm-fleet:admin
            subjects:
              - name: TENANT-admins
      # ClusterRoleBinding: ACM console access for TENANT-operators
      - path: acm-finegrained-rbac/acm-fleet-clusterrolebinding.yaml
        patches:
          - metadata:
              name: customer-TENANT-acm-fleet-operator
            roleRef:
              name: acm-vm-fleet:view
            subjects:
              - name: TENANT-operators
      # MulticlusterRoleAssignment: virt-admin on managed clusters
      - path: acm-finegrained-rbac/multiclusterroleassignment-virt.yaml
        patches:
          - metadata:
              name: customer-TENANT-virt-admin
            spec:
              subject:
                name: TENANT-admins
              roleAssignments:
                - name: customer-TENANT-virt-admin-kubevirt
                  clusterRole: kubevirt.io:admin
                  targetNamespaces:
                    - TENANT
                - name: customer-TENANT-virt-admin-extended
                  clusterRole: acm-vm-extended:admin
                  targetNamespaces:
                    - TENANT
      # MulticlusterRoleAssignment: virt-operator on managed clusters
      - path: acm-finegrained-rbac/multiclusterroleassignment-virt.yaml
        patches:
          - metadata:
              name: customer-TENANT-virt-operator
            spec:
              subject:
                name: TENANT-operators
              roleAssignments:
                - name: customer-TENANT-virt-operator-kubevirt
                  clusterRole: kubevirt.io:edit
                  targetNamespaces:
                    - TENANT
                - name: customer-TENANT-virt-operator-extended
                  clusterRole: acm-vm-extended:view
                  targetNamespaces:
                    - TENANT
```

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
                requests.cpu: "4"          # <-- adjust
                requests.memory: "16Gi"    # <-- adjust
                pods: "10"                 # <-- adjust
                requests.storage: "1000Gi" # <-- adjust
      - path: quota/application-aware-resource-quota.yaml
        patches:
          - metadata:
              name: TENANT-vm-resource-quota
              namespace: TENANT
            spec:
              hard:
                requests.cpu/vmi: "4"      # <-- adjust
                requests.memory/vmi: "16Gi"# <-- adjust
                limits.cpu/vmi: "4"        # <-- adjust
                limits.memory/vmi: "16Gi"  # <-- adjust
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
                  - "10.0.X.0/24"         # <-- next available UDN subnet
      - path: network/metallb-vrf-bgp.yaml
        patches:
          - metadata:
              name: TENANT-bgp-peer
            spec:
              peerASN: 64503              # <-- upstream ASN
              peerAddress: 192.168.1.X    # <-- upstream peer IP
              vrf: TENANT-vrf
          - metadata:
              name: TENANT-ip-pool
            spec:
              addresses:
                - 192.168.X.0/24          # <-- external IP pool
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

Delete the three policy blocks (hub RBAC, managed RBAC, managed config) from the PolicyGenerator files and push. The CM Application has `prune: true` so ArgoCD will remove the generated policies. ACM will then remove the resources from managed clusters.

The AC Application has `prune: false` — RBAC removals require a manual sync with pruning or direct cleanup to avoid accidental access revocation during refactoring.
