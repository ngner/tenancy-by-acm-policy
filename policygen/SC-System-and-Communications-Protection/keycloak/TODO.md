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

## Client secret management

The current implementation omits the OIDC client secret and uses a wildcard
redirect URI. Production deployments require:

- Generate or reference per-tenant OIDC client secrets via SealedSecrets,
  External Secrets Operator, or HashiCorp Vault.
- Create a corresponding `Secret` in `openshift-config` for each tenant so the
  OpenShift OAuth server can complete the IdP handshake.
- A new template (`client-secret-from-crd.yaml`) that iterates Tenant CRs and
  emits Secrets in `openshift-config` with the client secret value.
- Replace the wildcard `redirectUris: ["*"]` with the actual
  `oauth-openshift.apps.<cluster>/oauth2callback/<tenant>-idp` callback URL.

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

## Group mapper automation

Include the Group Membership protocol mapper in the realm import so that
tokens automatically contain the `groups` claim without manual Keycloak
console configuration:

```yaml
clientScopes:
  - name: openshift-{tenant}-dedicated
    protocol: openid-connect
    protocolMappers:
      - name: groups-mapper
        protocol: openid-connect
        protocolMapper: oidc-group-membership-mapper
        config:
          claim.name: groups
          full.path: "false"
          id.token.claim: "true"
          access.token.claim: "true"
```

## Realm lifecycle

- Handle tenant deletion and realm cleanup. Currently, removing a Tenant CR
  leaves the Keycloak realm orphaned. Consider setting `pruneObjectBehavior:
  DeleteAll` on the policy or implementing a finalizer-based cleanup.
- Realm import is additive — the RHBK Operator does not remove groups, roles,
  or users that were deleted from the import spec. Document this behavior and
  consider periodic reconciliation via the Keycloak Admin API if strict
  declarative management is required.
