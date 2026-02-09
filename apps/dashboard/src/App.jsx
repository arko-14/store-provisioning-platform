import { useEffect, useState } from "react";

// Dev (localhost) -> call platform host directly (no /api prefix there)
// K8s (dashboard.localtest.me) -> call /api which nginx rewrites to API service
const isLocal = window.location.hostname === "localhost";
const LIST_URL = isLocal ? "http://platform.localtest.me/stores" : "/api/stores";
const CREATE_URL = isLocal ? "http://platform.localtest.me/stores" : "/api/stores";
const DELETE_URL = (id) =>
  isLocal
    ? `http://platform.localtest.me/stores/${id}`
    : `/api/stores/${id}`;
const REFRESH_URL = (id) =>
  isLocal
    ? `http://platform.localtest.me/stores/${id}/refresh`
    : `/api/stores/${id}/refresh`;

export default function App() {
  const [stores, setStores] = useState([]);
  const [name, setName] = useState("");
  const [msg, setMsg] = useState("");

  async function load() {
    setMsg("");
    try {
      const res = await fetch(LIST_URL);
      const data = await res.json();
      setStores(Array.isArray(data) ? data : []);
    } catch (e) {
      setMsg(String(e));
    }
  }

  async function createStore() {
    if (!name.trim()) return;
    setMsg("");
    try {
      const res = await fetch(CREATE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: name.trim() }),
      });
      const data = await res.json().catch(() => ({}));
      setMsg(data?.status ? `${data.id}: ${data.status}` : "Created");
      setName("");
      load();
    } catch (e) {
      setMsg(String(e));
    }
  }

  async function refreshStore(id) {
    setMsg("");
    await fetch(REFRESH_URL(id), { method: "POST" });
    load();
  }

  async function deleteStore(id) {
    if (!confirm(`Delete ${id}?`)) return;
    setMsg("");
    await fetch(DELETE_URL(id), { method: "DELETE" });
    load();
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 4000);
    return () => clearInterval(t);
  }, []);

  return (
    <div style={{ padding: 24, fontFamily: "system-ui", maxWidth: 1100, margin: "0 auto" }}>
      <h2>Store Provisioning Dashboard</h2>

      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="store name e.g. store-8"
          style={{ flex: 1, padding: 10 }}
        />
        <button onClick={createStore} style={{ padding: "10px 14px" }}>
          Create Store
        </button>
        <button onClick={load} style={{ padding: "10px 14px" }}>
          Refresh
        </button>
      </div>

      {msg && <div style={{ marginBottom: 12, padding: 10, background: "#f4f4f4" }}>{msg}</div>}

      <table width="100%" cellPadding="10" style={{ borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "1px solid #ddd" }}>
            <th>ID</th>
            <th>Status</th>
            <th>URL</th>
            <th>Created</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {stores.map((s) => (
            <tr key={s.id} style={{ borderBottom: "1px solid #eee" }}>
              <td><code>{s.id}</code></td>
              <td>{s.status}</td>
              <td>{s.url ? <a href={s.url} target="_blank" rel="noreferrer">{s.url}</a> : "-"}</td>
              <td>{s.created_at ? new Date(s.created_at * 1000).toLocaleString() : ""}</td>
              <td style={{ display: "flex", gap: 8 }}>
                <button onClick={() => refreshStore(s.id)}>Refresh</button>
                <button onClick={() => deleteStore(s.id)} style={{ color: "crimson" }}>Delete</button>
              </td>
            </tr>
          ))}
          {stores.length === 0 && (
            <tr><td colSpan="5" style={{ opacity: 0.7 }}>No stores yet.</td></tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
