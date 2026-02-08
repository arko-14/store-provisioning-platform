import subprocess
import os
from pathlib import Path

BITNAMI_REPO = "oci://registry-1.docker.io/bitnamicharts/wordpress"


def run(cmd: list[str]):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()

def _values_path() -> str:
    # Prefer env var (works in Kubernetes)
    p = os.environ.get("STORE_VALUES_PATH")
    if p:
        return p

    # Local fallback for your laptop runs (repo-relative)
    local = Path("infra/local/values-store-demo.yaml")
    if local.exists():
        return str(local.resolve())

    raise RuntimeError("No values file found. Set STORE_VALUES_PATH or ensure infra/local/values-store-demo.yaml exists.")

def create_store(store_name: str):
    namespace = store_name

    # Create namespace (idempotent)
    try:
        run(["kubectl", "create", "ns", namespace])
    except RuntimeError as e:
        if "AlreadyExists" not in str(e):
            raise

    values = _values_path()

    run([
        "helm", "install", store_name, BITNAMI_REPO,
        "-n", namespace,
        "-f", values,
        "--set", f"ingress.hostname={store_name}.localtest.me",
        "--set", "ingress.ingressClassName=nginx",
        "--set", "service.type=ClusterIP",
    ])

    return "helm install triggered"

def delete_store(store_name: str):
    namespace = store_name

    # best-effort uninstall + namespace delete
    subprocess.run(["helm", "uninstall", store_name, "-n", namespace], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    subprocess.run(["kubectl", "delete", "ns", namespace], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    return "delete triggered"
