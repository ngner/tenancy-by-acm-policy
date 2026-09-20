# Keycloak / identity — status and future work

## Completed

### Tenant CRD `spec.identity` (replaces standalone `keycloak` section)

Implemented on the Tenant CRD and Create Tenant form:

| Original idea | Implemented as |
|---------------|----------------|
| Opt in/out of SSO | `spec.identity.enabled` |
| Keycloak namespace / instance | `spec.identity.keycloak.namespace`, `instanceName` |
| Opt out of realm creation | `spec.identity.keycloak.manageRealm` (false = existing realm only) |
| Disable seed users | `spec.identity.keycloak.seedUsers` |
| External OIDC | `spec.identity.provider: oidc` + `spec.identity.oidc` |
| Console IdP name, client ID, secret ref | `consoleLoginName`, `clientId`, `clientSecretRef` |
| Seed password + force change | `seedPassword`, `requirePasswordChange` |
| Demo login theme | `loginTheme` (when `manageRealm: true`) |

Not implemented: explicit `redirectUris` array (redirects are derived from Ingress domain + IdP name).

### Group mapper — DONE

`oidc-group-membership-mapper` on each `openshift-{tenant}` client in `realm-import-from-crd.yaml`.

### OAuth IdP registration — DONE (reconciler, not policy)

`identity-reconciler.yaml` CronJob patches `oauth/cluster` to add/update per-tenant OpenID IdPs, merges into the singleton (does not replace the list). Orphan IdPs and client secrets are removed when the Tenant CR is deleted. When `spec.identity.enabled` is false, the reconciler removes the IdP and client secret (and platform-managed Keycloak realms when `manageRealm` was true).

### Client secret lookup in realm import — DONE (with fallback)

`realm-import-from-crd.yaml` reads `clientSecretRef` (default `openshift-config/{tenant}-client-secret`) via `lookup`. A static fallback remains if the Secret is missing (workshop default).

Create Tenant form provisions the Secret in `openshift-config`.

### Realm lifecycle — DONE

| Concern | Mechanism |
|---------|-----------|
| `KeycloakRealmImport` prune | `pruneObjectBehavior: DeleteAll` on `tenancy-hub-keycloak-realms` |
| Orphan import CRs | Identity reconciler |
| OAuth IdP + client secret | Identity reconciler |
| Keycloak DB realm | Identity reconciler Admin API sweep |

### Hub fleet RBAC on tenant delete — known issue (documented)

MCRAs and `acm-vm-fleet:view` ClusterRoleBindings are **not** auto-pruned (`tenancy-access-control` Argo app has `prune: false`). Manual cleanup or future `pruneObjectBehavior` on `tenancy-hub-console-and-vm-rbac`. Does **not** block delete + recreate with the same tenant name.

See `docs/new-tenant.md` (tenant deletion table) and `keycloak/README.md`.

---

## Open / future work

### Client secret hardening (production)

- Remove the hardcoded fallback secret from `realm-import-from-crd.yaml` once all tenants use `clientSecretRef`.
- Optional dedicated policy template to emit Secrets (only if not using the form / external provisioning).
- Integrate SealedSecrets, External Secrets Operator, or Vault for secret generation and rotation.
- Remove `.gitleaks.toml` allowlist entry when fallback is gone.

### Seed user hardening (production)

Current: `seedPassword` on the Tenant CR (workshop only) and `requirePasswordChange`.

Future options:

- Per-tenant Secret lookup for bootstrap credentials (out-of-band Vault / SealedSecrets).
- One-time password generation via Vault.
- Post-bootstrap CronJob to disable or delete seed users.

### Explicit OAuth redirect URIs

Add `spec.identity.redirectUris` (or `keycloak.redirectUris`) for non-standard console URLs or multi-cluster hubs. Today redirects are built from Ingress domain lookup.

### Custom CSS themes

Remain **outside** production policy — use `apply-themes.sh` in demo-setups. Not planned for PolicyGenerator.

### Optional demo-only franchise realms

`argocd/application-tenancy-sc-hub-demo.yaml` for theme-only tenants without `spec.identity` (starwars, startrek, etc.). Workshop use only.
