# dev-local.ps1 - Sets up the local development environment
# Usage: .\scripts\dev-local.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Store Platform - Local Dev Setup ===" -ForegroundColor Cyan

# 1. Check prerequisites
Write-Host "`n[1/6] Checking prerequisites..." -ForegroundColor Yellow
$missing = @()
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { $missing += "docker" }
if (-not (Get-Command k3d -ErrorAction SilentlyContinue)) { $missing += "k3d" }
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) { $missing += "helm" }
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { $missing += "kubectl" }

if ($missing.Count -gt 0) {
    Write-Host "Missing: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "All prerequisites found!" -ForegroundColor Green

# 2. Create k3d cluster (if not exists)
Write-Host "`n[2/6] Creating k3d cluster..." -ForegroundColor Yellow
$clusterExists = k3d cluster list -o json | ConvertFrom-Json | Where-Object { $_.name -eq "store-cluster" }
if (-not $clusterExists) {
    k3d cluster create store-cluster -p "80:80@loadbalancer" --agents 2
} else {
    Write-Host "Cluster 'store-cluster' already exists" -ForegroundColor Green
}

# 3. Install ingress-nginx (if not exists)
Write-Host "`n[3/6] Installing ingress-nginx..." -ForegroundColor Yellow
$ingressNs = kubectl get ns ingress-nginx -o name 2>$null
if (-not $ingressNs) {
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace --wait
} else {
    Write-Host "ingress-nginx already installed" -ForegroundColor Green
}

# 4. Build images
Write-Host "`n[4/6] Building Docker images..." -ForegroundColor Yellow
docker build -t platform-api:v11 apps/api
docker build -t platform-dashboard:v8 apps/dashboard

# 5. Import images to k3d
Write-Host "`n[5/6] Importing images to k3d..." -ForegroundColor Yellow
k3d image import platform-api:v11 platform-dashboard:v8 -c store-cluster

# 6. Deploy platform
Write-Host "`n[6/6] Deploying platform..." -ForegroundColor Yellow
$platformNs = kubectl get ns platform -o name 2>$null
if (-not $platformNs) {
    helm install platform charts/platform -n platform --create-namespace -f charts/platform/values-local.yaml
} else {
    helm upgrade platform charts/platform -n platform -f charts/platform/values-local.yaml
}

# Wait for rollout
kubectl -n platform rollout status deploy/platform-api --timeout=120s
kubectl -n platform rollout status deploy/platform-dashboard --timeout=120s

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Green
Write-Host "Dashboard: http://platform-dashboard.localtest.me" -ForegroundColor Cyan
Write-Host "API:       http://platform-dashboard.localtest.me/api/stores" -ForegroundColor Cyan
