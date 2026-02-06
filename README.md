# Kubernetes Store Provisioning Platform

This project is a Kubernetes-native platform that provisions isolated ecommerce
stores (WooCommerce) using Helm. Each store runs in its own namespace and is
exposed via Ingress with a stable URL.

## Status
- [x] Local Kubernetes cluster setup (k3d)
- [x] Ingress routing via nginx
- [ ] WooCommerce store provisioning
- [ ] FastAPI orchestrator
- [ ] React dashboard
