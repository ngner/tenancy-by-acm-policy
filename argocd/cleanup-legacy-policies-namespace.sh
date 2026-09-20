#!/usr/bin/env bash
# Remove tenant Policy/MCRA/Placement resources left in the legacy policies namespace
# after consolidating everything into tenancies. Safe to re-run (ignore-not-found).
set -euo pipefail

NS=policies

echo "==> Cleaning legacy tenant resources in namespace: ${NS}"

echo "    Policies..."
oc delete policy -n "$NS" -l 'policy.open-cluster-management.io/policy-set' --ignore-not-found 2>/dev/null || true
for p in $(oc get policy -n "$NS" -o name 2>/dev/null | grep tenancy || true); do
  oc delete "$p" -n "$NS" --ignore-not-found
done

echo "    PolicySets..."
for ps in $(oc get policyset -n "$NS" -o name 2>/dev/null | grep tenancy || true); do
  oc delete "$ps" -n "$NS" --ignore-not-found
done

echo "    PlacementBindings..."
for pb in $(oc get placementbinding -n "$NS" -o name 2>/dev/null | grep tenancy || true); do
  oc delete "$pb" -n "$NS" --ignore-not-found
done

echo "    Placements..."
for pl in policies-placement-hub-clusters policies-placement-managed-clusters policies-placement-managed-vm-clusters; do
  oc delete placement "$pl" -n "$NS" --ignore-not-found
done

echo "    MulticlusterRoleAssignments (hub objects that lived in policies ns)..."
for m in $(oc get mcra -n "$NS" -o name 2>/dev/null || true); do
  oc delete "$m" -n "$NS" --ignore-not-found
done

echo "==> Done. Verify: oc get policy,policyset,placementbinding,placement,mcra -n ${NS}"
