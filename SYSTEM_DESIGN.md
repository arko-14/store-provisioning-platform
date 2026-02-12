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
