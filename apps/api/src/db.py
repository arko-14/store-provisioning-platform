import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parents[3] / "data" / "stores.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

def conn():
    c = sqlite3.connect(DB_PATH)
    c.execute("""
      CREATE TABLE IF NOT EXISTS stores(
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        engine TEXT NOT NULL,
        url TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_error TEXT
      )
    """)
    c.commit()
    return c
