import time
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .store_manager import create_store, delete_store
from .db import conn

from kubernetes import client, config
from kubernetes.config.config_exception import ConfigException

router = APIRouter()


# --------- Request Models ---------
class StoreCreateRequest(BaseModel):
    name: str  # e.g. "store-test-1"


# --------- Helpers ---------
def _row_to_dict(r):
    return {
        "id": r[0],
        "status": r[1],
        "engine": r[2],
        "url": r[3],
        "created_at": r[4],
        "last_error": r[5],
    }


def is_wordpress_ready(namespace: str) -> bool:
    """
    Returns True if a WordPress pod in the namespace is Ready=True.

    - In Kubernetes: uses in-cluster config
    - Locally: falls back to kubeconfig (~/.kube/config)
    """
    try:
        config.load_incluster_config()
    except ConfigException:
        config.load_kube_config()

    v1 = client.CoreV1Api()

    pods = v1.list_namespaced_pod(
        namespace=namespace,
        label_selector="app.kubernetes.io/name=wordpress",
    ).items

    if not pods:
        return False

    pod = pods[0]
    for cond in pod.status.conditions or []:
        if cond.type == "Ready" and cond.status == "True":
            return True

    return False


# --------- Routes ---------
@router.post("/stores")
def create_store_api(req: StoreCreateRequest):
    store_name = req.name.strip()
    if not store_name:
        raise HTTPException(status_code=400, detail="name is required")

    url = f"http://{store_name}.localtest.me"
    c = conn()

    # Idempotency: if store exists in DB, return it
    existing = c.execute(
        "SELECT id,status,engine,url,created_at,last_error FROM stores WHERE id=?",
        (store_name,),
    ).fetchone()

    if existing:
        return _row_to_dict(existing)

    created_at = int(time.time())

    # Insert row as Provisioning
    c.execute(
        "INSERT INTO stores(id,status,engine,url,created_at,last_error) VALUES (?,?,?,?,?,?)",
        (store_name, "Provisioning", "woocommerce", url, created_at, None),
    )
    c.commit()

    # Trigger provisioning (Helm + Kubernetes)
    try:
        create_store(store_name)
        return {
            "id": store_name,
            "status": "Provisioning",
            "engine": "woocommerce",
            "url": url,
            "created_at": created_at,
            "last_error": None,
        }
    except Exception as e:
        c.execute(
            "UPDATE stores SET status=?, last_error=? WHERE id=?",
            ("Failed", str(e), store_name),
        )
        c.commit()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stores")
def list_stores():
    c = conn()
    rows = c.execute(
        "SELECT id,status,engine,url,created_at,last_error FROM stores ORDER BY created_at DESC"
    ).fetchall()
    return [_row_to_dict(r) for r in rows]


@router.get("/stores/{store_name}")
def get_store(store_name: str):
    c = conn()
    r = c.execute(
        "SELECT id,status,engine,url,created_at,last_error FROM stores WHERE id=?",
        (store_name,),
    ).fetchone()
    if not r:
        raise HTTPException(status_code=404, detail="Store not found")
    return _row_to_dict(r)


@router.post("/stores/{store_name}/refresh")
def refresh_status(store_name: str):
    """
    Updates status based on whether the WordPress pod is Ready.
    - If wordpress pod ready => Ready
    - Else => Provisioning
    """
    c = conn()

    # Only update if store exists
    exists = c.execute("SELECT 1 FROM stores WHERE id=?", (store_name,)).fetchone()
    if not exists:
        raise HTTPException(status_code=404, detail="Store not found in registry")

    try:
        ready = is_wordpress_ready(store_name)
        new_status = "Ready" if ready else "Provisioning"

        # Clear last_error on successful refresh checks
        c.execute(
            "UPDATE stores SET status=?, last_error=? WHERE id=?",
            (new_status, None, store_name),
        )
        c.commit()

        return {"id": store_name, "status": new_status}
    except Exception as e:
        # If refresh check itself fails, keep status as Provisioning but record why
        c.execute("UPDATE stores SET last_error=? WHERE id=?", (str(e), store_name))
        c.commit()
        return {"id": store_name, "status": "Provisioning", "warning": str(e)}


@router.delete("/stores/{store_name}")
def delete_store_api(store_name: str):
    # Trigger infra cleanup
    try:
        delete_store(store_name)
    except Exception:
        # still continue to delete from DB best-effort
        pass

    c = conn()
    c.execute("DELETE FROM stores WHERE id=?", (store_name,))
    c.commit()

    return {"status": "deleted", "store_name": store_name}
