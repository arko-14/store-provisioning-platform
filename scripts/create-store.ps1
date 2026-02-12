# create-store.ps1 - Creates a store and opens WordPress admin
# Usage: .\scripts\create-store.ps1 -Name "my-store"
# Usage: .\scripts\create-store.ps1 -Name "my-store" -OpenAdmin
# Usage: .\scripts\create-store.ps1 -Name "my-store" -OpenAdmin -AddProduct

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [switch]$OpenAdmin,
    
    [switch]$AddProduct,
    
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
$baseUrl = "http://platform-dashboard.localtest.me/api"
$storeUrl = "http://$Name.localtest.me"

Write-Host "=== Creating Store: $Name ===" -ForegroundColor Cyan

# 1. Create store via API
Write-Host "`n[1/3] Creating store via API..." -ForegroundColor Yellow
try {
    $body = @{ name = $Name } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$baseUrl/stores" -Method POST -ContentType "application/json" -Body $body
    Write-Host "Store created: $($response.id) - Status: $($response.status)" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 200) {
        Write-Host "Store already exists" -ForegroundColor Yellow
    } else {
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}

# 2. Wait for store to be ready
Write-Host "`n[2/3] Waiting for store to be ready..." -ForegroundColor Yellow
$startTime = Get-Date
$ready = $false

while (-not $ready) {
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
        Write-Host "Timeout waiting for store to be ready" -ForegroundColor Red
        exit 1
    }
    
    # Check if pods exist first
    $podCount = kubectl -n $Name get pods -l app.kubernetes.io/name=wordpress --no-headers 2>$null | Measure-Object -Line | Select-Object -ExpandProperty Lines
    
    if ($podCount -gt 0) {
        $podStatus = kubectl -n $Name get pods -l app.kubernetes.io/name=wordpress -o jsonpath="{.items[0].status.conditions[?(@.type=='Ready')].status}" 2>$null
        if ($podStatus -eq "True") {
            $ready = $true
            Write-Host "Store is ready! (took $([int]$elapsed.TotalSeconds)s)" -ForegroundColor Green
        }
    }
    
    if (-not $ready) {
        $pods = kubectl -n $Name get pods --no-headers 2>$null
        Write-Host "  Waiting... ($([int]$elapsed.TotalSeconds)s) - Pods:" -ForegroundColor Gray
        $pods | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        Start-Sleep -Seconds 5
    }
}

# Update status in DB
Invoke-RestMethod -Uri "$baseUrl/stores/$Name/refresh" -Method POST | Out-Null

# 3. Show URLs and optionally open browser
Write-Host "`n[3/3] Store URLs:" -ForegroundColor Yellow
Write-Host "  Store Front:    $storeUrl" -ForegroundColor Cyan
Write-Host "  Admin Login:    $storeUrl/wp-admin/" -ForegroundColor Cyan
Write-Host "  Add Product:    $storeUrl/wp-admin/post-new.php?post_type=product" -ForegroundColor Cyan
Write-Host "  All Products:   $storeUrl/wp-admin/edit.php?post_type=product" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Credentials:" -ForegroundColor Yellow
Write-Host "    Username: admin" -ForegroundColor White
Write-Host "    Password: Admin@12345" -ForegroundColor White

if ($OpenAdmin -or $AddProduct) {
    Write-Host "`nOpening browser..." -ForegroundColor Yellow
    
    # Open admin login
    Start-Process "$storeUrl/wp-admin/"
    
    if ($AddProduct) {
        # Wait a moment then open add product page
        Start-Sleep -Seconds 2
        Start-Process "$storeUrl/wp-admin/post-new.php?post_type=product"
    }
}

Write-Host "`n=== Done! ===" -ForegroundColor Green

# Print quick commands
Write-Host "`nQuick Commands:" -ForegroundColor Yellow
Write-Host "  View pods:      kubectl -n $Name get pods" -ForegroundColor Gray
Write-Host "  View logs:      kubectl -n $Name logs -l app.kubernetes.io/name=wordpress" -ForegroundColor Gray
Write-Host "  Delete store:   Invoke-RestMethod -Uri '$baseUrl/stores/$Name' -Method DELETE" -ForegroundColor Gray
