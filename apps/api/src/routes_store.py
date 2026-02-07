import time
import subprocess
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .store_manager import create_store, delete_store
from .db import conn

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

    # Insert row as Provisioning
    c.execute(
        "INSERT INTO stores(id,status,engine,url,created_at,last_error) VALUES (?,?,?,?,?,?)",
        (store_name, "Provisioning", "woocommerce", url, int(time.time()), None),
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
            "created_at": int(time.time()),
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
    # Check pod readiness in that namespace
    cmd = [
        "kubectl",
        "-n",
        store_name,
        "get",
        "pods",
        "-l",
        "app.kubernetes.io/name=wordpress",
        "-o",
        "jsonpath={.items[0].status.containerStatuses[0].ready}",
    ]

    try:
        out = subprocess.check_output(cmd, text=True).strip()
    except Exception:
        out = ""

    new_status = "Ready" if out == "true" else "Provisioning"

    c = conn()
    # Only update if store exists
    exists = c.execute("SELECT 1 FROM stores WHERE id=?", (store_name,)).fetchone()
    if not exists:
        raise HTTPException(status_code=404, detail="Store not found in registry")

    c.execute("UPDATE stores SET status=? WHERE id=?", (new_status, store_name))
    c.commit()

    return {"id": store_name, "status": new_status}


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
