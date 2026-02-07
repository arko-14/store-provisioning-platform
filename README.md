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


kubectl -n store-demo get pods,svc,ingress,pvc
helm -n store-demo list

### Store demo (WooCommerce-ready WordPress)
```bash
kubectl -n store-demo get pods,svc,ingress,pvc
helm -n store-demo list



PS C:\Users\psand> helm -n store-demo list
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                  APP VERSION
store-demo      store-demo      1               2026-02-07 11:37:08.9480893 +0530 IST   deployed        wordpress-28.1.5       6.9.1
PS C:\Users\psand> kubectl -n store-demo get pods
NAME                                   READY   STATUS    RESTARTS   AGE
store-demo-mariadb-0                   1/1     Running   0          3h40m
store-demo-wordpress-5f79b4b9d-vsjl5   1/1     Running   0          3h40m
PS C:\Users\psand> kubectl -n store-demo get ingress
NAME                   CLASS   HOSTS                     ADDRESS      PORTS   AGE
store-demo-wordpress   nginx   store-demo.localtest.me   172.23.0.3   80      3h40m
PS C:\Users\psand> kubectl -n store-demo get pvc
NAME                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-store-demo-mariadb-0   Bound    pvc-944e6da0-eefc-4b98-9f72-ff624230797f   2Gi        RWO            local-path     <unset>                 3h40m
store-demo-wordpress        Bound    pvc-33479ace-5809-4a70-bb67-4e8221a93475   2Gi        RWO            local-path     <unset>                 3h40m