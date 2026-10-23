# ocp-gitops-devspace

Deploy **OpenShift GitOps**, then use Argo CD to install **Red Hat OpenShift Dev Spaces**.

Repo: [https://github.com/ebeaudoi/ocp-gitops-devspace.git](https://github.com/ebeaudoi/ocp-gitops-devspace.git)

## Index

| Section | Description |
|---------|-------------|
| [Repository layout](#repository-layout) | What each path contains |
| [Quick start](#quick-start) | Configure values and run the playbook |
| [What gets installed](#what-gets-installed) | GitOps + Dev Spaces stages |
| [Deploy options](#deploy-options) | Full stack, Argo CD only, or Kustomize only |
| [Verify](#verify) | Commands to confirm the install |
| [GitOps guide](gitops/README.md) | OpenShift GitOps operator and Argo CD instance |
| [Dev Spaces guide](devspaces/README.md) | Operator, CheCluster, AppProject, Application |

### Repository layout

| Path | Description |
|------|-------------|
| [`update-values.sh`](update-values.sh) | Patch GitOps / Dev Spaces channel, catalog, and Git repo overlays |
| [`deploy.yaml`](deploy.yaml) | Ansible playbook (GitOps bootstrap + Dev Spaces Argo CD app) |
| [`gitops/`](gitops/) | OpenShift GitOps kustomize (operator + Argo CD instance) |
| [`gitops/README.md`](gitops/README.md) | GitOps deploy and admin-user notes |
| [`devspaces/`](devspaces/) | Dev Spaces operator, CheCluster instance, and Argo CD manifests |
| [`devspaces/README.md`](devspaces/README.md) | Full Dev Spaces guide (manual, Argo CD, customize) |
| [`devspaces/argocd/`](devspaces/argocd/) | AppProject `devspaces` + Application `devspaces` |
| [`devspaces/overlays/full/`](devspaces/overlays/full/) | Aggregate overlay synced by Argo CD |

## Quick start

```bash
# 1. Configure GitOps + Dev Spaces overlay params (optional)
vim update-values.sh   # UPDATE_GITOPS / UPDATE_DEVSPACES + channel / repo vars
./update-values.sh

# 2. Optional: add Argo CD admin users
vim gitops/instance/overlays/connected/gitops-admins-group.yaml

# 3. Login and kubeconfig
oc login --server=<api-url> --token=<token>
oc config view --raw > "$HOME/ocpkubeconfig"

# 4. Install Ansible collection
ansible-galaxy collection install kubernetes.core

# 5. Push this repo to main (Argo CD syncs from GitHub), then deploy
ansible-playbook deploy.yaml
```

| Flag | Effect |
|------|--------|
| `-e deploy_gitops=false` | Skip OpenShift GitOps |
| `-e deploy_devspaces=false` | Skip Dev Spaces AppProject / Application |
| `--tags gitops` | Only GitOps |
| `--tags devspaces` | Only Dev Spaces Argo CD resources |

## What gets installed

| Stage | Where |
|-------|--------|
| GitOps operator | `openshift-gitops-operator` |
| Argo CD instance | `openshift-gitops` |
| Dev Spaces AppProject + Application | `openshift-gitops` → syncs Dev Spaces |

## Deploy options

### A) Full stack (GitOps + Argo CD Application)

```bash
./update-values.sh
ansible-playbook deploy.yaml
```

### B) Dev Spaces only via Argo CD (GitOps already installed)

```bash
oc apply -k devspaces/argocd
# or
ansible-playbook deploy.yaml -e deploy_gitops=false --tags devspaces
```

### C) Kustomize only (no Argo CD)

```bash
oc apply -k devspaces/operator/overlays/stable
# wait for CSV / CheCluster CRD
oc apply -k devspaces/instance/overlays/default

# or both:
oc apply -k devspaces/overlays/full
```

## Verify

```bash
oc get csv -n openshift-gitops-operator
oc get argocd,route -n openshift-gitops
oc get appproject,application -n openshift-gitops
oc get application devspaces -n openshift-gitops
oc get checluster,pods,route -n openshift-devspaces
```

Push this repo to `main` before Argo CD can sync Dev Spaces.
