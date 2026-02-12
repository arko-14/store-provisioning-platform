import subprocess
import os
from pathlib import Path

BITNAMI_CHART = "oci://registry-1.docker.io/bitnamicharts/wordpress"


def run(cmd: list[str]) -> str:
    """Run a command and raise a clean error if it fails."""
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def _values_path() -> str:
    # In-cluster (mounted configmap)
    p = os.environ.get("STORE_VALUES_PATH")
    if p:
        return p

    # Local fallback (repo-relative)
    local = Path("infra/local/values-store-demo.yaml")
    if local.exists():
        return str(local.resolve())

    raise RuntimeError(
        "No values file found. Set STORE_VALUES_PATH or ensure infra/local/values-store-demo.yaml exists."
    )


def _apply_quota_and_limits(namespace: str):
    quota_yaml = f"""
apiVersion: v1
kind: ResourceQuota
metadata:
  name: store-quota
  namespace: {namespace}
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    persistentvolumeclaims: "10"
    pods: "20"
"""
    limits_yaml = f"""
apiVersion: v1
kind: LimitRange
metadata:
  name: store-limits
  namespace: {namespace}
spec:
  limits:
    - type: Container
      default:
        cpu: "1"
        memory: "1Gi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
"""

    netpol_yaml = f"""
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: store-default-deny
  namespace: {namespace}
spec:
  podSelector: {{}}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {namespace}
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {namespace}
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
"""

    # Apply all in one shot
    manifest = quota_yaml.strip() + "\n---\n" + limits_yaml.strip() + "\n---\n" + netpol_yaml.strip() + "\n"

    # Use stdin to avoid extra files
    p = subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=manifest,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip())


def create_store(store_name: str):
    namespace = store_name

    # 1) Create namespace (idempotent)
    try:
        run(["kubectl", "create", "ns", namespace])
    except RuntimeError as e:
        if "AlreadyExists" not in str(e):
            raise

    # 2) Apply isolation guardrails (ResourceQuota + LimitRange)
    _apply_quota_and_limits(namespace)

    # 3) Helm install (fail fast + rollback on fail)
    values = _values_path()

    run([
        "helm", "install", store_name, BITNAMI_CHART,
        "-n", namespace,
        "-f", values,
        "--set", f"ingress.hostname={store_name}.localtest.me",
        "--set", "ingress.ingressClassName=nginx",
        "--set", "service.type=ClusterIP",
        "--wait",
        "--timeout", "10m",
        "--atomic",
    ])

    return "helm install completed"


def delete_store(store_name: str):
    namespace = store_name
    subprocess.run(["helm", "uninstall", store_name, "-n", namespace], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    subprocess.run(["kubectl", "delete", "ns", namespace], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return "delete triggered"
