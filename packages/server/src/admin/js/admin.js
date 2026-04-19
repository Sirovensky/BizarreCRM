const API = '/api/v1/admin';
let currentBrowsePath = '';
let authToken = sessionStorage.getItem('admin_token') || '';

// XSS protection — escape HTML entities in dynamic values
function esc(str) { if (str == null) return ''; return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }
function fmt(bytes) { if (!bytes) return '0 B'; const u = ['B','KB','MB','GB']; let i = 0; let b = bytes; while (b >= 1024 && i < 3) { b /= 1024; i++; } return b.toFixed(i > 0 ? 1 : 0) + ' ' + u[i]; }
function fmtTime(s) { if (s < 60) return s + 's'; if (s < 3600) return Math.floor(s/60) + 'm'; const h = Math.floor(s/3600); return h + 'h ' + Math.floor((s%3600)/60) + 'm'; }
function fmtDate(iso) { if (!iso) return 'Never'; return new Date(iso).toLocaleString(); }

async function api(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json', 'X-Admin-Token': authToken } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(API + path, opts);
  if (r.status === 401) { showLogin(); return { success: false }; }
  return r.json();
}

function showLogin() {
  authToken = '';
  sessionStorage.removeItem('admin_token');
  document.getElementById('login-screen').style.display = 'flex';
  document.getElementById('main-screen').style.display = 'none';
}

function showMain() {
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('main-screen').style.display = 'block';
  load();
}

async function doLogin() {
  const user = document.getElementById('login-user').value;
  const pass = document.getElementById('login-pass').value;
  const err = document.getElementById('login-error');
  err.textContent = '';
  if (!user || !pass) { err.textContent = 'Enter username and password'; return; }
  try {
    const r = await fetch(API + '/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: user, password: pass }),
    });
    const data = await r.json();
    if (!data.success) { err.textContent = data.message || 'Login failed'; return; }
    authToken = data.data.token;
    sessionStorage.setItem('admin_token', authToken);
    showMain();
  } catch { err.textContent = 'Connection error'; }
}

async function doLogout() {
  await api('POST', '/logout');
  showLogin();
}

async function load() {
  const { data } = await api('GET', '/status');
  document.getElementById('db-size').textContent = fmt(data.dbSize);
  document.getElementById('uploads-size').textContent = fmt(data.uploadsSize);
  document.getElementById('uptime').textContent = fmtTime(data.uptime);
  document.getElementById('last-backup').textContent = data.backup.lastBackup ? fmtDate(data.backup.lastBackup) : 'Never';
  document.getElementById('info').textContent = `${esc(data.hostname)} | Port ${esc(data.port)} | ${esc(data.platform)} | Node ${esc(data.nodeVersion)}`;
  // Show dev mode banner if not production
  if (data.nodeEnv !== 'production') {
    document.getElementById('dev-banner').style.display = 'block';
  }
  document.getElementById('backup-path').value = data.backup.path || '';
  document.getElementById('backup-schedule').value = data.backup.schedule || '0 3 * * *';
  document.getElementById('backup-retention').value = data.backup.retention || 30;
  loadBackups();
}

// @audit-fixed: previously the Delete button used an inline onclick that
// double-escaped the backup name (`esc()` then a raw `.replace(/'/, …)`),
// resulting in broken handlers when filenames had special characters AND a
// real attribute-injection risk if a backup name contained a `'` or `>`.
// We now build the DOM with createElement, attach addEventListener, and
// pass the original (unescaped) name to delBackup — no string interpolation
// into HTML attributes at all.
async function loadBackups() {
  const { data } = await api('GET', '/backups');
  const el = document.getElementById('backups');
  el.innerHTML = '';
  if (!data || data.length === 0) {
    const msg = document.createElement('span');
    msg.className = 'text-muted text-sm';
    msg.textContent = 'No backups yet';
    el.appendChild(msg);
    return;
  }
  for (const b of data) {
    const row = document.createElement('div');
    row.className = 'backup-item';
    const meta = document.createElement('div');
    const name = document.createElement('span');
    name.className = 'text-sm';
    name.textContent = b.name;
    const sub = document.createElement('span');
    sub.className = 'text-xs text-muted';
    sub.textContent = `${fmt(b.size)} \u00b7 ${fmtDate(b.date)}`;
    meta.appendChild(name);
    meta.appendChild(document.createElement('br'));
    meta.appendChild(sub);
    const btn = document.createElement('button');
    btn.className = 'btn btn-danger text-xs';
    btn.textContent = 'Delete';
    btn.addEventListener('click', () => delBackup(b.name));
    row.appendChild(meta);
    row.appendChild(btn);
    el.appendChild(row);
  }
}

async function saveSettings() {
  await api('PUT', '/backup-settings', {
    path: document.getElementById('backup-path').value,
    schedule: document.getElementById('backup-schedule').value,
    retention: parseInt(document.getElementById('backup-retention').value) || 30,
  });
  alert('Settings saved');
  load();
}

async function backupNow() {
  const btn = document.getElementById('btn-backup');
  btn.disabled = true; btn.textContent = 'Backing up...';
  const { data } = await api('POST', '/backup');
  btn.disabled = false; btn.textContent = 'Backup Now';
  alert(data.success ? 'Backup completed!' : 'Backup failed: ' + data.message);
  load();
}

async function delBackup(name) {
  if (!confirm('Delete ' + name + '?')) return;
  await api('DELETE', '/backups/' + encodeURIComponent(name));
  loadBackups();
}

// Folder browser
async function toggleBrowser() {
  const el = document.getElementById('browser');
  if (el.style.display === 'none') { el.style.display = 'block'; loadDrives(); }
  else el.style.display = 'none';
}

async function loadDrives() {
  const { data } = await api('GET', '/drives');
  const drivesEl = document.getElementById('drives');
  drivesEl.innerHTML = data.map(d =>
    `<button class="btn btn-ghost text-xs" data-browse-path="${esc(d.path)}">${esc(d.label)} (${esc(fmt(d.free))} free)</button>`
  ).join('');
  drivesEl.querySelectorAll('[data-browse-path]').forEach(btn => {
    btn.addEventListener('click', () => browse(btn.getAttribute('data-browse-path')));
  });
}

async function browse(p) {
  currentBrowsePath = p;
  document.getElementById('browse-path').textContent = p;
  const { data } = await api('GET', '/drives/browse?path=' + encodeURIComponent(p));
  const foldersEl = document.getElementById('folders');
  if (!data.folders.length) {
    foldersEl.innerHTML = '<div class="text-sm text-muted" style="padding:.5rem">Empty folder</div>';
    return;
  }
  foldersEl.innerHTML = data.folders.map(f =>
    `<div class="folder-item" data-browse-path="${esc(f.path)}">📁 ${esc(f.name)}</div>`
  ).join('');
  foldersEl.querySelectorAll('[data-browse-path]').forEach(el => {
    el.addEventListener('dblclick', () => browse(el.getAttribute('data-browse-path')));
  });
}

// @audit-fixed: previously referenced `process?.platform` which only exists
// in Node — in the browser this throws ReferenceError on the no-parent path
// because optional chaining only protects null/undefined, not undeclared
// identifiers. We use navigator.platform as a heuristic instead.
function browseUp() {
  if (!currentBrowsePath) return;
  const isWin = (typeof navigator !== 'undefined' && /win/i.test(navigator.platform || ''));
  const parent = currentBrowsePath.replace(/[/\\][^/\\]+[/\\]?$/, '') || (isWin ? 'C:\\' : '/');
  browse(parent);
}

async function newFolder() {
  const name = prompt('New folder name:');
  if (!name || !name.trim()) return;
  await api('POST', '/drives/mkdir', { path: currentBrowsePath, name: name.trim() });
  browse(currentBrowsePath);
}

function selectFolder() {
  document.getElementById('backup-path').value = currentBrowsePath;
  document.getElementById('browser').style.display = 'none';
}

// Wire up event listeners instead of inline onclick attributes
document.addEventListener('DOMContentLoaded', function () {
  document.getElementById('login-pass').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') doLogin();
  });
  document.getElementById('login-user').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') document.getElementById('login-pass').focus();
  });
  document.querySelector('[data-action="login"]').addEventListener('click', doLogin);
  document.querySelector('[data-action="logout"]').addEventListener('click', doLogout);
  document.querySelector('[data-action="save-settings"]').addEventListener('click', saveSettings);
  document.querySelector('[data-action="backup-now"]').addEventListener('click', backupNow);
  document.querySelector('[data-action="toggle-browser"]').addEventListener('click', toggleBrowser);
  document.querySelector('[data-action="browse-up"]').addEventListener('click', browseUp);
  document.querySelector('[data-action="select-folder"]').addEventListener('click', selectFolder);
  document.querySelector('[data-action="new-folder"]').addEventListener('click', newFolder);

  // Init: check if we have a valid token
  if (authToken) {
    api('GET', '/status').then(r => { if (r.success) { showMain(); } else { showLogin(); } });
  } else {
    showLogin();
  }
});
