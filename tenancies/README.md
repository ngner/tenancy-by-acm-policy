# Tenant CRs

This directory is synced by Argo CD Application **`tenancy-base`** and is
**intentionally empty**. Sample tenants are **not** GitOps-managed here.

## Why empty + prune false

| Setting | Value | Reason |
|---------|-------|--------|
| `tenancies/` contents | empty | Create Tenant UI (or example YAML) owns Tenant CRs |
| `tenancy-base` `automated.prune` | **false** | Empty Git + prune would delete any live Tenant CRs |

Do **not** commit starwars/startrek into this folder unless you deliberately want Argo to own them.

## How to provision sample tenants

**After** Keycloak is Ready (`./bin/apply acm-tenancy-keycloak`):

```bash
# Workshop / fast path — golden SSO examples
content/tenancy-by-acm-policy/examples/apply-samples.sh

# Or one at a time
oc apply -f content/tenancy-by-acm-policy/examples/tenant-starwars.yaml
oc apply -f content/tenancy-by-acm-policy/examples/tenant-startrek.yaml

# Or live demo — Create Tenant in the ACM console (/tenant-create) with SSO enabled
```

Reference examples:

- [`examples/tenant-starwars.yaml`](../examples/tenant-starwars.yaml) — `workloadProfile: vms` + Keycloak SSO
- [`examples/tenant-startrek.yaml`](../examples/tenant-startrek.yaml) — same
- [`examples/tenant-gigashadow-identity.yaml`](../examples/tenant-gigashadow-identity.yaml)

Each example includes an `openshift-config` client secret plus `spec.identity`
(`manageRealm` + `seedUsers`). Do **not** apply `10-tenant-groups.yaml` for this
path — the HTPasswd OAuth file was removed, and groups come from Keycloak OIDC claims.

ACM policies then provision namespaces, quotas, UDN, MetalLB, Keycloak realms,
OAuth IdPs, and (by default) a starter VM.

## Argo source

Point apps at your fork when developing:

```bash
export TENANCY_POLICY_REPO_URL=https://github.com/mandibuswell/tenancy-by-acm-policy
export TENANCY_POLICY_BRANCH=master
cd content/tenancy-by-acm-policy && ./argocd/apply.sh
```

`use-cases/acm-tenancy/apply.sh` defaults to that fork for demos.
