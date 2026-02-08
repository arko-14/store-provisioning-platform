import os
import sqlite3
from pathlib import Path

# In containers, write to /tmp by default (always writable)
# You can override via env var DB_PATH if you want persistence later.
DB_PATH = Path(os.environ.get("DB_PATH", "/tmp/stores.db"))

def conn():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    c = sqlite3.connect(str(DB_PATH))
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
