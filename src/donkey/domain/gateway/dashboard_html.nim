## The dashboard shell served at `/dashboard`: static HTML that asks for the
## Bearer token and reads the `/api/*` routes from the browser.

func buildDashboardHtml*(): string =
  ## Dashboard shell. Public and data-free: the token is entered in the page
  ## and kept in sessionStorage, every table is filled at runtime through the
  ## Bearer-authenticated endpoints, and the CSP keeps script/connect local.
  result = """<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'">
<title>Donkey</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;margin:2rem;max-width:60rem;color:#1b1b1b}
h1{font-size:1.4rem;margin:0 0 1rem}
label{display:flex;gap:.5rem;align-items:center;margin-bottom:1rem;font-size:.9rem}
input{flex:1;padding:.4rem .6rem;border:1px solid #bbb;border-radius:6px}
button{padding:.4rem .9rem;border:1px solid #888;border-radius:6px;background:#f4f4f4;cursor:pointer}
pre{background:#f7f7f7;border:1px solid #e3e3e3;border-radius:8px;padding:.8rem;overflow:auto;max-height:20rem;font-size:.8rem}
h2{font-size:1rem;margin:1.2rem 0 .4rem}
table{width:100%;border-collapse:collapse;font-size:.8rem}
th,td{text-align:left;padding:.35rem .5rem;border-bottom:1px solid #e3e3e3;vertical-align:top}
</style>
</head>
<body>
<h1>Donkey</h1>
<label>Token <input id="token" type="password" autocomplete="off" placeholder="DONKEY_HTTP_TOKEN (obrigatório nas rotas /api)"></label>
<button id="save">Salvar e atualizar</button>
<h2>Status</h2>
<pre id="status">—</pre>
<h2>Sessões</h2>
<table>
<thead><tr><th>Sessão</th><th>Usuário</th><th>Canais</th><th>Último contato</th><th>Ativa</th></tr></thead>
<tbody id="sessions"><tr><td colspan="5">—</td></tr></tbody>
</table>
<h2>Providers</h2>
<table>
<thead><tr><th>Provider</th><th>Saúde</th><th>Cooldown</th><th>Chamadas</th><th>OK</th><th>Erros</th><th>Latência</th></tr></thead>
<tbody id="providers"><tr><td colspan="7">—</td></tr></tbody>
</table>
<h2>Nova conversa</h2>
<label>Usuário <input id="new-user" type="text" autocomplete="off" placeholder="userId (2ª coluna da tabela)"></label>
<button id="new-session">Nova conversa</button>
<pre id="action">—</pre>
<h2>Logs recentes</h2>
<pre id="logs">—</pre>
<script>
const $ = id => document.getElementById(id);
let token = sessionStorage.getItem('donkey_token') || '';
$('token').value = token;
function authHeaders() {
  const headers = {'Content-Type': 'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  return headers;
}
// A request without a token can never satisfy the mandatory bearer check on
// /api/sessions, /api/providers and the session action; the shell asks for the
// token first and does not hammer the endpoints with an answer it knows is 401.
function hasToken() {
  if (token) return true;
  $('token').focus();
  for (const id of ['sessions', 'providers']) {
    $(id).replaceChildren(row(['informe o token', '', '', '', '', '', '']));
  }
  return false;
}
async function get(path) {
  const headers = token ? {Authorization: 'Bearer ' + token} : {};
  const r = await fetch(path, {headers});
  return r.ok ? await r.text() : 'HTTP ' + r.status;
}
async function getJson(path) {
  const r = await fetch(path, {headers: authHeaders()});
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}
function row(cells) {
  const tr = document.createElement('tr');
  for (const text of cells) {
    const td = document.createElement('td');
    td.textContent = text;
    tr.appendChild(td);
  }
  return tr;
}
async function refreshSessions() {
  if (!hasToken()) return;
  try {
    const data = await getJson('/api/sessions');
    const body = $('sessions');
    body.replaceChildren();
    for (const s of (data.sessions || [])) {
      body.appendChild(row([
        s.sessionId || '', s.userId || '',
        (s.channels || []).join(', '),
        s.lastInboundAt || '—',
        s.live ? 'sim' : 'não',
      ]));
    }
    if (!body.firstChild) body.appendChild(row(['—', '—', '—', '—', '—']));
  } catch (e) {
    $('sessions').replaceChildren(row(['erro', String(e), '', '', '']));
  }
}
async function refreshProviders() {
  if (!hasToken()) return;
  try {
    const data = await getJson('/api/providers');
    const body = $('providers');
    body.replaceChildren();
    for (const p of data) {
      body.appendChild(row([
        p.id || '', p.health || '', p.cooldownUntil || '—',
        String(p.calls || 0), String(p.ok || 0), String(p.err || 0),
        String(p.avgLatencyMs || 0) + ' ms',
      ]));
    }
  } catch (e) {
    $('providers').replaceChildren(row(['erro', String(e), '', '', '', '', '']));
  }
}
async function refresh() {
  $('status').textContent = await get('/api/status');
  $('logs').textContent = await get('/api/logs?n=50');
  await refreshSessions();
  await refreshProviders();
}
$('save').onclick = () => {
  token = $('token').value.trim();
  sessionStorage.setItem('donkey_token', token);
  refresh();
};
$('new-session').addEventListener('click', async () => {
  const raw = $('new-user').value.trim();
  if (!raw) {
    $('action').textContent = 'informe o usuário';
    return;
  }
  if (!token) {
    $('action').textContent = 'informe o token';
    $('token').focus();
    return;
  }
  const r = await fetch('/api/sessions/' + encodeURIComponent(raw) + '/task', {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify({action: 'new'}),
  });
  $('action').textContent = r.ok ? 'aceito' : 'HTTP ' + r.status;
  refresh();
});
refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>
"""
