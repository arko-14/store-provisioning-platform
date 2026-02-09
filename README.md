# 🛍️ Kubernetes Store Provisioning Platform

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white) ![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi) ![React](https://img.shields.io/badge/react-%2320232a.svg?style=for-the-badge&logo=react&logoColor=%2361DAFB) ![WooCommerce](https://img.shields.io/badge/WooCommerce-96588A?style=for-the-badge&logo=woocommerce&logoColor=white)

A **Kubernetes-native platform** that provisions isolated ecommerce stores (WooCommerce via WordPress) using Helm. Each store runs in its **own namespace** with **persistent storage** and is exposed via **Ingress** with a stable URL.

---

## ✨ Features

- 🎯 **Namespace-per-store isolation** – Strong security boundaries and easy cleanup
- 🚀 **One-click provisioning** – Deploy WooCommerce stores via React dashboard or REST API
- 🔗 **Stable URLs** – Each store gets a unique subdomain via Ingress
- 💾 **Persistent storage** – Data survives pod restarts (PVCs for WordPress + MariaDB)
- 🎛️ **Helm-based** – Same deployment works local → VPS using values files
- 🗑️ **Safe deletion** – Complete cleanup of namespaces, releases, and resources
- 📊 **Real-time status** – Monitor store health and readiness

---

## 🏗️ Architecture

```
┌─────────────────┐
│ React Dashboard │ ──HTTP──> ┌──────────────────┐
└─────────────────┘            │  FastAPI Platform│
                               │       API        │
                               └────────┬─────────┘
                                        │
                                        ▼
                               ┌────────────────────┐
                               │   Kubernetes API   │
                               └────────┬───────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
            ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
            │ Namespace:    │   │ Namespace:    │   │ Namespace:    │
            │   store-1     │   │   store-2     │   │   store-N     │
            ├───────────────┤   ├───────────────┤   ├───────────────┤
            │ WordPress Pod │   │ WordPress Pod │   │ WordPress Pod │
            │ MariaDB Pod   │   │ MariaDB Pod   │   │ MariaDB Pod   │
            │ PVCs          │   │ PVCs          │   │ PVCs          │
            │ Ingress       │   │ Ingress       │   │ Ingress       │
            └───────────────┘   └───────────────┘   └───────────────┘
```

**Tech Stack:**
- **Frontend:** React (dashboard UI)
- **Backend:** FastAPI (orchestrator API)
- **Orchestration:** Kubernetes + Helm (Bitnami WordPress chart)
- **Ingress:** nginx-ingress-controller
- **Storage:** PersistentVolumeClaims (local-path / cloud storage)

---

## 📁 Project Structure

```
.
├── apps/
│   ├── api/                    # FastAPI service (orchestrator)
│   │   ├── Dockerfile
│   │   ├── src/
│   │   └── requirements.txt
│   └── dashboard/              # React UI
│       ├── Dockerfile
│       ├── package.json
│       ├── nginx.conf
│       └── src/
├── charts/
│   └── platform/               # Helm chart for platform services
│       ├── Chart.yaml
│       ├── values.yaml         # Production defaults
│       ├── values-local.yaml   # Local k3d overrides
│       ├── values-prod.yaml    # Production overrides
│       ├── templates/          # K8s manifests
│       └── files/              # Config files
├── infra/
│   └── local/                  # Local cluster setup notes
├── docs/
│   └── screenshots/
│       └── postman/            # API testing screenshots
├── scripts/                    # Automation scripts
├── demo/                       # Demo configurations
├── data/                       # Data files
├── README.md
└── SYSTEM_DESIGN.md
```

| Folder | Purpose |
|--------|---------|
| **apps/api/** | FastAPI orchestrator (create/list/delete/refresh stores) |
| **apps/dashboard/** | React UI for store management |
| **charts/platform/** | Helm chart deploying API + Dashboard + RBAC + Ingresses |
| **infra/local/** | k3d cluster setup scripts and notes |
| **docs/screenshots/** | Postman/UI demo screenshots |
| **scripts/** | Deployment and automation scripts |

---

## 🔧 Prerequisites

- **Docker Desktop** (with Kubernetes enabled) or standalone Docker
- **k3d** – Lightweight Kubernetes in Docker
- **kubectl** ≥ 1.25
- **Helm** ≥ 3.0

---

## 🚀 Quick Start (Local k3d)

### 1️⃣ Create Kubernetes Cluster

```bash
# Create k3d cluster with 2 agent nodes
k3d cluster create store-cluster --agents 2

# Verify nodes
kubectl get nodes
```

### 2️⃣ Install nginx Ingress Controller

```bash
# Install nginx ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for ingress pods to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Verify
kubectl get pods -n ingress-nginx
kubectl get ingressclass
```

### 3️⃣ Build and Import Platform Images

```bash
# Build API image
docker build -t platform-api:v1 -f apps/api/Dockerfile apps/api

# Build Dashboard image
docker build -t platform-dashboard:v1 -f apps/dashboard/Dockerfile apps/dashboard

# Import images into k3d cluster
k3d image import platform-api:v1 -c store-cluster
k3d image import platform-dashboard:v1 -c store-cluster
```

### 4️⃣ Deploy Platform via Helm

```bash
# Install platform chart (API + Dashboard + Ingresses)
helm upgrade --install platform charts/platform \
  -n platform \
  --create-namespace \
  -f charts/platform/values-local.yaml

# Verify deployment
kubectl -n platform get pods,svc,ingress
```

### 5️⃣ Access the Platform

This project uses **`*.localtest.me`** which automatically resolves to `127.0.0.1` (no `/etc/hosts` editing needed).

| Service | URL |
|---------|-----|
| **Dashboard** | http://platform-dashboard.localtest.me |
| **API Docs** | http://platform.localtest.me/docs |
| **Store Example** | http://store-1.localtest.me |

---

## 📚 Usage

### Via Dashboard (UI)

1. Open **http://platform-dashboard.localtest.me**
2. Enter a store name (e.g., `store-1`)
3. Click **Create Store**
4. Wait for status to become `Ready` (~2-3 minutes)
5. Click the store URL to access WooCommerce

### Via API (Postman / cURL)

**Base URL:** `http://platform.localtest.me`

#### 1. List All Stores
```bash
GET /api/stores
```

#### 2. Create a New Store
```bash
POST /api/stores
Content-Type: application/json

{
  "name": "postman-store-1"
}
```

**Screenshot:**

![Postman Create Store](docs/screenshots/postman/create%20store.png)

#### 3. Refresh Store Status
```bash
POST /api/stores/postman-store-1/refresh
```

#### 4. Delete a Store
```bash
DELETE /api/stores/postman-store-1
```

**Screenshot:**

![Postman List Stores](docs/screenshots/postman/list%20stores.png)

---

## 🧪 Demo Store Verification

A working demo store (`store-demo`) is included for verification:

```bash
# Check all resources
kubectl -n store-demo get pods,svc,ingress,pvc

# Verify Helm release
helm -n store-demo list
```

**Expected Output:**
```
NAME       NAMESPACE  STATUS    CHART             APP VERSION
store-demo store-demo deployed  wordpress-28.1.5   6.9.1

NAME                                   READY   STATUS    RESTARTS
store-demo-mariadb-0                   1/1     Running   0
store-demo-wordpress-5f79b4b9d-vsjl5   1/1     Running   0

NAME                       HOSTS                    ADDRESS
store-demo-wordpress       store-demo.localtest.me  80

NAME                              STATUS   CAPACITY
data-store-demo-mariadb-0         Bound    2Gi
store-demo-wordpress              Bound    2Gi
```

Access: **http://store-demo.localtest.me**

---

## 🗑️ Deleting a Store

Deleting a store removes:
- ✅ Namespace
- ✅ Helm release
- ✅ All pods, services, ingresses
- ✅ PersistentVolumeClaims (data)

```bash
# Via API
DELETE /api/stores/store-1

# Verify cleanup
kubectl get ns | grep store-1  # Should return nothing
```

---

## 🎯 Design Decisions

### Why Namespace-per-Store?
- **Strong isolation** – Security boundary between stores
- **Easy cleanup** – Delete namespace = delete everything
- **Resource quotas** – Apply limits per store (future)
- **Multi-tenancy ready** – Clear ownership boundaries

### Why Helm?
- **Portability** – Same chart works local → VPS with different values files
- **Upgrades/Rollbacks** – Built-in version management
- **Templating** – DRY configuration for multiple stores

### Why Bitnami WordPress Chart?
- **Production-ready** – Includes MariaDB, persistence, security defaults
- **WooCommerce compatible** – WordPress 6.x with plugin support
- **Well-maintained** – Regular updates and CVE patches

---

## 🔄 Production Deployment (VPS / k3s)

Only Helm values change for production:

```yaml
# values-prod.yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: platform.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: platform-tls
      hosts:
        - platform.yourdomain.com

storage:
  storageClass: longhorn  # or openebs, cloud storage

secrets:
  # Use external-secrets or sealed-secrets
  wordpress:
    password: <sealed-secret-ref>
```

**Additional Production Considerations:**
- 🔒 **TLS/SSL** – Use cert-manager for automatic Let's Encrypt certificates
- 💾 **Storage** – Replace local-path with Longhorn, OpenEBS, or cloud storage
- 🔐 **Secrets** – Use external-secrets-operator or sealed-secrets
- 📊 **Monitoring** – Add Prometheus + Grafana for observability
- 🚨 **Alerts** – Configure alerting for pod failures and resource limits

---

## 🛠️ Roadmap / Future Improvements

- [ ] **ResourceQuota + LimitRange** per store namespace
- [ ] **Provisioning timeouts** and clearer failure reasons
- [ ] **Audit log** of store creation/deletion actions
- [ ] **Multi-user authentication** with per-user quotas
- [ ] **Backup/Restore** functionality for stores
- [ ] **Custom domain mapping** for stores
- [ ] **Store templates** (different WooCommerce configurations)
- [ ] **Cost tracking** per store
- [ ] **Auto-scaling** based on traffic

---

## 🐛 Troubleshooting

### Store stuck in "Pending" status
```bash
# Check pod status
kubectl -n <store-name> get pods

# Check pod logs
kubectl -n <store-name> logs <pod-name>

# Check events
kubectl -n <store-name> get events --sort-by='.lastTimestamp'
```

### Ingress not working
```bash
# Verify ingress controller is running
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl -n <store-name> describe ingress

# Test DNS resolution
nslookup store-1.localtest.me
```

### PVC not binding
```bash
# Check PVC status
kubectl -n <store-name> get pvc

# Check storage class
kubectl get storageclass

# For k3d, ensure local-path provisioner is running
kubectl -n kube-system get pods | grep local-path
```

---

## 📖 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Bitnami WordPress Chart](https://github.com/bitnami/charts/tree/main/bitnami/wordpress)
- [k3d Documentation](https://k3d.io/)
- [WooCommerce Documentation](https://woocommerce.com/documentation/)

---

## 📊 Project Status

- [x] Local Kubernetes cluster setup (k3d)
- [x] Ingress routing via nginx
- [x] WooCommerce store provisioning (Helm)
- [x] FastAPI orchestrator (create/list/delete/refresh)
- [x] React dashboard (list/create/delete/refresh)
- [x] Local-to-prod structure via Helm values
- [ ] Multi-user authentication
- [ ] Resource quotas and limits
- [ ] Backup/restore functionality
- [ ] Production deployment guide

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 👤 Author

**arko-14**
- GitHub: [@arko-14](https://github.com/arko-14)

---

## ⭐ Show your support

Give a ⭐️ if this project helped you!
