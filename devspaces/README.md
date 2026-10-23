# OpenShift Dev Spaces

GitOps-ready install of **Red Hat OpenShift Dev Spaces** (CheCluster).

This deploys:

1. OLM **Subscription** for package `devspaces` into `openshift-operators`
2. Operand namespace `openshift-devspaces` + **CheCluster** (`devspaces`) + NetworkPolicy

---

## Folder layout

```
devspaces/
├── operator/                 # Subscription (cluster-scoped via openshift-operators)
│   ├── base/
│   └── overlays/stable/      # channel: stable, catalog: redhat-operators
├── instance/                 # Namespace + CheCluster + NetworkPolicy
│   ├── base/
│   ├── components/           # Optional: allow-autoscaling, low-idle
│   └── overlays/
│       ├── default/
│       └── allow-autoscaling/
├── overlays/full/            # Operator + instance (default)
├── argocd/                   # AppProject + Application
└── README.md
```

---

## Prerequisites

- OpenShift cluster with **OLM** and the **redhat-operators** catalog
- Cluster-admin (or equivalent) access
- A default **StorageClass** for workspace PVCs
- For GitOps: **OpenShift GitOps** (Argo CD) in namespace `openshift-gitops`

---

## What gets deployed

| Piece | Kind | Namespace | Purpose |
| --- | --- | --- | --- |
| Operator | `Subscription` (`devspaces`) | `openshift-operators` | Installs Dev Spaces (+ DevWorkspace) operator |
| Operand NS | `Namespace` | `openshift-devspaces` | Home for CheCluster / dashboard / gateway |
| Instance | `CheCluster` (`devspaces`) | `openshift-devspaces` | Deploys Dev Spaces services |
| NetPol | `NetworkPolicy` (`allow-from-openshift-devspaces`) | `openshift-devspaces` | Allow pod-to-pod traffic inside the NS |
| NetPol | `NetworkPolicy` (`allow-from-openshift-ingress`) | `openshift-devspaces` | Allow OpenShift router → gateway (required for the Route) |

Sync order (Argo CD waves):

1. Wave `0` — Subscription  
2. Wave `1` — Namespace + NetworkPolicy  
3. Wave `2` — CheCluster (waits for the CRD from the operator)

---

## Deploy with Argo CD (recommended)

### 0. Install OpenShift GitOps (if needed)

From the repo root:

```bash
./update-values.sh
ansible-playbook deploy.yaml
```

GitOps only:

```bash
ansible-playbook deploy.yaml -e deploy_devspaces=false --tags gitops
```

### 1. Push this repo

Make sure `main` on GitHub includes these manifests.

Repo used by the Application:

`https://github.com/ebeaudoi/ocp-gitops-devspace.git`

### 2. Apply the Argo CD project + app

If GitOps is already installed and you only need the Dev Spaces Application:

```bash
ansible-playbook deploy.yaml -e deploy_gitops=false --tags devspaces

# or manually
oc apply -k devspaces/argocd
```

That creates:

- **ClusterRole / ClusterRoleBinding** for the GitOps application-controller (NetworkPolicy, CheCluster, Subscription, …)
- **AppProject** `devspaces`
- **Application** `devspaces` — syncs `overlays/full` with auto-sync, prune, and self-heal

### 3. Watch the sync

```bash
oc get application devspaces -n openshift-gitops
oc get csv -n openshift-operators | grep -E 'devspaces|devworkspace'
oc get checluster -n openshift-devspaces
oc get pods -n openshift-devspaces
oc get route -n openshift-devspaces
```

Wait until the Application is `Synced` / `Healthy`, the CheCluster status is `Available`, and the dashboard Route exists.

---

## Deploy without Argo CD (manual)

```bash
oc apply -k devspaces/operator/overlays/stable
oc get csv -n openshift-operators | grep devspaces

# Wait until the CheCluster CRD exists, then:
oc apply -k devspaces/instance/overlays/default

# Or both at once (CheCluster may fail once until the CRD exists — re-apply)
oc apply -k devspaces/overlays/full
```

Optional GPU / autoscaling-friendly instance:

```bash
oc apply -k devspaces/instance/overlays/allow-autoscaling
```

To use that overlay with Argo CD, change `spec.source.path` in `argocd/application.yaml` (or the patch in `argocd/kustomization.yaml`) to `devspaces/overlays/full` after pointing `overlays/full` at `instance/overlays/allow-autoscaling`, or create a dedicated aggregate overlay.

---

## Verify

```bash
oc get subscription,csv -n openshift-operators | grep -E 'devspaces|NAME'
oc get checluster devspaces -n openshift-devspaces
oc get pods,route -n openshift-devspaces
oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.cheURL}{"\n"}'
```

Open the CheCluster URL (dashboard) and sign in with OpenShift OAuth.

---

## Customize

Edit variables in [`../update-values.sh`](../update-values.sh), set `UPDATE_DEVSPACES=true`, then run `./update-values.sh`.

| Variable | What it patches |
| --- | --- |
| `DEVSPACES_SUBSCRIPTION_CHANNEL` | Usually `stable` |
| `DEVSPACES_CATALOG_SOURCE` | Usually `redhat-operators` |
| `DEVSPACES_GIT_REPO_HTTPS` / `DEVSPACES_GIT_REPO_SSH` | Argo CD Application + AppProject repos |
| `DEVSPACES_GIT_TARGET_REVISION` | Argo CD Application branch / tag |

| Change (manual) | Where |
| --- | --- |
| Idle / timeout / storage | `instance/base/checluster.yaml` |
| GPU / long start timeout | `instance/overlays/allow-autoscaling` + components |

---

## Notes

- Uses the **Red Hat** operator package `devspaces` from `redhat-operators`.
- Channel is typically **`stable`**.
- Workspace namespaces are auto-provisioned as `<username>-devspaces` (see CheCluster `defaultNamespace.template`).
- The Dev Workspace Operator is pulled in by the Dev Spaces Subscription / CheCluster — no separate install is required for the default path.
- If the dashboard Route shows **Application is not available** while pods are `Running`, confirm `allow-from-openshift-ingress` exists — without it the router cannot reach `che-gateway`.
