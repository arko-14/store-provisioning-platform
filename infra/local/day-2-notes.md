# Day-2: WooCommerce store (Bitnami WordPress)

## What I deployed
- Namespace: store-demo
- Helm chart: bitnami/wordpress (includes MariaDB)
- Ingress: nginx (host: store-demo.localtest.me)
- Persistence: MariaDB PVC + WordPress PVC

## DoD verification (end-to-end)
- Added product (₹199)
- Checkout with Cash on Delivery
- Order created and visible in WooCommerce Admin → Orders

## Commands used
- helm install store-demo bitnami/wordpress -n store-demo -f infra/local/values-store-demo.yaml
- kubectl -n store-demo get pods,svc,ingress,pvc
