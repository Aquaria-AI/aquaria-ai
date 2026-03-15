/* ── Aquaria Admin Console — Frontend ─────────────────── */

const API = '';  // same origin
let TOKEN = '';
let chartInstances = {};

// ── Auth ──────────────────────────────────────────────
const $login    = document.getElementById('login-overlay');
const $app      = document.getElementById('app');
const $pwd      = document.getElementById('login-password');
const $loginBtn = document.getElementById('login-btn');
const $loginErr = document.getElementById('login-error');

$loginBtn.addEventListener('click', doLogin);
$pwd.addEventListener('keydown', e => { if (e.key === 'Enter') doLogin(); });
document.getElementById('logout-btn').addEventListener('click', () => {
  TOKEN = '';
  sessionStorage.removeItem('admin_token');
  $app.classList.add('hidden');
  $login.classList.remove('hidden');
  $pwd.value = '';
});

// Auto-login from session
const saved = sessionStorage.getItem('admin_token');
if (saved) { TOKEN = saved; showApp(); }

async function doLogin() {
  $loginErr.textContent = '';
  const pw = $pwd.value.trim();
  if (!pw) return;
  try {
    const r = await fetch(`${API}/api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: pw }),
    });
    if (!r.ok) throw new Error('Invalid password');
    const d = await r.json();
    TOKEN = d.token;
    sessionStorage.setItem('admin_token', TOKEN);
    showApp();
  } catch (e) {
    $loginErr.textContent = e.message;
  }
}

function showApp() {
  $login.classList.add('hidden');
  $app.classList.remove('hidden');
  loadDashboard();
  loadFeedback();  // preload to populate badge
  loadFlagged();   // preload to populate badge
}

// ── Navigation ────────────────────────────────────────
const navLinks = document.querySelectorAll('.nav-link');
navLinks.forEach(link => {
  link.addEventListener('click', e => {
    e.preventDefault();
    navLinks.forEach(l => l.classList.remove('active'));
    link.classList.add('active');
    document.querySelectorAll('.section').forEach(s => s.classList.add('hidden'));
    const sec = link.dataset.section;
    document.getElementById(`sec-${sec}`).classList.remove('hidden');
    // Load data for section
    if (sec === 'dashboard') loadDashboard();
    else if (sec === 'flagged') loadFlagged();
    else if (sec === 'feedback') loadFeedback();
    else if (sec === 'activity') loadActivity();
    else if (sec === 'metrics') loadMetrics();
    else if (sec === 'usage') loadUsage();
    else if (sec === 'security') loadSecurity();
    else if (sec === 'signups') loadSignups();
    else if (sec === 'contacts') loadContacts();
  });
});

// ── Helpers ───────────────────────────────────────────
function api(path, opts = {}) {
  return fetch(`${API}${path}`, {
    ...opts,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
      ...(opts.headers || {}),
    },
  }).then(r => { if (!r.ok) throw new Error(`API ${r.status}`); return r.json(); });
}

function fmtDate(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function fmtDateTime(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' +
         d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
}

function destroyChart(id) {
  if (chartInstances[id]) { chartInstances[id].destroy(); delete chartInstances[id]; }
}

function makeLineChart(canvasId, labels, datasets) {
  destroyChart(canvasId);
  const ctx = document.getElementById(canvasId).getContext('2d');
  chartInstances[canvasId] = new Chart(ctx, {
    type: 'line',
    data: { labels, datasets },
    options: {
      responsive: true,
      interaction: { intersect: false, mode: 'index' },
      scales: {
        x: { ticks: { color: '#8b90a0', maxTicksLimit: 10 }, grid: { color: '#2e3345' } },
        y: { beginAtZero: true, ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } },
      },
      plugins: { legend: { labels: { color: '#e1e4ed' } } },
    },
  });
}

// ── Dashboard ─────────────────────────────────────────
async function loadDashboard() {
  const [summary, trends] = await Promise.all([
    api('/api/activity/summary'),
    api('/api/activity/trends?days=30'),
  ]);
  const t = summary.totals;
  const w = summary.last_7_days;
  document.getElementById('dash-stats').innerHTML = [
    statCard(t.dau_today, 'DAU Today', ''),
    statCard(t.users, 'Total Users', `+${w.new_users} this week`),
    statCard(t.tanks, 'Total Tanks', `+${w.new_tanks} this week`),
    statCard(t.logs, 'Total Logs', `+${w.new_logs} this week`),
    statCard(t.posts, 'Community Posts', `+${w.new_posts} this week`),
    statCard(t.feedback_open, 'Open Tickets', `${t.feedback_total} total`),
  ].join('');

  const labels = trends.dates.map(d => d.slice(5)); // MM-DD
  makeLineChart('dash-dau-chart', labels, [
    { label: 'Daily Active Users', data: trends.dau, borderColor: '#e05555', backgroundColor: 'rgba(224,85,85,0.1)', fill: true, tension: 0.3 },
  ]);
  makeLineChart('dash-chart', labels, [
    { label: 'Logs', data: trends.logs, borderColor: '#4f8ff7', tension: 0.3 },
    { label: 'Users', data: trends.users, borderColor: '#3dba6f', tension: 0.3 },
    { label: 'Tanks', data: trends.tanks, borderColor: '#e0a030', tension: 0.3 },
    { label: 'Posts', data: trends.posts, borderColor: '#c06de8', tension: 0.3 },
    { label: 'DAU', data: trends.dau, borderColor: '#e05555', borderWidth: 2, tension: 0.3 },
  ]);
}

function statCard(value, label, sub) {
  return `<div class="stat-card"><div class="value">${value}</div><div class="label">${label}</div><div class="sub">${sub}</div></div>`;
}

// ── Flagged Content ───────────────────────────────────
async function loadFlagged() {
  const posts = await api('/api/flagged-posts');
  const $list = document.getElementById('flagged-list');
  const $empty = document.getElementById('flagged-empty');
  // Update badge — count only unaddressed flagged posts
  const openCount = posts.filter(p => p.admin_action === null && p.flag_count > 0).length;
  const $badge = document.getElementById('flagged-badge');
  if (openCount > 0) { $badge.textContent = openCount; $badge.classList.remove('hidden'); }
  else { $badge.classList.add('hidden'); }
  if (!posts.length) { $list.innerHTML = ''; $empty.classList.remove('hidden'); return; }
  $empty.classList.add('hidden');
  $list.innerHTML = posts.map(p => `
    <div class="flag-card" id="flag-${p.id}">
      <img src="${p.photo_url}" alt="" onerror="this.style.display='none'">
      <div class="meta">
        <div class="user">@${p.username || p.display_name || 'unknown'}</div>
        <div class="caption">${escHtml(p.caption || '(no caption)')}</div>
        <div class="flags">${p.flag_count} flag(s): ${p.flag_reasons.join(', ')}</div>
        <div class="date">${fmtDateTime(p.created_at)} · ${p.is_hidden ? '<span class="badge badge-hidden">Hidden</span>' : '<span class="badge badge-active">Visible</span>'}</div>
      </div>
      <div class="actions">
        <button class="btn btn-success" onclick="postAction(${p.id},'appropriate')">Appropriate</button>
        <button class="btn btn-danger" onclick="postAction(${p.id},'inappropriate')">Inappropriate</button>
      </div>
    </div>
  `).join('');
}

async function postAction(id, action) {
  if (action === 'inappropriate' && !confirm('Remove this post? The user will be notified.')) return;
  await api(`/api/posts/${id}/action`, { method: 'POST', body: JSON.stringify({ action }) });
  loadFlagged();
}

function escHtml(s) {
  const d = document.createElement('div'); d.textContent = s; return d.innerHTML;
}

// ── Feedback ──────────────────────────────────────────
let feedbackData = [];

document.getElementById('fb-filter').addEventListener('change', renderFeedback);

async function loadFeedback() {
  feedbackData = await api('/api/feedback');
  updateFeedbackBadge();
  renderFeedback();
}

function updateFeedbackBadge() {
  const open = feedbackData.filter(f => f.ticket_status === 'new' || f.ticket_status === 'in_progress').length;
  const $badge = document.getElementById('fb-badge');
  if (open > 0) {
    $badge.textContent = open;
    $badge.classList.remove('hidden');
  } else {
    $badge.classList.add('hidden');
  }
}

function renderFeedback() {
  const filter = document.getElementById('fb-filter').value;
  const items = filter === 'all' ? feedbackData : feedbackData.filter(f => f.ticket_status === filter);
  const $body = document.getElementById('fb-body');
  const $empty = document.getElementById('fb-empty');
  if (!items.length) { $body.innerHTML = ''; $empty.classList.remove('hidden'); return; }
  $empty.classList.add('hidden');
  $body.innerHTML = items.map(f => `
    <tr>
      <td>${f.id}</td>
      <td>${fmtDateTime(f.created_at)}</td>
      <td>${escHtml(f.email || f.username || f.display_name || '—')}</td>
      <td class="msg-cell">${escHtml(f.message)}</td>
      <td>
        <select class="status-select" onchange="updateFeedback(${f.id}, 'ticket_status', this.value)">
          <option value="new" ${f.ticket_status === 'new' ? 'selected' : ''}>New</option>
          <option value="in_progress" ${f.ticket_status === 'in_progress' ? 'selected' : ''}>In Progress</option>
          <option value="resolved" ${f.ticket_status === 'resolved' ? 'selected' : ''}>Resolved</option>
        </select>
      </td>
      <td class="notes-cell">
        <textarea onblur="updateFeedback(${f.id}, 'admin_notes', this.value)">${escHtml(f.admin_notes || '')}</textarea>
      </td>
      <td>${f.attachment_url ? '<a href="' + escHtml(f.attachment_url) + '" target="_blank" title="' + escHtml(f.attachment_name || 'Attachment') + '"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#4f8ff7" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg></a>' : ''}</td>
    </tr>
  `).join('');
}

async function updateFeedback(id, field, value) {
  await api(`/api/feedback/${id}`, { method: 'PATCH', body: JSON.stringify({ [field]: value }) });
  // Update local cache
  const item = feedbackData.find(f => f.id === id);
  if (item) item[field] = value;
  updateFeedbackBadge();
}

// ── Activity Charts ───────────────────────────────────
async function loadActivity() {
  const trends = await api('/api/activity/trends?days=60');
  const labels = trends.dates.map(d => d.slice(5));
  makeLineChart('chart-dau', labels, [{ label: 'Daily Active Users', data: trends.dau, borderColor: '#e05555', backgroundColor: 'rgba(224,85,85,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-logs', labels, [{ label: 'Logs', data: trends.logs, borderColor: '#4f8ff7', backgroundColor: 'rgba(79,143,247,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-users', labels, [{ label: 'Users', data: trends.users, borderColor: '#3dba6f', backgroundColor: 'rgba(61,186,111,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-tanks', labels, [{ label: 'Tanks', data: trends.tanks, borderColor: '#e0a030', backgroundColor: 'rgba(224,160,48,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-posts', labels, [{ label: 'Posts', data: trends.posts, borderColor: '#c06de8', backgroundColor: 'rgba(192,109,232,0.1)', fill: true, tension: 0.3 }]);
}

// ── Feature Metrics ───────────────────────────────────
async function loadMetrics() {
  const m = await api('/api/metrics/overview');
  const colors = ['#4f8ff7','#3dba6f','#e0a030','#c06de8','#e05555','#5bc0de','#f0ad4e','#d9534f'];

  // Tasks
  const t = m.tasks;
  document.getElementById('metrics-tasks').innerHTML = [
    statCard(t.total, 'Total Tasks', ''),
    statCard(t.ai_created, 'AI Created', `${t.tasks_from_ai_rate || 0}% of total`),
    statCard(t.user_created, 'User Created', ''),
    statCard(t.dismissed, 'Dismissed', `${t.dismiss_rate}% rate`),
    statCard(t.recurring, 'Recurring', ''),
    statCard(t.one_off, 'One-Off', ''),
  ].join('');

  // Task source pie
  destroyChart('chart-task-source');
  chartInstances['chart-task-source'] = new Chart(document.getElementById('chart-task-source').getContext('2d'), {
    type: 'doughnut',
    data: { labels: ['AI', 'User'], datasets: [{ data: [t.ai_created, t.user_created], backgroundColor: ['#4f8ff7','#3dba6f'] }] },
    options: { plugins: { legend: { labels: { color: '#e1e4ed' } } } },
  });

  // Task outcome pie
  destroyChart('chart-task-outcome');
  const active = t.total - t.dismissed;
  chartInstances['chart-task-outcome'] = new Chart(document.getElementById('chart-task-outcome').getContext('2d'), {
    type: 'doughnut',
    data: { labels: ['Active', 'Dismissed'], datasets: [{ data: [active, t.dismissed], backgroundColor: ['#3dba6f','#e05555'] }] },
    options: { plugins: { legend: { labels: { color: '#e1e4ed' } } } },
  });

  // AI
  document.getElementById('metrics-ai').innerHTML = [
    statCard(m.ai.suggestions_converted, 'Suggestions → Tasks', `${m.ai.tasks_from_ai_rate}% of all tasks`),
  ].join('');

  // Community
  const c = m.community;
  document.getElementById('metrics-community').innerHTML = [
    statCard(c.total_posts, 'Posts', `${c.unique_posters} unique posters`),
    statCard(c.total_reactions, 'Reactions', ''),
    statCard(c.total_flags, 'Flags', ''),
    statCard(c.total_blocks, 'Blocks', ''),
  ].join('');

  // Emoji pie
  const emojiLabels = Object.keys(c.emoji_breakdown);
  const emojiData = Object.values(c.emoji_breakdown);
  destroyChart('chart-emoji');
  if (emojiLabels.length) {
    chartInstances['chart-emoji'] = new Chart(document.getElementById('chart-emoji').getContext('2d'), {
      type: 'doughnut',
      data: { labels: emojiLabels, datasets: [{ data: emojiData, backgroundColor: colors.slice(0, emojiLabels.length) }] },
      options: { plugins: { legend: { labels: { color: '#e1e4ed' } } } },
    });
  }

  // Tank setup
  const ts = m.tank_setup;
  document.getElementById('metrics-tank-setup').innerHTML = [
    statCard(ts.active_tanks, 'Active Tanks', ''),
    statCard(ts.with_equipment, 'With Equipment', `${ts.without_equipment} without`),
    statCard(ts.with_tap_water, 'With Tap Water', `${ts.without_tap_water} without`),
    statCard(ts.with_inhabitants, 'With Inhabitants', `${ts.without_inhabitants} without`),
    statCard(ts.with_plants, 'With Plants', `${ts.without_plants} without`),
  ].join('');

  // Inhabitant types pie
  const inhLabels = Object.keys(m.inhabitants.type_breakdown);
  const inhData = Object.values(m.inhabitants.type_breakdown);
  destroyChart('chart-inhab-types');
  if (inhLabels.length) {
    chartInstances['chart-inhab-types'] = new Chart(document.getElementById('chart-inhab-types').getContext('2d'), {
      type: 'doughnut',
      data: { labels: inhLabels, datasets: [{ data: inhData, backgroundColor: colors.slice(0, inhLabels.length) }] },
      options: { plugins: { legend: { labels: { color: '#e1e4ed' } } } },
    });
  }

  // Tank completeness bar
  destroyChart('chart-tank-completeness');
  chartInstances['chart-tank-completeness'] = new Chart(document.getElementById('chart-tank-completeness').getContext('2d'), {
    type: 'bar',
    data: {
      labels: ['Equipment', 'Tap Water', 'Inhabitants', 'Plants'],
      datasets: [
        { label: 'With', data: [ts.with_equipment, ts.with_tap_water, ts.with_inhabitants, ts.with_plants], backgroundColor: '#3dba6f' },
        { label: 'Without', data: [ts.without_equipment, ts.without_tap_water, ts.without_inhabitants, ts.without_plants], backgroundColor: '#2e3345' },
      ],
    },
    options: {
      responsive: true, indexAxis: 'y',
      scales: { x: { stacked: true, ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } }, y: { stacked: true, ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } } },
      plugins: { legend: { labels: { color: '#e1e4ed' } } },
    },
  });

  // Measurements
  const ms = m.measurements;
  document.getElementById('metrics-measurements').innerHTML = [
    statCard(ms.tanks_with_measurements_30d, 'Tanks Logging', `${ms.tanks_without_measurements_30d} inactive`),
    statCard(ms.total_entries_30d, 'Entries (30D)', ''),
  ].join('');

  // Parameter frequency bar
  const paramLabels = Object.keys(ms.parameter_frequency).sort((a,b) => ms.parameter_frequency[b] - ms.parameter_frequency[a]);
  const paramData = paramLabels.map(k => ms.parameter_frequency[k]);
  destroyChart('chart-params');
  if (paramLabels.length) {
    chartInstances['chart-params'] = new Chart(document.getElementById('chart-params').getContext('2d'), {
      type: 'bar',
      data: { labels: paramLabels, datasets: [{ label: 'Times Logged', data: paramData, backgroundColor: '#4f8ff7' }] },
      options: {
        responsive: true,
        scales: { x: { ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } }, y: { beginAtZero: true, ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } } },
        plugins: { legend: { display: false } },
      },
    });
  }

  // Notes & Photos
  document.getElementById('metrics-notes-photos').innerHTML = [
    statCard(m.notes.tanks_with_notes_30d, 'Tanks with Notes (30D)', `${m.notes.total_entries_30d} entries`),
    statCard(m.photos.total, 'Tank Photos', ''),
  ].join('');
}

// ── API Usage ─────────────────────────────────────────
async function loadUsage() {
  const data = await api('/api/usage/trends?days=30');
  const labels = data.dates.map(d => d.slice(5));
  const t = data.totals;

  document.getElementById('usage-stats').innerHTML = [
    statCard('$' + t.cost.toFixed(2), '30-Day Cost', ''),
    statCard(t.calls.toLocaleString(), 'API Calls', ''),
    statCard(t.tokens.toLocaleString(), 'Total Tokens', ''),
  ].join('');

  makeLineChart('chart-cost', labels, [{ label: 'Cost (USD)', data: data.daily_cost, borderColor: '#e05555', backgroundColor: 'rgba(224,85,85,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-calls', labels, [{ label: 'Calls', data: data.daily_calls, borderColor: '#4f8ff7', backgroundColor: 'rgba(79,143,247,0.1)', fill: true, tension: 0.3 }]);
  makeLineChart('chart-tokens', labels, [{ label: 'Tokens', data: data.daily_tokens, borderColor: '#e0a030', backgroundColor: 'rgba(224,160,48,0.1)', fill: true, tension: 0.3 }]);

  // Cost by model — bar chart
  const models = Object.keys(data.cost_by_model);
  const costs = models.map(m => data.cost_by_model[m]);
  const colors = ['#4f8ff7', '#3dba6f', '#e0a030', '#c06de8', '#e05555'];
  destroyChart('chart-model-cost');
  const ctx = document.getElementById('chart-model-cost').getContext('2d');
  chartInstances['chart-model-cost'] = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: models,
      datasets: [{ label: 'Cost (USD)', data: costs, backgroundColor: colors.slice(0, models.length) }],
    },
    options: {
      responsive: true,
      scales: {
        x: { ticks: { color: '#8b90a0' }, grid: { color: '#2e3345' } },
        y: { beginAtZero: true, ticks: { color: '#8b90a0', callback: v => '$' + v.toFixed(2) }, grid: { color: '#2e3345' } },
      },
      plugins: { legend: { display: false } },
    },
  });
}

// ── Security ──────────────────────────────────────────
async function loadSecurity() {
  const [users, blocked] = await Promise.all([
    api('/api/security/users'),
    api('/api/security/blocked'),
  ]);

  document.getElementById('security-body').innerHTML = users.map(u => {
    const cls = u.risk_score >= 10 ? 'risk-high' : u.risk_score >= 5 ? 'risk-med' : 'risk-low';
    return `<tr>
      <td><strong>@${escHtml(u.username || u.display_name || 'unknown')}</strong><br><span style="font-size:0.75rem;color:#8b90a0">${fmtDate(u.created_at)}</span></td>
      <td>${u.total_posts}</td>
      <td>${u.hidden_posts}</td>
      <td>${u.flags_received}</td>
      <td>${u.flags_cast}</td>
      <td>${u.times_blocked}</td>
      <td class="${cls}">${u.risk_score}</td>
    </tr>`;
  }).join('') || '<tr><td colspan="7" class="empty-msg">No users with activity.</td></tr>';

  document.getElementById('blocked-body').innerHTML = blocked.map(b => `
    <tr><td>${escHtml(b.blocker)}</td><td>${escHtml(b.blocked)}</td><td>${fmtDate(b.created_at)}</td></tr>
  `).join('') || '<tr><td colspan="3" class="empty-msg">No blocks.</td></tr>';
}

// ── Beta Signups ─────────────────────────────────────
async function loadSignups() {
  const rows = await api('/api/beta-signups');
  const $badge = document.getElementById('signups-badge');
  if (rows.length) { $badge.textContent = rows.length; $badge.classList.remove('hidden'); }
  else { $badge.classList.add('hidden'); }
  document.getElementById('signups-stats').innerHTML = statCard(rows.length, 'Total Signups', '');
  const $body = document.getElementById('signups-body');
  const $empty = document.getElementById('signups-empty');
  if (!rows.length) { $body.innerHTML = ''; $empty.classList.remove('hidden'); return; }
  $empty.classList.add('hidden');
  $body.innerHTML = rows.map((r, i) =>
    `<tr><td>${i + 1}</td><td>${escHtml(r.email)}</td><td>${fmtDateTime(r.created_at)}</td></tr>`
  ).join('');
}

// ── Contact Submissions ──────────────────────────────
async function loadContacts() {
  const rows = await api('/api/contact-submissions');
  const $badge = document.getElementById('contacts-badge');
  if (rows.length) { $badge.textContent = rows.length; $badge.classList.remove('hidden'); }
  else { $badge.classList.add('hidden'); }
  document.getElementById('contacts-stats').innerHTML = statCard(rows.length, 'Total Messages', '');
  const $body = document.getElementById('contacts-body');
  const $empty = document.getElementById('contacts-empty');
  if (!rows.length) { $body.innerHTML = ''; $empty.classList.remove('hidden'); return; }
  $empty.classList.add('hidden');
  $body.innerHTML = rows.map((r, i) =>
    `<tr><td>${i + 1}</td><td>${escHtml(r.email)}</td><td class="msg-cell">${escHtml(r.message || '')}</td><td>${fmtDateTime(r.created_at)}</td></tr>`
  ).join('');
}

// Expose to onclick handlers
window.postAction = postAction;
window.updateFeedback = updateFeedback;
