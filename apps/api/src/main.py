from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from .store_manager import create_store, delete_store
from .routes_store import router as store_router


app = FastAPI(title="Store Provisioning API")
app.include_router(store_router)

class StoreCreateRequest(BaseModel):
    name: str   # e.g. "store-demo-2"


@app.post("/stores")
def create_store_api(req: StoreCreateRequest):
    try:
        result = create_store(req.name)
        return {
            "status": "provisioning",
            "store_name": req.name,
            "url": f"http://{req.name}.localtest.me",
            "details": result
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/stores/{store_name}")
def delete_store_api(store_name: str):
    try:
        delete_store(store_name)
        return {
            "status": "deleted",
            "store_name": store_name
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
