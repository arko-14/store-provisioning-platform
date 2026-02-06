# System Design (Draft)

## Goal
Provision isolated ecommerce stores on Kubernetes using Helm, supporting local
and VPS deployments via configuration changes only.

## High-level Architecture
- React dashboard (user-facing)
- FastAPI backend (orchestration)
- Kubernetes cluster (k3d locally, k3s on VPS)
- Helm charts for store provisioning
- Ingress-nginx for HTTP routing

## Isolation
- Namespace per store
- Secrets and PVCs scoped per namespace

## Current Progress
Day-1: Local cluster + ingress working
