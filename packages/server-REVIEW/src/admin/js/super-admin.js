const API = '/super-admin/api';
let token = sessionStorage.getItem('sa_token');
let currentTab = 'dashboard';

// ─── API Helper ─────────────────────────────────────────────────
async function api(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (token) opts.headers['Authorization'] = `Bearer ${token}`;
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${API}${path}`, opts);
  const data = await res.json();
  if (res.status === 401 && path !== '/login') { logout(); throw new Error('Session expired'); }
  return { ok: res.ok, status: res.status, data };
}

async function logout() {
  try { if (token) await fetch(`${API}/logout`, { method: 'POST', headers: { 'Authorization': `Bearer ${token}` } }); } catch {}
  token = null;
  sessionStorage.removeItem('sa_token');
  render();
}

// XSS protection — escape HTML entities in dynamic values
function esc(str) {
  if (str == null) return '';
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

// ─── Login Flow ─────────────────────────────────────────────────
let loginStep = 'credentials'; // credentials | set-password | 2fa-setup | 2fa-verify
let challengeToken = '';
let qrUrl = '';
let secretCode = '';
let loginError = '';

function renderLogin() {
  const app = document.getElementById('app');
  let html = '<div class="login-wrapper"><div class="login-box">';
  html += '<div class="shield">🛡️</div>';
  html += '<h1>Super Admin</h1>';
  html += '<p class="subtitle">BizarreCRM Platform Administration</p>';

  if (loginStep === 'credentials') {
    html += `
      <div class="form-group"><label>Username</label><input id="username" type="text" autocomplete="username" autofocus></div>
      <div class="form-group"><label>Password</label><input id="password" type="password" autocomplete="current-password"></div>
      <button class="btn btn-primary" id="login-btn" data-action="login">Sign In</button>
    `;
  } else if (loginStep === 'set-password') {
    html += `
      <p class="info" style="margin-bottom:16px">Create a secure password (min 10 characters)</p>
      <div class="form-group"><label>New Password</label><input id="new-password" type="password" minlength="10" autofocus></div>
      <div class="form-group"><label>Confirm Password</label><input id="confirm-password" type="password"></div>
      <button class="btn btn-primary" data-action="set-password">Set Password</button>
    `;
  } else if (loginStep === '2fa-setup') {
    html += `
      <p class="info" style="margin-bottom:16px">Scan this QR code with Google Authenticator</p>
      <div class="qr-container"><img src="${esc(qrUrl)}" width="180" height="180" alt="QR Code"></div>
      <div class="secret-code">${esc(secretCode)}</div>
      <div class="form-group"><label>Enter 6-digit code to verify</label><input id="totp-code" type="text" maxlength="6" pattern="[0-9]{6}" autofocus></div>
      <button class="btn btn-primary" data-action="verify-2fa">Verify &amp; Complete Setup</button>
    `;
  } else if (loginStep === '2fa-verify') {
    html += `
      <div class="form-group"><label>Authenticator Code</label><input id="totp-code" type="text" maxlength="6" pattern="[0-9]{6}" autofocus placeholder="000000"></div>
      <button class="btn btn-primary" data-action="verify-2fa">Verify</button>
    `;
  }

  if (loginError) html += `<p class="error">${esc(loginError)}</p>`;
  html += '</div></div>';
  app.innerHTML = html;

  // Enter key support
  document.querySelectorAll('input').forEach(input => {
    input.addEventListener('keydown', e => { if (e.key === 'Enter') document.querySelector('.btn-primary')?.click(); });
  });

  // Wire up action buttons rendered into the login HTML
  const loginBtn = document.querySelector('[data-action="login"]');
  if (loginBtn) loginBtn.addEventListener('click', handleLogin);
  const setPwBtn = document.querySelector('[data-action="set-password"]');
  if (setPwBtn) setPwBtn.addEventListener('click', handleSetPassword);
  const verify2faBtn = document.querySelector('[data-action="verify-2fa"]');
  if (verify2faBtn) verify2faBtn.addEventListener('click', handleVerify2FA);
}

async function doLogin() {
  loginError = '';
  const username = document.getElementById('username')?.value;
  const password = document.getElementById('password')?.value;
  if (!username || !password) { loginError = 'Enter username and password'; renderLogin(); return; }
  const btn = document.getElementById('login-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Signing in...'; }
  try {
    const res = await fetch(`${API}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json();
    if (!res.ok) { loginError = data.message || 'Login failed'; renderLogin(); return; }
    challengeToken = data.data.challengeToken;
    if (data.data.requiresPasswordSetup) { loginStep = 'set-password'; }
    else if (data.data.requires2faSetup) { loginStep = '2fa-setup'; await do2FASetup(); return; }
    else if (data.data.totpEnabled) { loginStep = '2fa-verify'; }
    renderLogin();
  } catch (e) {
    loginError = 'Connection failed: ' + e.message;
    renderLogin();
  }
}

async function doSetPassword() {
  const pw = document.getElementById('new-password')?.value;
  const confirm = document.getElementById('confirm-password')?.value;
  if (!pw || pw.length < 10) { loginError = 'Password must be at least 10 characters'; renderLogin(); return; }
  if (pw !== confirm) { loginError = 'Passwords do not match'; renderLogin(); return; }
  try {
    const { ok, data } = await api('POST', '/login/set-password', { challengeToken, password: pw });
    if (!ok) { loginError = data.message; renderLogin(); return; }
    challengeToken = data.data.challengeToken;
    loginStep = '2fa-setup';
    await do2FASetup();
  } catch (e) { loginError = e.message; renderLogin(); }
}

async function do2FASetup() {
  try {
    const { ok, data } = await api('POST', '/login/2fa-setup', { challengeToken });
    if (!ok) { loginError = data.message; renderLogin(); return; }
    challengeToken = data.data.challengeToken;
    qrUrl = data.data.qr;
    secretCode = data.data.secret;
    loginStep = '2fa-setup';
    renderLogin();
  } catch (e) { loginError = e.message; renderLogin(); }
}

async function doVerify2FA() {
  const code = document.getElementById('totp-code')?.value;
  if (!code || code.length !== 6) { loginError = 'Enter a 6-digit code'; renderLogin(); return; }
  try {
    const { ok, data } = await api('POST', '/login/2fa-verify', { challengeToken, code });
    if (!ok) { loginError = data.message; renderLogin(); return; }
    token = data.data.token;
    sessionStorage.setItem('sa_token', token);
    loginStep = 'credentials';
    loginError = '';
    render();
  } catch (e) { loginError = e.message; renderLogin(); }
}

// ─── Safe wrappers (used as event handler callbacks) ──────────────
function handleLogin() { doLogin().catch(function(e) { loginError = e.message; renderLogin(); }); }
function handleSetPassword() { doSetPassword().catch(function(e) { loginError = e.message; renderLogin(); }); }
function handleVerify2FA() { doVerify2FA().catch(function(e) { loginError = e.message; renderLogin(); }); }

// ─── Dashboard ──────────────────────────────────────────────────
async function renderDashboard() {
  const app = document.getElementById('app');
  app.innerHTML = '<div class="container"><p>Loading...</p></div>';

  try {
    const { data: me } = await api('GET', '/me');
    const { data: dash } = await api('GET', '/dashboard');
    const d = dash.data;

    let html = `
      <div class="container">
        <div class="header">
          <h1>🛡️ BizarreCRM Super Admin</h1>
          <div class="user-info">
            <span>${esc(me.data.username)}</span>
            <button class="btn btn-sm btn-outline" data-action="logout">Sign Out</button>
          </div>
        </div>
        <div class="tabs">
          <button class="tab ${currentTab==='dashboard'?'active':''}" data-tab="dashboard">Dashboard</button>
          <button class="tab ${currentTab==='tenants'?'active':''}" data-tab="tenants">Tenants</button>
          <button class="tab ${currentTab==='backups'?'active':''}" data-tab="backups">Backups</button>
          <button class="tab ${currentTab==='audit'?'active':''}" data-tab="audit">Audit Log</button>
          <button class="tab ${currentTab==='sessions'?'active':''}" data-tab="sessions">Sessions</button>
        </div>
    `;

    if (currentTab === 'dashboard') {
      html += `
        <div class="kpi-grid">
          <div class="kpi"><div class="value">${d.active_tenants}</div><div class="label">Active Shops</div></div>
          <div class="kpi"><div class="value">${d.total_tenants}</div><div class="label">Total Tenants</div></div>
          <div class="kpi"><div class="value">${d.suspended_tenants}</div><div class="label">Suspended</div></div>
          <div class="kpi"><div class="value">${d.total_db_size_mb} MB</div><div class="label">Total DB Size</div></div>
          <div class="kpi"><div class="value">${d.memory_mb} MB</div><div class="label">Memory Usage</div></div>
          <div class="kpi"><div class="value">${d.uptime_hours}h</div><div class="label">Uptime</div></div>
          <div class="kpi"><div class="value">${d.pool_stats?.size || 0}/${d.pool_stats?.maxSize || 50}</div><div class="label">DB Pool</div></div>
        </div>
      `;
    }

    if (currentTab === 'tenants') {
      html += await renderTenantsTab();
    } else if (currentTab === 'backups') {
      html += await renderBackupsTab();
    } else if (currentTab === 'audit') {
      html += await renderAuditTab();
    } else if (currentTab === 'sessions') {
      html += await renderSessionsTab();
    }

    html += '</div>';
    app.innerHTML = html;

    // Wire up dashboard action buttons
    document.querySelectorAll('[data-action="logout"]').forEach(btn => {
      btn.addEventListener('click', logout);
    });
    document.querySelectorAll('[data-tab]').forEach(btn => {
      btn.addEventListener('click', function() { switchTab(this.getAttribute('data-tab')); });
    });
    document.querySelectorAll('[data-action="new-tenant"]').forEach(btn => {
      btn.addEventListener('click', showCreateTenantDialog);
    });
    document.querySelectorAll('[data-action="suspend"]').forEach(btn => {
      btn.addEventListener('click', function() { handleSuspend(this.getAttribute('data-slug')); });
    });
    document.querySelectorAll('[data-action="activate"]').forEach(btn => {
      btn.addEventListener('click', function() { handleActivate(this.getAttribute('data-slug')); });
    });
    document.querySelectorAll('[data-action="delete-tenant"]').forEach(btn => {
      btn.addEventListener('click', function() { handleDelete(this.getAttribute('data-slug')); });
    });
    document.querySelectorAll('[data-action="revoke-session"]').forEach(btn => {
      btn.addEventListener('click', function() { handleRevokeSession(this.getAttribute('data-session-id')); });
    });
  } catch (e) {
    app.innerHTML = `<div class="container"><p class="error">${esc(e.message)}</p></div>`;
  }
}

async function renderTenantsTab() {
  const { data } = await api('GET', '/tenants');
  const tenants = data.data.tenants;
  let html = `
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
        <h3>Tenants (${tenants.length})</h3>
        <button class="btn btn-sm btn-primary" data-action="new-tenant">+ New Shop</button>
      </div>
      <table>
        <thead><tr><th>Slug</th><th>Name</th><th>Plan</th><th>Status</th><th>DB Size</th><th>Created</th><th>Actions</th></tr></thead>
        <tbody>
  `;
  for (const t of tenants) {
    const statusBadge = t.status === 'active' ? 'badge-green' : t.status === 'suspended' ? 'badge-amber' : 'badge-gray';
    html += `<tr>
      <td><strong>${esc(t.slug)}</strong></td>
      <td>${esc(t.name)}</td>
      <td>${esc(t.plan)}</td>
      <td><span class="badge ${statusBadge}">${esc(t.status)}</span></td>
      <td>${esc(t.db_size_mb)} MB</td>
      <td>${esc((t.created_at||'').substring(0,10))}</td>
      <td class="actions">
        ${t.status === 'active' ? `<button class="btn btn-sm btn-outline" data-action="suspend" data-slug="${esc(t.slug)}">Suspend</button>` : ''}
        ${t.status === 'suspended' ? `<button class="btn btn-sm btn-outline" data-action="activate" data-slug="${esc(t.slug)}">Activate</button>` : ''}
        <button class="btn btn-sm btn-danger" data-action="delete-tenant" data-slug="${esc(t.slug)}">Delete</button>
      </td>
    </tr>`;
  }
  html += '</tbody></table></div>';
  return html;
}

async function renderBackupsTab() {
  const { data } = await api('GET', '/backups');
  let html = `<div class="card"><h3>Tenant Databases</h3><table>
    <thead><tr><th>Shop</th><th>Name</th><th>Size</th><th>Last Modified</th><th>Status</th></tr></thead><tbody>`;
  for (const b of data.data.tenants) {
    const statusBadge = b.status === 'active' ? 'badge-green' : 'badge-gray';
    html += `<tr><td><strong>${esc(b.slug)}</strong></td><td>${esc(b.name)}</td><td>${esc(b.db_size_mb)} MB</td><td>${esc((b.last_modified||'').substring(0,19).replace('T',' '))}</td><td><span class="badge ${statusBadge}">${esc(b.status)}</span></td></tr>`;
  }
  html += `</tbody></table><p style="margin-top:12px;font-size:12px;color:#64748b">Master DB: ${data.data.master_db_size_mb} MB</p></div>`;
  return html;
}

async function renderAuditTab() {
  const { data } = await api('GET', '/audit-log?limit=100');
  let html = `<div class="card"><h3>Audit Log</h3><table>
    <thead><tr><th>Time</th><th>Admin</th><th>Action</th><th>Details</th><th>IP</th></tr></thead><tbody>`;
  for (const log of data.data.logs) {
    html += `<tr><td style="white-space:nowrap">${esc((log.created_at||'').substring(0,19).replace('T',' '))}</td><td>${esc(log.admin_username||'—')}</td><td>${esc(log.action)}</td><td style="max-width:300px;overflow:hidden;text-overflow:ellipsis">${esc(log.details||'')}</td><td>${esc(log.ip_address||'')}</td></tr>`;
  }
  html += '</tbody></table></div>';
  return html;
}

async function renderSessionsTab() {
  const { data } = await api('GET', '/sessions');
  let html = `<div class="card"><h3>Active Sessions</h3><table>
    <thead><tr><th>Admin</th><th>IP</th><th>Created</th><th>Expires</th><th>Actions</th></tr></thead><tbody>`;
  for (const s of data.data.sessions) {
    html += `<tr><td>${esc(s.username)}</td><td>${esc(s.ip_address)}</td><td>${esc((s.created_at||'').substring(0,19).replace('T',' '))}</td><td>${esc((s.expires_at||'').substring(0,19).replace('T',' '))}</td><td><button class="btn btn-sm btn-danger" data-action="revoke-session" data-session-id="${esc(s.id)}">Revoke</button></td></tr>`;
  }
  html += '</tbody></table></div>';
  return html;
}

// ─── Actions ────────────────────────────────────────────────────
function switchTab(tab) { currentTab = tab; render(); }

function handleSuspend(slug) {
  if (!confirm('Suspend ' + slug + '? All users will be locked out immediately.')) return;
  api('POST', '/tenants/' + slug + '/suspend').then(function(r) {
    if (!r.ok) alert('Failed: ' + (r.data.message || 'Unknown error'));
    render();
  }).catch(function(e) { alert('Error: ' + e.message); });
}

function handleActivate(slug) {
  if (!confirm('Reactivate ' + slug + '?')) return;
  api('POST', '/tenants/' + slug + '/activate').then(function(r) {
    if (!r.ok) alert('Failed: ' + (r.data.message || 'Unknown error'));
    render();
  }).catch(function(e) { alert('Error: ' + e.message); });
}

function handleDelete(slug) {
  if (!confirm('DELETE ' + slug + '? This cannot be undone. Type the slug to confirm:')) return;
  var typed = prompt('Type "' + slug + '" to confirm deletion:');
  if (typed !== slug) { alert('Slug did not match. Deletion cancelled.'); return; }
  api('DELETE', '/tenants/' + slug).then(function(r) {
    if (!r.ok) alert('Failed: ' + (r.data.message || 'Unknown error'));
    render();
  }).catch(function(e) { alert('Error: ' + e.message); });
}

function handleRevokeSession(id) {
  if (!confirm('Revoke this session? The admin will be logged out.')) return;
  api('DELETE', '/sessions/' + id).then(function(r) {
    if (!r.ok) alert('Failed: ' + (r.data.message || 'Unknown error'));
    render();
  }).catch(function(e) { alert('Error: ' + e.message); });
}

function showCreateTenantDialog() {
  const overlay = document.createElement('div');
  overlay.className = 'dialog-overlay';
  overlay.innerHTML = `
    <div class="dialog">
      <h3>Create New Shop</h3>
      <div class="form-group"><label>Subdomain (slug)</label><input id="d-slug" placeholder="joes-repair"></div>
      <div class="form-group"><label>Shop Name</label><input id="d-name" placeholder="Joe's Phone Repair"></div>
      <div class="form-group"><label>Admin Email</label><input id="d-email" type="email" placeholder="admin@shop.com"></div>
      <div class="form-group"><label>Plan</label><select id="d-plan"><option value="free">Free</option><option value="starter">Starter</option><option value="pro">Pro</option><option value="enterprise">Enterprise</option></select></div>
      <p style="font-size:11px;color:#8892b0;margin-top:8px">Shop admin will set their own password on first login.</p>
      <div id="d-error" class="error"></div>
      <div style="display:flex;gap:8px;margin-top:16px">
        <button class="btn btn-primary" style="flex:1" data-action="create-tenant">Create</button>
        <button class="btn btn-outline" style="flex:1" data-action="cancel-dialog">Cancel</button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);
  overlay.querySelector('[data-action="create-tenant"]').addEventListener('click', createTenant);
  overlay.querySelector('[data-action="cancel-dialog"]').addEventListener('click', function() {
    overlay.remove();
  });
}

async function createTenant() {
  const slug = document.getElementById('d-slug')?.value;
  const name = document.getElementById('d-name')?.value;
  const email = document.getElementById('d-email')?.value;
  const plan = document.getElementById('d-plan')?.value;
  const errEl = document.getElementById('d-error');

  if (!slug || !name || !email) { errEl.textContent = 'Slug, name, and email are required'; return; }
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug) || slug.length < 3 || slug.length > 30) {
    errEl.textContent = 'Slug must be 3-30 chars, lowercase letters/numbers/hyphens only'; return;
  }
  try {
    const { ok, data } = await api('POST', '/tenants', { slug, shop_name: name, admin_email: email, plan });
    if (!ok) { errEl.textContent = data.message; return; }
    document.querySelector('.dialog-overlay')?.remove();
    const setupUrl = data.data.setup_url || data.data.url;
    prompt('Shop created! Send this setup link to the shop admin (expires in 24h):', setupUrl);
    render();
  } catch (e) { errEl.textContent = e.message; }
}

// ─── Main Render ────────────────────────────────────────────────
function render() {
  if (!token) { renderLogin(); }
  else { renderDashboard(); }
}

render();
