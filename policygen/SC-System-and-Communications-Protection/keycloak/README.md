# Keycloak realm policy

The `tenancy-hub-keycloak-realms` policy (hub only) creates a `KeycloakRealmImport`
**only when** `spec.identity.keycloak.manageRealm: true`. The identity reconciler
registers OpenShift OAuth IdPs for all identity-enabled tenants regardless.

## Production vs demo

| Concern | Production (Argo SC policy) | Demo / workshop (outside or optional) |
|---------|----------------------------|----------------------------------------|
| OpenShift OAuth IdP | Identity reconciler CronJob | Same |
| Keycloak realm CR | Only if `manageRealm: true` | Optional greenfield workshops |
| Seed users | Only if `manageRealm` + `seedUsers: true` | Workshop bootstrap |
| Custom CSS themes | **Not in policy** | `apply-themes.sh` in demo-setups |
| Legacy franchise tenants (no `spec.identity`) | **Not in production policy** | Optional app `tenancy-sc-hub-demo` |

### Production paths

1. **External OIDC** (`provider: oidc`) — reconciler registers IdP; customer completes external app registration using `status.identity.externalSetupNotes`.
2. **Existing customer Keycloak** (`provider: keycloak`, `manageRealm: false`) — customer realm and OIDC client already exist; platform stores client secret and registers OpenShift IdP against `https://<keycloak-route>/realms/<realm>`.
3. **Greenfield Keycloak tenant** (`manageRealm: true`) — rare; creates realm, groups, optional seed users, and OAuth client via `KeycloakRealmImport`. Keycloak instance must already be installed.

### Demo workshop path

- Enable optional Argo app `tenancy-sc-hub-demo` for franchise tenants **without** `spec.identity` (starwars, startrek).
- Use `apply-themes.sh` for CSS themes and Keycloak volume mounts — never part of production policy.
- For ACM tenants with identity, set `manageRealm: true` and optionally `seedUsers: true` in the Create Tenant form.

## Opt-in console SSO (`spec.identity`)

Tenants **without** `spec.identity` are not enrolled in console SSO automation.

| `provider` | `manageRealm` | Policy behaviour | IdP registration |
|------------|---------------|------------------|------------------|
| `keycloak` | `false` | No realm import | CronJob adds `{tenant}-idp` to `oauth/cluster` |
| `keycloak` | `true` | `KeycloakRealmImport` | CronJob adds IdP |
| `oidc` | n/a | No realm import | CronJob adds IdP; external setup notes in status |

Required fields when enabled:

- `clientSecretRef` — Secret in `openshift-config` (create via form or CLI; never store the value on the CR)
- `keycloak.namespace` / `keycloak.instanceName` — which Keycloak CR to use (must exist before SSO works)

See [`examples/tenant-gigashadow-identity.yaml`](../../../examples/tenant-gigashadow-identity.yaml).

## Seed users

When `manageRealm` and `seedUsers` are both true, each tenant realm is bootstrapped with demo users. Console display names use the tenant name as the last name (for example `Admin Lexx`, `User Firefly`) so IdP pickers are easy to tell apart:

| Username | Display name | Group | Default password |
|----------|--------------|-------|------------------|
| `admin@<tenant>.local` | `Admin <Tenant>` | `<tenant>-tenant-admin` | `spec.identity.keycloak.seedPassword` (default `password`) |
| `user@<tenant>.local` | `User <Tenant>` | `<tenant>-tenant-user` | same |
| `viewer@<tenant>.local` | `Viewer <Tenant>` | `<tenant>-tenant-viewer` | same |

Set `requirePasswordChange: true` to force a password change on first login (Keycloak `temporary` credential).

These are **workshop bootstrap accounts only** — the password is stored in plain text on the Tenant CR.

## OIDC client and OpenShift login

Each managed realm includes an `openshift-<tenant>` client with console redirect URIs and a group mapper. When `manageRealm` is false, the customer must configure an equivalent client in their existing realm.

## Custom login themes

Custom CSS is **not** deployed by production policy. Optional `spec.identity.keycloak.loginTheme` applies only when `manageRealm: true` (demo). Prefer `apply-themes.sh` for workshop themes.

## Tenant deletion

When a `Tenant` CR is **deleted**:

1. **KeycloakRealmImport** — removed when `manageRealm` was true (`pruneObjectBehavior: DeleteAll`).
2. **OAuth IdP + client secret** — removed by the identity reconciler CronJob.
3. **Custom CSS themes** — left in place. `apply-themes.sh` mounts every `themes/*.css` once; tenant delete does not unmount them. Pass `--purge-themes` only if you intentionally want the CSS removed.
4. **Hub fleet RBAC** — known issue: not auto-pruned on tenant delete (see [TODO.md](TODO.md#hub-fleet-rbac-on-tenant-delete--known-issue-documented)).

## Disabling console SSO (`spec.identity.enabled: false`)

When SSO is turned off on an existing tenant (Tenant CR kept):

1. **OpenShift OAuth IdP** — removed by the identity reconciler (matches `openshift-{tenant}` client ID).
2. **Client secret** — deleted from `openshift-config` (or `clientSecretRef` namespace).
3. **KeycloakRealmImport + DB realm** — removed only when `keycloak.manageRealm` was true (platform-managed realm). Customer-owned realms (`manageRealm: false`) are not deleted from Keycloak.
4. **Re-enable** — supply a new client secret in the form; reconciler registers a fresh IdP on the next cycle.

The Create Tenant form preserves `clientSecretRef` and `manageRealm` hints on the CR when disabling so the reconciler can clean up safely.

## Further work

See [TODO.md](TODO.md) for completed items and remaining production hardening.
