#!/bin/bash
##############################################################################
# update-values.sh — patch kustomize overlay values for GitOps and Dev Spaces
#
# This script ONLY patches overlay kustomization.yaml files.
# It does NOT deploy anything. Deploy with:  ansible-playbook deploy.yaml
#
# HOW TO USE
#   1. Edit the VARIABLES sections below.
#   2. Set UPDATE_*=true for the projects you want to refresh.
#   3. Run from the repo root:
#        ./update-values.sh
#
# Backups of each touched kustomization.yaml are written next to the file
# (suffix .YYYYMMDD-HHMM) and are gitignored.
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

###############################################################################
# TOGGLE — which projects to update (true / false)
# These UPDATE_* flags only control this script — not deploy.yaml.
# Deploy toggles are: -e deploy_gitops / deploy_devspaces
###############################################################################
UPDATE_GITOPS=true
UPDATE_DEVSPACES=true

###############################################################################
# GITOPS — operator overlay (connected)
# Path: gitops/operator/overlays/connected/
###############################################################################
GITOPS_SUBSCRIPTION_CHANNEL="latest"            # connected GitOps channel
GITOPS_CATALOG_SOURCE="redhat-operators"        # connected CatalogSource

###############################################################################
# DEV SPACES — operator / argocd overlays
# Paths:
#   devspaces/operator/overlays/stable/
#   devspaces/argocd/
###############################################################################
# Operator Subscription (Red Hat OpenShift Dev Spaces)
# Package: devspaces  |  Channel typically stable
DEVSPACES_SUBSCRIPTION_CHANNEL="stable"
DEVSPACES_CATALOG_SOURCE="redhat-operators"

# Argo CD Application / AppProject source
DEVSPACES_GIT_REPO_HTTPS="https://github.com/ebeaudoi/ocp-gitops-devspace.git"
DEVSPACES_GIT_REPO_SSH="git@github.com:ebeaudoi/ocp-gitops-devspace.git"
DEVSPACES_GIT_TARGET_REVISION="main"

###############################################################################
# Helpers (do not edit)
###############################################################################
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M)"

replace_json6902_value() {
  local file="$1"
  local path="$2"
  local value="$3"
  python3 - "$file" "$path" "$value" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
json_path = sys.argv[2]
value = sys.argv[3]
lines = path.read_text().splitlines()
updated = False
i = 0
while i < len(lines):
    if lines[i].strip() == f"path: {json_path}":
        j = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        if j < len(lines) and lines[j].lstrip().startswith("value:"):
            indent = lines[j][: len(lines[j]) - len(lines[j].lstrip())]
            lines[j] = f"{indent}value: {value}"
            updated = True
            i = j
    i += 1
if not updated:
    raise SystemExit(f"Failed to update path {json_path} in {path}")
path.write_text("\n".join(lines) + "\n")
PY
}

update_gitops() {
  local op="gitops/operator/overlays/connected/kustomization.yaml"

  echo ""
  echo "------------------------------------------"
  echo "[GitOps] Updating operator overlay..."
  echo "  Channel: ${GITOPS_SUBSCRIPTION_CHANNEL}"
  echo "  Catalog: ${GITOPS_CATALOG_SOURCE}"
  echo "------------------------------------------"

  cp "${op}"{,."${BACKUP_SUFFIX}"}
  replace_json6902_value "${op}" "/spec/channel" "${GITOPS_SUBSCRIPTION_CHANNEL}"
  replace_json6902_value "${op}" "/spec/source" "${GITOPS_CATALOG_SOURCE}"
  echo "    Done."
}

update_devspaces() {
  local op="devspaces/operator/overlays/stable/kustomization.yaml"
  local argocd="devspaces/argocd/kustomization.yaml"

  echo ""
  echo "------------------------------------------"
  echo "[Dev Spaces] Updating overlays..."
  echo "  Channel:          ${DEVSPACES_SUBSCRIPTION_CHANNEL}"
  echo "  Catalog:          ${DEVSPACES_CATALOG_SOURCE}"
  echo "  Git HTTPS:        ${DEVSPACES_GIT_REPO_HTTPS}"
  echo "  Git SSH:          ${DEVSPACES_GIT_REPO_SSH}"
  echo "  Target revision:  ${DEVSPACES_GIT_TARGET_REVISION}"
  echo "------------------------------------------"

  cp "${op}"{,."${BACKUP_SUFFIX}"}
  cp "${argocd}"{,."${BACKUP_SUFFIX}"}

  # Operator Subscription
  replace_json6902_value "${op}" "/spec/channel" "${DEVSPACES_SUBSCRIPTION_CHANNEL}"
  replace_json6902_value "${op}" "/spec/source" "${DEVSPACES_CATALOG_SOURCE}"

  # Argo CD Application + AppProject
  replace_json6902_value "${argocd}" "/spec/source/repoURL" "${DEVSPACES_GIT_REPO_HTTPS}"
  replace_json6902_value "${argocd}" "/spec/source/targetRevision" "${DEVSPACES_GIT_TARGET_REVISION}"
  replace_json6902_value "${argocd}" "/spec/sourceRepos/0" "${DEVSPACES_GIT_REPO_HTTPS}"
  replace_json6902_value "${argocd}" "/spec/sourceRepos/1" "${DEVSPACES_GIT_REPO_SSH}"

  echo "    Done."
}

###############################################################################
# Run
###############################################################################
echo "=========================================="
echo "update-values.sh  (patches overlays only — does not deploy)"
echo "  UPDATE_GITOPS     = ${UPDATE_GITOPS}"
echo "  UPDATE_DEVSPACES  = ${UPDATE_DEVSPACES}"
echo "  Backup suffix     = .${BACKUP_SUFFIX}"
echo "=========================================="

if [[ "${UPDATE_GITOPS}" == "true" ]]; then
  update_gitops
fi

if [[ "${UPDATE_DEVSPACES}" == "true" ]]; then
  update_devspaces
fi

echo ""
echo "=========================================="
echo "Update completed."
echo "Deploy with:  ansible-playbook deploy.yaml"
echo "=========================================="
