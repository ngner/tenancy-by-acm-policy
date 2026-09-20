#!/usr/bin/env bash
# Label managed clusters with tenancy capability flags.
# Usage: ./label-cluster-capabilities.sh aws-us container
#        ./label-cluster-capabilities.sh virtualisation-cluster both
set -euo pipefail

CLUSTER="${1:?cluster name required}"
PROFILE="${2:?profile required: container | vm | both}"

case "$PROFILE" in
  container)
    oc label managedcluster "$CLUSTER" \
      tenancy.acm.io/capability-container=true --overwrite
    oc label managedcluster "$CLUSTER" tenancy.acm.io/capability-vm- --overwrite 2>/dev/null || true
    ;;
  vm)
    oc label managedcluster "$CLUSTER" \
      tenancy.acm.io/capability-vm=true --overwrite
    oc label managedcluster "$CLUSTER" tenancy.acm.io/capability-container- --overwrite 2>/dev/null || true
    ;;
  both)
    oc label managedcluster "$CLUSTER" \
      tenancy.acm.io/capability-container=true \
      tenancy.acm.io/capability-vm=true --overwrite
    ;;
  *)
    echo "Unknown profile: $PROFILE (use container, vm, or both)" >&2
    exit 1
    ;;
esac

echo "==> $CLUSTER capability labels:"
oc get managedcluster "$CLUSTER" --show-labels | tail -1 | tr ' ' '\n' | grep 'tenancy.acm.io/' || echo "(none)"
