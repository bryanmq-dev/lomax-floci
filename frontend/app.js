// Helpers compartidos por las 3 vistas. Todo pasa por el proxy en /api/...
const API = "/api";

async function apiGet(path) {
  const res = await fetch(`${API}${path}`);
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

async function apiPostJSON(path, body) {
  const res = await fetch(`${API}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

async function apiPostForm(path, formData) {
  const res = await fetch(`${API}${path}`, { method: "POST", body: formData });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

function mostrarMensaje(el, texto, tipo) {
  el.textContent = texto;
  el.className = `mensaje ${tipo}`;
  el.hidden = false;
}
