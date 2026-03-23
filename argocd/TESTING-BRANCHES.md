# Testing feature branches

The Application YAMLs in this directory hardcode `targetRevision: master`.
When working on a feature branch you need ArgoCD to track that branch instead,
but the committed files must stay unchanged so merging back to `master` doesn't
clobber the default value.

`apply.sh` solves this by substituting `targetRevision` at apply-time only —
the YAML files in git are never modified.

## Quick start

```bash
# From the feature branch — auto-detects the current branch
git checkout feature/hub-range-tenant-replication
argocd/apply.sh
# ==> targetRevision: feature/hub-range-tenant-replication
```

## Switch back to master

```bash
git checkout master
argocd/apply.sh
# ==> targetRevision: master
```

## Override the branch explicitly

Useful when you want to point ArgoCD at a branch you haven't checked out
locally:

```bash
argocd/apply.sh some-other-branch
```

## What the script does

1. Detects the current git branch (or accepts one as an argument).
2. Applies `openshift-gitops-policygen.yaml` and waits for the repo-server
   rollout (Phase 1 — no `targetRevision` to patch).
3. Applies `appproject.yaml` as-is.
4. For each `application-*.yaml`, pipes the file through `sed` to replace
   `targetRevision: master` with the detected branch, then applies via
   `oc apply -f -`.

On `master` the `sed` substitution is a no-op, so the behaviour is identical
to a plain `oc apply`.

## Why this doesn't clobber master on merge

The feature branch never commits a change to `targetRevision` in any YAML file.
The substitution is ephemeral — it only exists in the pipe to `oc apply`.
When the feature branch is merged, the Application files still say
`targetRevision: master`.
