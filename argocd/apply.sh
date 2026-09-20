#!/usr/bin/env bash
#
# Apply ArgoCD resources to the cluster, automatically setting each
# Application's targetRevision to the current git branch and repoURL to
# this clone's origin (when using a fork).
#
# The checked-in YAML files keep targetRevision: master and ngner repoURL
# so merging to upstream never clobbers defaults. This script patches at apply-time.
#
# Usage:
#   argocd/apply.sh              # auto-detect current branch + origin
#   argocd/apply.sh my-branch    # override branch name
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_REV="master"
DEFAULT_REPO="https://github.com/ngner/tenancy-by-acm-policy"

BRANCH="${1:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$DEFAULT_REV")}"
if [[ "$BRANCH" == "HEAD" ]]; then
  BRANCH="${TENANCY_POLICY_BRANCH:-$DEFAULT_REV}"
fi

REPO_URL="${TENANCY_POLICY_REPO_URL:-}"
if [[ -z "$REPO_URL" ]]; then
  origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    git@github.com:*)
      REPO_URL="https://github.com/${origin#git@github.com:}"
      REPO_URL="${REPO_URL%.git}"
      ;;
    http*)
      REPO_URL="${origin%.git}"
      # Strip embedded credentials (e.g. https://user@github.com/...) so AppProject sourceRepos match.
      REPO_URL="${REPO_URL#https://*@}"
      REPO_URL="${REPO_URL#http://*@}"
      [[ "$REPO_URL" != http* ]] && REPO_URL="https://${REPO_URL}"
      ;;
  esac
fi
[[ -z "$REPO_URL" ]] && REPO_URL="$DEFAULT_REPO"
REPO_URL="${REPO_URL%.git}"

apply() {
    local file="$1"
    local content
    content=$(cat "$file")
    if [[ "$BRANCH" != "$DEFAULT_REV" ]]; then
        content=$(echo "$content" | sed "s|targetRevision: ${DEFAULT_REV}|targetRevision: ${BRANCH}|")
    fi
    if [[ "$REPO_URL" != "$DEFAULT_REPO" ]]; then
        # YAML may use repoURL with or without a trailing .git
        content=$(echo "$content" | sed -E "s|repoURL: ${DEFAULT_REPO}(\.git)?|repoURL: ${REPO_URL}|g")
    fi
    echo "$content" | oc apply -f -
}

echo "==> repoURL:        $REPO_URL"
echo "==> targetRevision: $BRANCH"
echo

# Phase 1: PolicyGenerator plugin (no targetRevision to patch)
echo "--- Phase 1: PolicyGenerator plugin ---"
oc apply -f "$SCRIPT_DIR/openshift-gitops-policygen.yaml"
echo "Waiting for repo-server rollout..."
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops --timeout=120s
echo

# Phase 2: project + applications (order matters: CRD before policies)
echo "--- Phase 2: AppProject + Applications ---"
oc apply -f "$SCRIPT_DIR/appproject.yaml"
apply "$SCRIPT_DIR/application-tenancy-base.yaml"
apply "$SCRIPT_DIR/application-tenancy-placements.yaml"
apply "$SCRIPT_DIR/application-tenancy-access-control.yaml"
apply "$SCRIPT_DIR/application-tenancy-configuration-management.yaml"
apply "$SCRIPT_DIR/application-tenancy-system-and-communications-protection.yaml"

echo
echo "==> Done. Applications track $REPO_URL @ $BRANCH"
echo "    Override with TENANCY_POLICY_REPO_URL / TENANCY_POLICY_BRANCH (or pass branch as \$1)."
