# System Design

## Overview

A multi-tenant ecommerce store provisioning platform that deploys isolated WordPress/WooCommerce instances on Kubernetes. Users interact via a React dashboard to create, monitor, and delete stores. Each store runs in its own namespace with resource quotas and network isolation.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Kubernetes Cluster                             │
│                         (k3d local / k3s production)                        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        platform namespace                            │   │
│  │                                                                      │   │
│  │  ┌──────────────────┐      ┌──────────────────┐                     │   │
│  │  │  platform-api    │      │ platform-dashboard│                     │   │
│  │  │  (FastAPI)       │      │ (React + nginx)   │                     │   │
│  │  │                  │      │                   │                     │   │
│  │  │  - /stores CRUD  │◄─────│  - Create UI      │                     │   │
│  │  │  - helm install  │      │  - Status list    │                     │   │
│  │  │  - kubectl apply │      │  - Delete/Refresh │                     │   │
│  │  └──────────────────┘      └──────────────────┘                     │   │
│  │           │                                                          │   │
│  │           │ ServiceAccount: platform-api-sa                          │   │
│  │           │ ClusterRole: platform-api-cr                             │   │
│  └───────────┼──────────────────────────────────────────────────────────┘   │
│              │                                                              │
│              ▼                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                     Per-Store Namespace (e.g. store-5)                │ │
│  │                                                                       │ │
│  │  Guardrails (applied before Helm install):                            │ │
│  │  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────────┐  │ │
│  │  │ ResourceQuota   │ │ LimitRange      │ │ NetworkPolicy           │  │ │
│  │  │ store-quota     │ │ store-limits    │ │ store-default-deny      │  │ │
│  │  │                 │ │                 │ │                         │  │ │
│  │  │ cpu: 4 req/8 lim│ │ default:        │ │ Ingress: same-ns +      │  │ │
│  │  │ mem: 4Gi/8Gi    │ │  cpu: 1         │ │          ingress-nginx  │  │ │
│  │  │ pods: 20        │ │  mem: 1Gi       │ │ Egress: same-ns + DNS   │  │ │
│  │  │ pvcs: 10        │ │ defaultRequest: │ │         + HTTPS (443)   │  │ │
│  │  └─────────────────┘ │  cpu: 100m      │ └─────────────────────────┘  │ │
│  │                      │  mem: 128Mi     │                              │ │
│  │                      └─────────────────┘                              │ │
│  │                                                                       │ │
│  │  WordPress Stack (Bitnami Helm chart):                                │ │
│  │  ┌─────────────────┐      ┌─────────────────┐                        │ │
│  │  │ WordPress Pod   │      │ MariaDB Pod     │                        │ │
│  │  │ (Deployment)    │◄────►│ (StatefulSet)   │                        │ │
│  │  └────────┬────────┘      └────────┬────────┘                        │ │
│  │           │                        │                                  │ │
│  │      ┌────┴────┐              ┌────┴────┐                            │ │
│  │      │ PVC 2Gi │              │ PVC 2Gi │                            │ │
│  │      └─────────┘              └─────────┘                            │ │
│  │                                                                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │  │ Ingress: store-5.localtest.me → WordPress Service               │ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │                      ingress-nginx namespace                           ││
│  │  ┌──────────────────────────────────────────────────────────────────┐ ││
│  │  │ Ingress Controller                                                │ ││
│  │  │ Routes: *.localtest.me → appropriate namespace services           │ ││
│  │  └──────────────────────────────────────────────────────────────────┘ ││
│  └────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Platform API (FastAPI)

**Location:** `apps/api/`

**Responsibilities:**
- REST API for store CRUD operations
- Executes `kubectl` and `helm` commands for provisioning
- Manages SQLite database for store metadata
- Applies namespace guardrails (quota, limits, network policy)

**Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| POST | `/stores` | Create a new store |
| GET | `/stores` | List all stores |
| GET | `/stores/{id}` | Get store details |
| POST | `/stores/{id}/refresh` | Check WordPress pod readiness |
| DELETE | `/stores/{id}` | Delete store and cleanup |

**Database Schema:**
```sql
CREATE TABLE stores(
  id TEXT PRIMARY KEY,        -- store name (e.g. "store-5")
  status TEXT NOT NULL,       -- Provisioning | Ready | Failed
  engine TEXT NOT NULL,       -- "woocommerce"
  url TEXT NOT NULL,          -- "http://store-5.localtest.me"
  created_at INTEGER NOT NULL,-- Unix timestamp
  last_error TEXT             -- Error message if failed
)
```

### 2. Platform Dashboard (React)

**Location:** `apps/dashboard/`

**Features:**
- Create store form (name input)
- Store list with status, URL, timestamps
- Refresh status button (checks pod readiness)
- Delete store button
- Auto-refresh every 4 seconds

**Deployment:** Static files served via nginx with reverse proxy to API.

### 3. Store Manager Module

**Location:** `apps/api/src/store_manager.py`

**Store Creation Workflow:**
```
create_store(store_name)
        │
        ▼
┌───────────────────────────────┐
│ 1. Create Namespace           │
│    kubectl create ns {name}   │
│    (idempotent - AlreadyExists│
│     is ignored)               │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ 2. Apply Guardrails           │
│    kubectl apply -f - <<EOF   │
│    - ResourceQuota            │
│    - LimitRange               │
│    - NetworkPolicy            │
│    EOF                        │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ 3. Helm Install WordPress     │
│    helm install {name}        │
│      oci://bitnamicharts/     │
│        wordpress              │
│      -n {namespace}           │
│      -f values-store.yaml     │
│      --set ingress.hostname=  │
│        {name}.localtest.me    │
│      --wait --timeout 10m     │
│      --atomic                 │
└───────────────────────────────┘
```

**Store Deletion Workflow:**
```
delete_store(store_name)
        │
        ▼
┌───────────────────────────────┐
│ 1. Helm Uninstall             │
│    helm uninstall {name}      │
│    -n {namespace}             │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ 2. Delete Namespace           │
│    kubectl delete ns {name}   │
│    (cascades all resources)   │
└───────────────────────────────┘
```

---

## Multi-Tenant Isolation

### Per-Namespace Guardrails

Applied automatically on every store creation:

**ResourceQuota (`store-quota`):**
```yaml
hard:
  requests.cpu: "4"
  requests.memory: 4Gi
  limits.cpu: "8"
  limits.memory: 8Gi
  persistentvolumeclaims: "10"
  pods: "20"
```

**LimitRange (`store-limits`):**
```yaml
limits:
  - type: Container
    default:
      cpu: "1"
      memory: "1Gi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
```

**NetworkPolicy (`store-default-deny`):**
```yaml
podSelector: {}  # All pods in namespace
policyTypes: [Ingress, Egress]

ingress:
  - from: [same namespace]
  - from: [ingress-nginx namespace]

egress:
  - to: [same namespace]
  - to: [kube-system] port 53/UDP (DNS)
  - to: [0.0.0.0/0] port 443/TCP (HTTPS)
```

### RBAC

**ServiceAccount:** `platform-api-sa` (in platform namespace)

**ClusterRole:** `platform-api-cr`

| Resource | Verbs |
|----------|-------|
| namespaces | get, list, watch, create, delete |
| pods, services, secrets, configmaps, pvcs, resourcequotas, limitranges | get, list, watch, create, delete, patch, update |
| deployments, statefulsets, replicasets | get, list, watch, create, delete, patch, update |
| ingresses, networkpolicies | get, list, watch, create, delete, patch, update |
| roles, rolebindings | get, list, watch, create, delete, patch, update |

---

## Request Flow

### Create Store

```
User clicks "Create Store"
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│ Dashboard: POST /api/stores {"name": "store-5"}                 │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ API: Check if store exists in DB                                │
│      - If exists: return existing record (idempotent)           │
│      - If not: INSERT with status="Provisioning"                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ store_manager.create_store("store-5")                           │
│   1. kubectl create ns store-5                                  │
│   2. kubectl apply (ResourceQuota + LimitRange + NetworkPolicy) │
│   3. helm install store-5 wordpress --wait --atomic             │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
            ┌───────────────┐       ┌───────────────┐
            │ Success       │       │ Failure       │
            │ Return 200    │       │ UPDATE status │
            │ status:       │       │ = "Failed"    │
            │ Provisioning  │       │ Return 500    │
            └───────────────┘       └───────────────┘
```

### Refresh Status

```
User clicks "Refresh" or auto-refresh triggers
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│ Dashboard: POST /api/stores/{id}/refresh                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ API: is_wordpress_ready(namespace)                              │
│      - List pods with label app.kubernetes.io/name=wordpress    │
│      - Check if any pod has condition Ready=True                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
            ┌───────────────┐       ┌───────────────┐
            │ Pod Ready     │       │ Pod Not Ready │
            │ UPDATE status │       │ Keep status   │
            │ = "Ready"     │       │ "Provisioning"│
            └───────────────┘       └───────────────┘
```

---

## Deployment

### Local (k3d)

```bash
# Create cluster
k3d cluster create store-cluster \
  -p "80:80@loadbalancer" \
  --agents 2

# Install ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace

# Build and import images
docker build -t platform-api:v11 apps/api
docker build -t platform-dashboard:v8 apps/dashboard
k3d image import platform-api:v11 platform-dashboard:v8 -c store-cluster

# Deploy platform
helm install platform charts/platform \
  -n platform --create-namespace \
  -f charts/platform/values-local.yaml
```

**Access:**
- Dashboard: http://platform-dashboard.localtest.me
- API: http://platform-dashboard.localtest.me/api/
- Stores: http://{store-name}.localtest.me

### Production (k3s on VPS)

Changes via Helm values:
- `ingress.dashboardHost`: Real domain
- `ingress.className`: nginx or traefik
- TLS: Add cert-manager annotations
- Storage: Configure proper StorageClass

---

## Helm Chart Structure

```
charts/platform/
├── Chart.yaml
├── values.yaml           # Defaults
├── values-local.yaml     # Local overrides
├── values-prod.yaml      # Production overrides
├── files/
│   └── store-values.yaml # WordPress defaults
└── templates/
    ├── api-deployment.yaml
    ├── api-service.yaml
    ├── api-ingress.yaml
    ├── api-configmap.yaml
    ├── api-secret.yaml
    ├── dashboard-deployment.yaml
    ├── dashboard-service.yaml
    ├── dashboard-ingress.yaml
    ├── rbac.yaml
    └── store-values-configmap.yaml
```

---

## File Structure

```
store/
├── apps/
│   ├── api/
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── src/
│   │       ├── main.py           # FastAPI app
│   │       ├── routes_store.py   # Store CRUD endpoints
│   │       ├── store_manager.py  # Helm/kubectl operations
│   │       ├── db.py             # SQLite connection
│   │       └── models.py
│   └── dashboard/
│       ├── Dockerfile
│       ├── package.json
│       ├── nginx.conf            # Reverse proxy config
│       └── src/
│           └── App.jsx           # React UI
├── charts/
│   └── platform/                 # Helm chart for platform
├── infra/
│   ├── local/
│   │   ├── values-store-demo.yaml
│   │   └── k3d.md
│   └── vps/
│       └── k3s.md
└── scripts/
    ├── dev-local.sh
    └── teardown.sh
```

---

## Status Lifecycle

```
                    ┌─────────────┐
     POST /stores   │             │
    ───────────────►│ Provisioning│
                    │             │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               │
    ┌─────────────┐ ┌─────────────┐        │
    │             │ │             │        │
    │   Ready     │ │   Failed    │        │
    │             │ │             │        │
    └─────────────┘ └──────┬──────┘        │
                           │               │
                           │  Retry        │
                           └───────────────┘
```

---

## Configuration

### Environment Variables (API)

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_PATH` | SQLite database path | `/tmp/stores.db` |
| `STORE_VALUES_PATH` | WordPress Helm values file | (ConfigMap mount) |

### WordPress Defaults (`values-store-demo.yaml`)

```yaml
wordpressUsername: admin
wordpressPassword: "Admin@12345"
service:
  type: ClusterIP
ingress:
  enabled: true
  ingressClassName: nginx
mariadb:
  enabled: true
  primary:
    persistence:
      size: 2Gi
persistence:
  size: 2Gi
```

---

## System Design & Tradeoffs

### Architecture Choices

| Decision | Choice | Why | Tradeoff |
|----------|--------|-----|----------|
| **Orchestration** | Synchronous Helm via subprocess | Simple, atomic (`--atomic`), no extra infrastructure | Blocks API during provisioning (~5-10 min); not horizontally scalable |
| **Store Isolation** | Namespace-per-store | Clean boundaries, easy cleanup (`kubectl delete ns`), native RBAC scoping | Namespace count limits (~10k), slight overhead per namespace |
| **State Storage** | SQLite in-pod | Zero dependencies, fast prototyping | Not persistent across pod restarts, not HA; production needs PostgreSQL |
| **Ingress** | Wildcard `*.localtest.me` | No DNS config needed for local dev | Production requires real DNS + cert-manager |
| **Container Runtime** | Direct `kubectl`/`helm` exec | Avoids Kubernetes client library complexity | Subprocess overhead, error parsing is string-based |

### Idempotency & Failure Handling

**Create Store:**
```
1. Check DB → if exists, return existing record (no duplicate creates)
2. Insert DB row with status="Provisioning"
3. kubectl create ns → ignores AlreadyExists error
4. kubectl apply guardrails → idempotent (apply, not create)
5. helm install --atomic → auto-rollback on failure
6. On exception: UPDATE status="Failed", store error message
```

**Key Behaviors:**
- ✅ **Safe retries:** Creating same store twice returns existing record
- ✅ **Atomic Helm:** `--atomic` flag rolls back on any failure
- ✅ **Error capture:** Failures recorded in `last_error` column
- ⚠️ **No recovery:** If API pod restarts mid-provision, store stays "Provisioning" forever (manual cleanup needed)

**Delete Store:**
```
1. helm uninstall (best-effort, continues on error)
2. kubectl delete ns (cascades all resources)
3. DELETE from DB
```

**Key Behaviors:**
- ✅ **Cascading cleanup:** Namespace deletion removes all child resources
- ✅ **Best-effort:** Partial failures don't block DB cleanup
- ⚠️ **No finalizers:** If namespace deletion hangs, requires manual intervention

### Cleanup Approach

| Resource | Cleanup Method | Notes |
|----------|---------------|-------|
| Helm release | `helm uninstall` | Removes managed resources |
| Pods, Services, Ingress | Namespace deletion | Cascaded automatically |
| PVCs | Namespace deletion | Data is deleted (no backup) |
| ResourceQuota, LimitRange | Namespace deletion | Cascaded |
| NetworkPolicy | Namespace deletion | Cascaded |
| DB record | `DELETE FROM stores` | After infra cleanup |

### Production Changes

| Component | Local (k3d) | Production | How to Change |
|-----------|-------------|------------|---------------|
| **DNS** | `*.localtest.me` (auto 127.0.0.1) | Real domain + DNS records | Helm values: `ingress.dashboardHost`, `ingress.apiHost` |
| **TLS** | None (HTTP) | Let's Encrypt via cert-manager | Add `cert-manager.io/cluster-issuer` annotation |
| **Ingress** | nginx-ingress | nginx / traefik / cloud LB | Helm values: `ingress.className` |
| **Storage** | local-path (ephemeral) | Longhorn / OpenEBS / cloud PV | Helm values: `storageClass` |
| **Secrets** | Plain ConfigMap | external-secrets / sealed-secrets | Replace `api-secret.yaml` template |
| **Database** | SQLite `/tmp/stores.db` | PostgreSQL with PVC | Env var `DB_PATH`, update `db.py` |
| **Registry** | k3d image import | Container registry (ECR/GCR/Docker Hub) | Helm values: `api.image`, `dashboard.image` |
| **RBAC** | ClusterRole (broad) | Namespace-scoped Roles | Refactor `rbac.yaml` |

### Production Checklist

```yaml
# values-prod.yaml changes
ingress:
  dashboardHost: dashboard.mycompany.com
  apiHost: api.mycompany.com
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

api:
  image: registry.mycompany.com/platform-api
  tag: v1.0.0

dashboard:
  image: registry.mycompany.com/platform-dashboard
  tag: v1.0.0

storage:
  class: longhorn  # or gp3, do-block-storage, etc.

# Additional production requirements:
# 1. Set up cert-manager with ClusterIssuer
# 2. Configure external-secrets for WordPress passwords
# 3. Deploy PostgreSQL for API state (or managed RDS)
# 4. Set up monitoring (Prometheus + Grafana)
# 5. Configure backup for PVCs (Velero)
# 6. Set appropriate resource requests/limits
```

### Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Synchronous provisioning | API blocks 5-10 min per store | Future: async job queue (Celery/Redis) |
| SQLite state | Lost on pod restart | Use PostgreSQL with PVC |
| No horizontal scaling | Single API instance | Future: distributed locking for Helm |
| No backup/restore | Data loss on PVC delete | Integrate Velero for PV snapshots |
| NetworkPolicy enforcement | Requires CNI support (Calico/Cilium) | k3d/Flannel doesn't enforce |
| Provisioning timeout | Helm can hang indefinitely | `--timeout 10m` flag mitigates |
