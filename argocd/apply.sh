#!/usr/bin/env bash
#
# Apply ArgoCD resources to the cluster, automatically setting each
# Application's targetRevision to the current git branch.
#
# The checked-in YAML files always keep  targetRevision: master  so that
# merging a feature branch back to master never clobbers the default value.
# This script substitutes the real branch name at apply-time only.
#
# Usage:
#   argocd/apply.sh              # auto-detect current branch
#   argocd/apply.sh my-branch    # override branch name
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REV="master"

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

apply() {
    local file="$1"
    if [[ "$BRANCH" == "$DEFAULT_REV" ]]; then
        oc apply -f "$file"
    else
        sed "s|targetRevision: ${DEFAULT_REV}|targetRevision: ${BRANCH}|" "$file" \
            | oc apply -f -
    fi
}

echo "==> targetRevision: $BRANCH"
echo

# Phase 1: PolicyGenerator plugin (no targetRevision to patch)
echo "--- Phase 1: PolicyGenerator plugin ---"
oc apply -f "$SCRIPT_DIR/openshift-gitops-policygen.yaml"
echo "Waiting for repo-server rollout..."
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops --timeout=120s
echo

# Phase 2: project + applications (order matters: CRD before policies)
echo "--- Phase 2: AppProject + Applications (targetRevision: $BRANCH) ---"
oc apply -f "$SCRIPT_DIR/appproject.yaml"
apply "$SCRIPT_DIR/application-tenancy-base.yaml"
apply "$SCRIPT_DIR/application-placements.yaml"
apply "$SCRIPT_DIR/application-ac.yaml"
apply "$SCRIPT_DIR/application-cm.yaml"

echo
echo "==> Done. All applications now tracking: $BRANCH"
