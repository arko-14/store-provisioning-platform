import subprocess
from pathlib import Path

BITNAMI_REPO = "bitnami/wordpress"


REPO_ROOT = Path(__file__).resolve().parents[3]
VALUES_PATH = REPO_ROOT / "infra" / "local" / "values-store-demo.yaml"


def run(cmd: list[str]):
    """Run command and raise readable error on failure."""
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def create_store(store_name: str):
    namespace = store_name

    
    try:
        run(["kubectl", "create", "ns", namespace])
    except RuntimeError as e:
        if "AlreadyExists" not in str(e):
            raise

    if not VALUES_PATH.exists():
        raise RuntimeError(f"Values file not found at: {VALUES_PATH}")

    
    run([
        "helm", "install", store_name, BITNAMI_REPO,
        "-n", namespace,
        "-f", str(VALUES_PATH),
        "--set", f"ingress.hostname={store_name}.localtest.me",
        "--set", "ingress.ingressClassName=nginx",
        "--set", "service.type=ClusterIP",
    ])

    return "helm install triggered"


def delete_store(store_name: str):
    namespace = store_name

    
    try:
        run(["helm", "uninstall", store_name, "-n", namespace])
    except RuntimeError:
        pass

   
    try:
        run(["kubectl", "delete", "ns", namespace])
    except RuntimeError:
        pass

    return "delete triggered"
