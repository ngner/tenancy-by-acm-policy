#!/usr/bin/env bash
# Apply golden sample tenants (SSO + workloadProfile: vms) AFTER Keycloak is Ready.
#
# These are NOT managed by Argo tenancy-base (tenancies/ stays empty, prune=false).
# Prefer Create Tenant in the console for live demos; use this for workshop bootstrap.
#
# Usage:
#   examples/apply-samples.sh              # starwars + startrek
#   examples/apply-samples.sh starwars     # one tenant
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged in. Set KUBECONFIG (and HTTPS_PROXY if using a bastion)."
  exit 1
fi

if ! oc get keycloak main -n keycloak-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
  echo "ERROR: Keycloak main in keycloak-system is not Ready."
  echo "    Run: ./bin/apply acm-tenancy-keycloak"
  exit 1
fi

# With set -u, "${@}" errors when no args are passed (bash 4.4+).
if [[ $# -eq 0 ]]; then
  TENANTS=(starwars startrek)
else
  TENANTS=("$@")
fi

for t in "${TENANTS[@]}"; do
  f="${SCRIPT_DIR}/tenant-${t}.yaml"
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found"
    exit 1
  fi
  echo "==> Applying sample tenant: $t"
  oc apply -f "$f"
done

echo ""
echo "==> Waiting for identity Ready (up to ~3 min)..."
for t in "${TENANTS[@]}"; do
  for i in $(seq 1 36); do
    phase=$(oc get tenant "$t" -n tenancies -o jsonpath='{.status.identity.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Ready" ]]; then
      echo "    $t: identity Ready"
      break
    fi
    if [[ $i -eq 6 ]] && oc get cronjob tenant-identity-reconciler -n tenancies &>/dev/null; then
      job="tenant-identity-reconciler-samples-$(date +%s)"
      oc create job --from=cronjob/tenant-identity-reconciler "$job" -n tenancies 2>/dev/null || true
    fi
    if [[ $i -eq 36 ]]; then
      echo "    Warning: $t identity.phase=${phase:-unknown} (check policies / reconciler)"
    fi
    sleep 5
  done
done

echo ""
echo "==> Done. Sample tenants applied (not Argo-managed)."
echo "    oc get tenants -n tenancies"
echo "    Console IdPs: $(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' 2>/dev/null || echo '(none)')"
echo "    Seed users: admin@<tenant>.local (password from example YAML seedPassword, often HugAPug2026!)"
