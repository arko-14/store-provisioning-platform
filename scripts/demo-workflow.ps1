# demo-workflow.ps1 - Full demo: create store, add product, view cart
# Usage: .\scripts\demo-workflow.ps1 -StoreName "demo-store"
# Usage: .\scripts\demo-workflow.ps1 -StoreName "demo-store" -FullAuto   (auto-creates product)

param(
    [string]$StoreName = "demo-$(Get-Random -Maximum 999)",
    [int]$TimeoutSeconds = 600,
    [switch]$FullAuto  # If set, auto-creates a product via WP-CLI
)

$ErrorActionPreference = "Stop"
$baseUrl = "http://platform-dashboard.localtest.me/api"
$storeUrl = "http://$StoreName.localtest.me"

$modeText = if ($FullAuto) { "FULL AUTO (creates product automatically)" } else { "MANUAL (opens admin for you to create)" }

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "          Store Platform - Demo Workflow                       " -ForegroundColor Cyan
Write-Host "          Mode: $modeText" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create Store
Write-Host "STEP 1: Creating store '$StoreName'..." -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

try {
    $body = @{ name = $StoreName } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$baseUrl/stores" -Method POST -ContentType "application/json" -Body $body -TimeoutSec 660
    Write-Host "  Created: $($response.id)" -ForegroundColor Green
    Write-Host "  Status:  $($response.status)" -ForegroundColor Green
    Write-Host "  URL:     $($response.url)" -ForegroundColor Green
} catch {
    # Check if store already exists
    try {
        $existing = Invoke-RestMethod -Uri "$baseUrl/stores/$StoreName" -Method GET
        Write-Host "  Store already exists: $($existing.id) - Status: $($existing.status)" -ForegroundColor Yellow
    } catch {
        Write-Host "  Error creating store: $_" -ForegroundColor Red
        exit 1
    }
}

# Step 2: Wait for Ready
Write-Host "`nSTEP 2: Waiting for WordPress to be ready..." -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

$startTime = Get-Date
$ready = $false

while (-not $ready) {
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
        Write-Host "  Timeout!" -ForegroundColor Red
        exit 1
    }
    
    # Check if pods exist first, then check ready status
    $podCount = kubectl -n $StoreName get pods -l app.kubernetes.io/name=wordpress --no-headers 2>$null | Measure-Object -Line | Select-Object -ExpandProperty Lines
    
    if ($podCount -gt 0) {
        $podReady = kubectl -n $StoreName get pods -l app.kubernetes.io/name=wordpress -o jsonpath="{.items[0].status.conditions[?(@.type=='Ready')].status}" 2>$null
        if ($podReady -eq "True") {
            $ready = $true
        }
    }
    
    if (-not $ready) {
        Write-Host "  Waiting... ($([int]$elapsed.TotalSeconds)s)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
}

# Extra wait for WordPress to fully initialize
Write-Host "  Pods ready, waiting for WordPress init..." -ForegroundColor Gray
Start-Sleep -Seconds 10

Write-Host "  Store is READY! (took $([int]$elapsed.TotalSeconds)s)" -ForegroundColor Green

# Update status
Invoke-RestMethod -Uri "$baseUrl/stores/$StoreName/refresh" -Method POST | Out-Null

# Step 3: Show guardrails
Write-Host "`nSTEP 3: Verify namespace guardrails..." -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

Write-Host "`n  ResourceQuota:" -ForegroundColor Cyan
kubectl -n $StoreName get resourcequota store-quota -o jsonpath="{.status.hard}" 2>$null | ConvertFrom-Json | Format-List

Write-Host "  LimitRange:" -ForegroundColor Cyan
kubectl -n $StoreName get limitrange store-limits -o jsonpath="{.spec.limits[0]}" 2>$null | ConvertFrom-Json | Format-List

Write-Host "  NetworkPolicy:" -ForegroundColor Cyan
$netpol = kubectl -n $StoreName get networkpolicy store-default-deny -o name 2>$null
if ($netpol) {
    Write-Host "    store-default-deny: Applied" -ForegroundColor Green
} else {
    Write-Host "    Not found" -ForegroundColor Yellow
}

# Step 4: Create product (auto) or prepare for manual
if ($FullAuto) {
    Write-Host "`nSTEP 4: Creating sample product via WP-CLI..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------" -ForegroundColor DarkGray

    $wpPod = kubectl -n $StoreName get pods -l app.kubernetes.io/name=wordpress -o jsonpath="{.items[0].metadata.name}"

    # Install WooCommerce plugin (use -c wordpress to avoid "Defaulted container" warning)
    Write-Host "  Installing WooCommerce plugin..." -ForegroundColor Gray
    $ErrorActionPreference = "Continue"
    kubectl -n $StoreName exec -c wordpress $wpPod -- wp plugin install woocommerce --activate --allow-root 2>&1 | Out-Null

    # Create a sample product
    $productName = "Demo T-Shirt"
    $productPrice = "29.99"
    $productDesc = "A comfortable demo t-shirt for testing"

    Write-Host "  Creating product: $productName (`$$productPrice)" -ForegroundColor Gray
    $createCmd = "wp wc product create --name='$productName' --type=simple --regular_price='$productPrice' --description='$productDesc' --status=publish --user=admin --allow-root"
    $productOutput = kubectl -n $StoreName exec -c wordpress $wpPod -- bash -c $createCmd 2>&1
    $ErrorActionPreference = "Stop"

    # Extract product ID
    if ($productOutput -match "Created product (\d+)") {
        $productId = $matches[1]
        Write-Host "  Product created! ID: $productId" -ForegroundColor Green
        $productUrl = "$storeUrl/?p=$productId"
    } else {
        Write-Host "  Product creation output: $productOutput" -ForegroundColor Yellow
        $productUrl = "$storeUrl/shop/"
    }

    # Step 5: Open browser to product
    Write-Host "`nSTEP 5: Opening browser to product..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------" -ForegroundColor DarkGray

    Write-Host "  Opening: $productUrl" -ForegroundColor Cyan
    Start-Process $productUrl

    # Summary for auto mode
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "                      DEMO COMPLETE                            " -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Store Name:  $StoreName" -ForegroundColor White
    Write-Host "  Store URL:   $storeUrl" -ForegroundColor White
    Write-Host "  Product:     $productName - `$$productPrice" -ForegroundColor White
    Write-Host "  Product URL: $productUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Click 'Add to Cart' on the product page!" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "`nSTEP 4: Opening browser for manual setup..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------" -ForegroundColor DarkGray

    Write-Host @"

  Opening 3 tabs:
  1. Store Front      - $storeUrl
  2. Admin Login      - $storeUrl/wp-admin/
  3. Add Product Page - $storeUrl/wp-admin/post-new.php?post_type=product

  Login Credentials:
    Username: admin
    Password: Admin@12345

"@ -ForegroundColor Cyan

    Start-Process $storeUrl
    Start-Sleep -Seconds 1
    Start-Process "$storeUrl/wp-admin/"
    Start-Sleep -Seconds 1
    Start-Process "$storeUrl/wp-admin/post-new.php?post_type=product"

    # Summary for manual mode
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "                      DEMO COMPLETE                            " -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Store Name:  $StoreName" -ForegroundColor White
    Write-Host "  Store URL:   $storeUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Log into wp-admin (admin / Admin@12345)"
    Write-Host "  2. Install WooCommerce plugin (Plugins > Add New)"
    Write-Host "  3. Go to Products > Add New"
    Write-Host "  4. Add product name, price, image"
    Write-Host "  5. Click 'Publish'"
    Write-Host "  6. Visit store front and add to cart!"
    Write-Host ""
}

Write-Host "Cleanup command:" -ForegroundColor Yellow
Write-Host "  Invoke-RestMethod -Uri '$baseUrl/stores/$StoreName' -Method DELETE" -ForegroundColor Gray
