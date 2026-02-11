import { useEffect, useState } from "react";

const API_BASE = "/api";

async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!res.ok) {
    const msg =
      typeof data === "object" && data?.detail
        ? data.detail
        : `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return data;
}

export default function App() {
  const [stores, setStores] = useState([]);
  const [name, setName] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(false);

  async function load() {
    try {
      setLoading(true);
      const data = await fetchJson(`${API_BASE}/stores`);
      setStores(Array.isArray(data) ? data : []);
      setMsg("");
    } catch (e) {
      setMsg(`Load failed: ${e.message}`);
      setStores([]);
    } finally {
      setLoading(false);
    }
  }

  async function createStore() {
    const n = name.trim();
    if (!n) return;

    try {
      setLoading(true);
      setMsg("");
      const data = await fetchJson(`${API_BASE}/stores`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: n }),
      });
      setMsg(`Created: ${data.id} (${data.status})`);
      setName("");
      await load();
    } catch (e) {
      setMsg(`Create failed: ${e.message}`);
    } finally {
      setLoading(false);
    }
  }

  async function refreshStore(id) {
    try {
      setMsg("");
      await fetchJson(`${API_BASE}/stores/${id}/refresh`, { method: "POST" });
      await load();
    } catch (e) {
      setMsg(`Refresh failed: ${e.message}`);
    }
  }

  async function deleteStore(id) {
    if (!confirm(`Delete ${id}?`)) return;
    try {
      setMsg("");
      await fetchJson(`${API_BASE}/stores/${id}`, { method: "DELETE" });
      setMsg(`Deleted: ${id}`);
      await load();
    } catch (e) {
      setMsg(`Delete failed: ${e.message}`);
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 4000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
        <button onClick={createStore} style={{ padding: "10px 14px" }} disabled={loading}>
          Create Store
        </button>
        <button onClick={load} style={{ padding: "10px 14px" }} disabled={loading}>
          {loading ? "Loading..." : "Refresh"}
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
              <td>
                {s.url ? (
                  <a href={s.url} target="_blank" rel="noreferrer">{s.url}</a>
                ) : "-"}
              </td>
              <td>{s.created_at ? new Date(s.created_at * 1000).toLocaleString() : ""}</td>
              <td style={{ display: "flex", gap: 8 }}>
                <button onClick={() => refreshStore(s.id)}>Refresh</button>
                <button onClick={() => deleteStore(s.id)} style={{ color: "crimson" }}>
                  Delete
                </button>
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
