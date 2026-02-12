# teardown.ps1 - Cleans up the local development environment
# Usage: .\scripts\teardown.ps1

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Store Platform - Teardown ===" -ForegroundColor Cyan

# Delete all store namespaces
Write-Host "`n[1/3] Deleting store namespaces..." -ForegroundColor Yellow
$storeNs = kubectl get ns -o name | Select-String "store-"
foreach ($ns in $storeNs) {
    $nsName = $ns -replace "namespace/", ""
    Write-Host "  Deleting $nsName..."
    kubectl delete ns $nsName --wait=false
}

# Uninstall platform
Write-Host "`n[2/3] Uninstalling platform..." -ForegroundColor Yellow
helm uninstall platform -n platform 2>$null
kubectl delete ns platform --wait=false 2>$null

# Delete k3d cluster
Write-Host "`n[3/3] Deleting k3d cluster..." -ForegroundColor Yellow
k3d cluster delete store-cluster

Write-Host "`n=== Teardown Complete! ===" -ForegroundColor Green
