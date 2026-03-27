# Keycloak Realm Policy — Future Work

## Extend Tenant CRD with `keycloak` section

Add optional per-tenant overrides to the Tenant CRD:

- `keycloak.enabled` (boolean) — opt out of realm creation for specific tenants
- `keycloak.namespace` (string) — target a different Keycloak instance namespace
- `keycloak.instanceName` (string) — reference a Keycloak CR other than `main`
- `keycloak.redirectUris` (array) — explicit OAuth callback URLs per tenant
- `keycloak.seedAdmin.enabled` (boolean) — disable seed user creation

This would allow multiple Keycloak instances serving different sets of tenants
and per-tenant opt-out without removing the Tenant CR.

## Client secret management — DONE (static secret)

A static client secret and proper redirect URI are now set on each
`openshift-{tenant}` client in `realm-import-from-crd.yaml`. The redirect URI
is derived from an Ingress config `lookup` at policy evaluation time.

### Replacing the hardcoded secret with a `lookup`

The static secret should be replaced with a dynamic `lookup` once the
per-tenant Secrets exist in `openshift-config`. The approach:

1. Create a new template (e.g., `client-secret-from-crd.yaml`) that iterates
   Tenant CRs and emits a Secret per tenant in `openshift-config`:

   ```yaml
   object-templates-raw: |
     {{- range $tenant := (lookup "dusty-seahorse.io/v1alpha1" "Tenant" "tenancies" "").items }}
     {{- $name := $tenant.metadata.name }}
     - complianceType: musthave
       objectDefinition:
         apiVersion: v1
         kind: Secret
         metadata:
           name: {{ $name }}-client-secret
           namespace: openshift-config
         type: Opaque
         stringData:
           clientSecret: <generated-or-vault-sourced-value>
     {{- end }}
   ```

2. In `realm-import-from-crd.yaml`, replace the hardcoded `secret:` line with
   a `lookup` of that Secret:

   ```yaml
   {{- $clientSecret := (lookup "v1" "Secret" "openshift-config" (printf "%s-client-secret" $name)).data.clientSecret | base64dec }}
   ...
   secret: '{{ $clientSecret }}'
   ```

3. Add a policy dependency so the Keycloak realm import waits for the Secrets
   to exist before evaluating.

This removes the hardcoded secret from git and keeps the Keycloak client
secret in sync with the OpenShift OAuth configuration. It also eliminates
the `.gitleaks.toml` allowlist entry.

### Remaining production hardening

- Generate or reference per-tenant OIDC client secrets via SealedSecrets,
  External Secrets Operator, or HashiCorp Vault.
- Create the corresponding `Secret` in `openshift-config` for each tenant so
  the OpenShift OAuth server can complete the IdP handshake.

## Seed admin password hardening

The bootstrap user currently uses a hardcoded `changeme` password with
`temporary: true`. Stronger options:

- **Per-tenant Secret lookup** — template uses `lookup` to read a Secret named
  `{tenant}-seed-credentials` from the Keycloak namespace and injects the
  password value. Secrets are provisioned out-of-band via Vault or
  SealedSecrets.
- **One-time password generation** — integrate with Vault's password generator
  to produce a unique bootstrap password per tenant.
- **Disable seed user post-bootstrap** — a follow-up policy or CronJob that
  disables or deletes the seed user after the tenant admin has created their
  own account.

## OAuth IdP auto-registration

Create a policy that patches `OAuth/cluster` to add a per-tenant IdP entry:

```yaml
- name: {tenant}-idp
  type: OpenID
  openID:
    clientID: openshift-{tenant}
    clientSecret:
      name: {tenant}-client-secret
    issuer: https://<keycloak-route>/realms/{tenant}
    claims:
      groups: [groups]
      preferredUsername: [preferred_username]
      name: [name]
      email: [email]
```

This is complex because the `OAuth/cluster` resource is a singleton — the
policy must merge IdP entries rather than replace the list. Consider using
`musthave` with a partial object or a server-side apply strategy.

## Group mapper automation — DONE

An `oidc-group-membership-mapper` protocol mapper is now defined directly on
each `openshift-{tenant}` client in `realm-import-from-crd.yaml`. The mapper
emits a `groups` claim with `full.path: false` into ID, access, and userinfo
tokens.

## Realm lifecycle

- Handle tenant deletion and realm cleanup. Currently, removing a Tenant CR
  leaves the Keycloak realm orphaned. Consider setting `pruneObjectBehavior:
  DeleteAll` on the policy or implementing a finalizer-based cleanup.
- Realm import is additive — the RHBK Operator does not remove groups, roles,
  or users that were deleted from the import spec. Document this behavior and
  consider periodic reconciliation via the Keycloak Admin API if strict
  declarative management is required.
