// ── ManageMe Dashboard — Main App ─────────────────────────────
import { saveTokens, loadTokens, clearTokens, saveSettings, loadSettings } from './storage.js';
import { JiraClient } from './jira.js';
import { GitHubClient } from './github.js';
import { GitLabClient } from './gitlab.js';

// ── State ─────────────────────────────────────────────────────
let state = {
  tokens: loadTokens(),
  settings: loadSettings(),
  jira: null,
  github: null,
  gitlab: null,
  loading: {},
  data: {},
  selectedPRs: new Set(),
};

const $ = (s, ctx = document) => ctx.querySelector(s);
const $$ = (s, ctx = document) => [...ctx.querySelectorAll(s)];

// ── Boot ──────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  registerSW();
  updateOnlineStatus();
  window.addEventListener('online', updateOnlineStatus);
  window.addEventListener('offline', updateOnlineStatus);

  if (hasAnyToken()) {
    initClients();
    showDashboard();
  } else {
    showSetup();
  }
});

function registerSW() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }
}

function updateOnlineStatus() {
  const badge = $('#online-badge');
  if (!badge) return;
  badge.className = navigator.onLine ? 'online-badge' : 'online-badge offline';
  badge.textContent = navigator.onLine ? 'Online' : 'Offline';
}

function hasAnyToken() {
  const t = state.tokens;
  return t.jiraToken || t.githubToken || t.gitlabToken;
}

// ── Clients ───────────────────────────────────────────────────
function initClients() {
  const t = state.tokens;
  if (t.jiraDomain && t.jiraEmail && t.jiraToken) {
    state.jira = new JiraClient(t.jiraDomain, t.jiraEmail, t.jiraToken);
  }
  if (t.githubToken) {
    state.github = new GitHubClient(t.githubToken);
  }
  if (t.gitlabDomain && t.gitlabToken) {
    state.gitlab = new GitLabClient(t.gitlabDomain, t.gitlabToken);
  }
}

// ── Toast ─────────────────────────────────────────────────────
function toast(msg, type = '') {
  const container = $('#toast-container');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  container.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

// ── Setup Screen ──────────────────────────────────────────────
function showSetup() {
  $('#splash').classList.add('hidden');
  const app = $('#app');
  app.innerHTML = renderSetupHTML();
  app.classList.add('visible');

  // Prefill
  const t = state.tokens;
  if (t.jiraDomain)  $('#jira-domain').value = t.jiraDomain;
  if (t.jiraEmail)   $('#jira-email').value = t.jiraEmail;
  if (t.jiraToken)   $('#jira-token').value = t.jiraToken;
  if (t.githubToken) $('#github-token').value = t.githubToken;
  if (t.gitlabDomain) $('#gitlab-domain').value = t.gitlabDomain;
  if (t.gitlabToken)  $('#gitlab-token').value = t.gitlabToken;

  $('#setup-form').addEventListener('submit', e => {
    e.preventDefault();
    state.tokens = {
      jiraDomain:  $('#jira-domain').value.trim(),
      jiraEmail:   $('#jira-email').value.trim(),
      jiraToken:   $('#jira-token').value.trim(),
      githubToken: $('#github-token').value.trim(),
      gitlabDomain: $('#gitlab-domain').value.trim() || 'gitlab.com',
      gitlabToken:  $('#gitlab-token').value.trim(),
    };
    saveTokens(state.tokens);
    initClients();
    if (hasAnyToken()) {
      showDashboard();
    } else {
      toast('Please enter at least one token', 'error');
    }
  });
}

function renderSetupHTML() {
  return `
    <div class="setup-screen">
      <h1>Manage<span>Me</span></h1>
      <p class="sub">Connect your tools. Everything stays on your device.</p>
      <form id="setup-form">
        <div class="setup-card">
          <h2><span class="icon card-icon jira">J</span> Jira</h2>
          <p class="hint">Cloud instance — uses basic auth (email + API token)</p>
          <details class="help-details">
            <summary>How do I get these?</summary>
            <div class="help-body">
              <div class="help-step">
                <strong>Domain</strong> — Your Jira Cloud URL without <code>https://</code>. Example: if you access Jira at
                <code>https://myteam.atlassian.net</code>, enter <code>myteam.atlassian.net</code>.
              </div>
              <div class="help-step">
                <strong>Email</strong> — The email address you use to log in to Jira / Atlassian.
              </div>
              <div class="help-step">
                <strong>API Token</strong> — Generate one at:
                <a href="https://id.atlassian.com/manage-profile/security/api-tokens" target="_blank" rel="noopener">
                  id.atlassian.com/manage-profile/security/api-tokens
                </a>
                <ol>
                  <li>Click <strong>"Create API token"</strong></li>
                  <li>Give it a label (e.g. "ManageMe")</li>
                  <li>Copy the token and paste it here</li>
                </ol>
              </div>
              <div class="help-note">No OAuth or redirect URLs needed — this uses basic auth with your email + token directly from your browser.</div>
            </div>
          </details>
          <div class="field-row">
            <div class="field">
              <label>Domain</label>
              <input id="jira-domain" type="text" placeholder="yourteam.atlassian.net">
            </div>
          </div>
          <div class="field-row">
            <div class="field">
              <label>Email</label>
              <input id="jira-email" type="email" placeholder="you@company.com">
            </div>
            <div class="field">
              <label>API Token</label>
              <input id="jira-token" type="password" placeholder="Paste your Jira API token">
            </div>
          </div>
        </div>

        <div class="setup-card">
          <h2><span class="icon card-icon github">G</span> GitHub</h2>
          <p class="hint">Personal access token with <code>repo</code> scope</p>
          <details class="help-details">
            <summary>How do I get this?</summary>
            <div class="help-body">
              <div class="help-step">
                <strong>Option A — Fine-grained token (recommended)</strong>
                <ol>
                  <li>Go to <a href="https://github.com/settings/tokens?type=beta" target="_blank" rel="noopener">github.com/settings/tokens</a> (Fine-grained tokens)</li>
                  <li>Click <strong>"Generate new token"</strong></li>
                  <li>Name it (e.g. "ManageMe"), set expiration</li>
                  <li>Under <strong>Repository access</strong>, choose "All repositories" or select specific ones</li>
                  <li>Under <strong>Permissions &rarr; Repository</strong>, enable:
                    <ul>
                      <li><code>Pull requests</code> — Read</li>
                      <li><code>Issues</code> — Read</li>
                      <li><code>Contents</code> — Read (for PR file diffs)</li>
                    </ul>
                  </li>
                  <li>Click <strong>"Generate token"</strong> and copy it</li>
                </ol>
              </div>
              <div class="help-step">
                <strong>Option B — Classic token</strong>
                <ol>
                  <li>Go to <a href="https://github.com/settings/tokens/new" target="_blank" rel="noopener">github.com/settings/tokens/new</a></li>
                  <li>Check the <code>repo</code> scope (full access to repos)</li>
                  <li>Click <strong>"Generate token"</strong> and copy it</li>
                </ol>
              </div>
              <div class="help-note">No redirect URLs needed — this app calls the GitHub API directly from your browser using your token.</div>
            </div>
          </details>
          <div class="field-row single">
            <div class="field">
              <label>Token</label>
              <input id="github-token" type="password" placeholder="ghp_... or github_pat_...">
            </div>
          </div>
        </div>

        <div class="setup-card">
          <h2><span class="icon card-icon gitlab">L</span> GitLab</h2>
          <p class="hint">Personal access token with <code>read_api</code> scope</p>
          <details class="help-details">
            <summary>How do I get this?</summary>
            <div class="help-body">
              <div class="help-step">
                <strong>Domain</strong> — Use <code>gitlab.com</code> for GitLab SaaS, or your self-hosted domain (e.g. <code>gitlab.mycompany.com</code>).
              </div>
              <div class="help-step">
                <strong>Personal Access Token</strong>
                <ol>
                  <li>Go to <a href="https://gitlab.com/-/user_settings/personal_access_tokens" target="_blank" rel="noopener">GitLab &rarr; Preferences &rarr; Access Tokens</a>
                    <br><span class="help-url-hint">Self-hosted: <code>https://&lt;your-domain&gt;/-/user_settings/personal_access_tokens</code></span>
                  </li>
                  <li>Click <strong>"Add new token"</strong></li>
                  <li>Name it (e.g. "ManageMe"), set expiration</li>
                  <li>Select scopes:
                    <ul>
                      <li><code>read_api</code> — Read access to the API (issues, MRs, projects)</li>
                      <li><code>read_user</code> — Read your user profile</li>
                    </ul>
                  </li>
                  <li>Click <strong>"Create personal access token"</strong> and copy it</li>
                </ol>
              </div>
              <div class="help-note">No OAuth or redirect URLs needed — the token is sent directly from your browser to the GitLab API.</div>
            </div>
          </details>
          <div class="field-row">
            <div class="field">
              <label>Domain</label>
              <input id="gitlab-domain" type="text" placeholder="gitlab.com" value="gitlab.com">
            </div>
            <div class="field">
              <label>Token</label>
              <input id="gitlab-token" type="password" placeholder="glpat-...">
            </div>
          </div>
        </div>

        <div style="display:flex;gap:0.75rem;margin-top:1.5rem;">
          <button type="submit" class="btn btn-primary">Launch Dashboard</button>
        </div>
      </form>
    </div>
    <div id="toast-container" class="toast-container"></div>
  `;
}

// ── Dashboard ─────────────────────────────────────────────────
function showDashboard() {
  $('#splash')?.classList.add('hidden');
  const app = $('#app');
  app.innerHTML = renderDashboardShell();
  app.classList.add('visible');

  setupTabs();
  setupTopbarActions();
  loadAllData();
}

function renderDashboardShell() {
  const tabs = [];
  tabs.push({ id: 'overview', label: 'Overview' });
  if (state.jira)   tabs.push({ id: 'jira', label: 'Jira' });
  if (state.github)  tabs.push({ id: 'github', label: 'GitHub' });
  if (state.gitlab)  tabs.push({ id: 'gitlab', label: 'GitLab' });
  tabs.push({ id: 'team', label: 'Team' });

  return `
    <header class="topbar">
      <div class="brand">Manage<span>Me</span></div>
      <div class="topbar-actions">
        <span id="online-badge" class="online-badge">Online</span>
        <button class="refresh-btn" id="refresh-all" title="Refresh all data">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
        </button>
        <button class="btn btn-ghost btn-sm" id="settings-btn">Settings</button>
      </div>
    </header>
    <nav class="tab-bar">
      ${tabs.map((t, i) => `<button class="tab-btn${i === 0 ? ' active' : ''}" data-tab="${t.id}">${t.label}<span class="badge" id="badge-${t.id}" style="display:none"></span></button>`).join('')}
    </nav>
    <main class="main">
      ${tabs.map((t, i) => `<section class="tab-panel${i === 0 ? ' active' : ''}" id="panel-${t.id}"><div class="skeleton skeleton-card"></div><div class="skeleton skeleton-card"></div></section>`).join('')}
    </main>
    <div id="toast-container" class="toast-container"></div>
    <div class="modal-overlay" id="modal-overlay"><div class="modal" id="modal"></div></div>
  `;
}

// ── Tabs ──────────────────────────────────────────────────────
function setupTabs() {
  $$('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      $$('.tab-btn').forEach(b => b.classList.remove('active'));
      $$('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      $(`#panel-${btn.dataset.tab}`).classList.add('active');
    });
  });
}

function setupTopbarActions() {
  $('#refresh-all').addEventListener('click', () => {
    $('#refresh-all').classList.add('spinning');
    loadAllData().finally(() => {
      setTimeout(() => $('#refresh-all')?.classList.remove('spinning'), 600);
    });
  });
  $('#settings-btn').addEventListener('click', showSettingsModal);
}

function setBadge(tabId, count) {
  const badge = $(`#badge-${tabId}`);
  if (!badge) return;
  if (count > 0) {
    badge.textContent = count;
    badge.style.display = '';
  } else {
    badge.style.display = 'none';
  }
}

// ── Data Loading ──────────────────────────────────────────────
async function loadAllData() {
  const promises = [];
  if (state.jira) promises.push(loadJiraData());
  if (state.github) promises.push(loadGitHubData());
  if (state.gitlab) promises.push(loadGitLabData());
  await Promise.allSettled(promises);
  renderOverview();
  renderTeam();
}

// ── JIRA ──────────────────────────────────────────────────────
async function loadJiraData() {
  const panel = $('#panel-jira');
  if (!panel) return;
  try {
    const [myself, boards, myIssues] = await Promise.all([
      state.jira.getMyself(),
      state.jira.getBoards(),
      state.jira.getMyIssues(),
    ]);
    state.data.jiraUser = myself;
    state.data.jiraBoards = boards.values || [];
    state.data.jiraMyIssues = myIssues.issues || [];
    setBadge('jira', state.data.jiraMyIssues.length);
    renderJiraPanel();
  } catch (err) {
    panel.innerHTML = renderError('Jira', err.message);
    toast(`Jira error: ${err.message}`, 'error');
  }
}

function renderJiraPanel() {
  const panel = $('#panel-jira');
  if (!panel) return;
  const issues = state.data.jiraMyIssues || [];
  const boards = state.data.jiraBoards || [];

  const boardOptions = boards.map(b => `<option value="${b.id}" ${b.id == state.settings.jiraBoard ? 'selected' : ''}>${b.name}</option>`).join('');

  panel.innerHTML = `
    <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;flex-wrap:wrap;">
      <h2 class="section-title" style="margin:0">My Issues</h2>
      ${boards.length ? `
        <div class="select-wrap">
          <select id="jira-board-select">
            <option value="">Select board...</option>
            ${boardOptions}
          </select>
        </div>
      ` : ''}
    </div>
    ${issues.length ? `
      <div class="card-grid">
        ${issues.map(renderJiraCard).join('')}
      </div>
    ` : renderEmpty('No issues assigned to you')}
  `;

  const sel = $('#jira-board-select');
  if (sel) {
    sel.addEventListener('change', () => {
      state.settings.jiraBoard = sel.value;
      saveSettings(state.settings);
      if (sel.value) loadJiraTeamData(sel.value);
    });
    if (state.settings.jiraBoard) loadJiraTeamData(state.settings.jiraBoard);
  }
}

function renderJiraCard(issue) {
  const f = issue.fields;
  const statusCat = f.status?.statusCategory?.key;
  const statusClass = statusCat === 'done' ? 'done' : statusCat === 'indeterminate' ? 'progress' : 'todo';
  const priorityClass = (f.priority?.name || '').toLowerCase();
  const url = `https://${state.tokens.jiraDomain}/browse/${issue.key}`;

  return `
    <div class="card">
      <div class="card-header">
        <div class="card-icon jira">${typeIcon(f.issuetype?.name)}</div>
        <div>
          <div class="card-title"><a href="${url}" target="_blank">${issue.key}: ${esc(f.summary)}</a></div>
          <div class="card-meta">
            <span class="status-pill ${statusClass}">${esc(f.status?.name)}</span>
            ${f.priority ? `<span title="${esc(f.priority.name)}"><span class="priority-dot ${priorityClass}"></span> ${esc(f.priority.name)}</span>` : ''}
            <span>${esc(f.project?.name || '')}</span>
          </div>
        </div>
      </div>
    </div>
  `;
}

async function loadJiraTeamData(boardId) {
  try {
    const team = await state.jira.getTeamWork(boardId);
    state.data.jiraTeam = team;
    renderTeam();
  } catch (err) {
    toast(`Board load error: ${err.message}`, 'error');
  }
}

// ── GITHUB ────────────────────────────────────────────────────
async function loadGitHubData() {
  const panel = $('#panel-github');
  if (!panel) return;
  try {
    const [user, myPRs, reviewReqs, assigned] = await Promise.all([
      state.github.getUser(),
      state.github.getMyPRs(),
      state.github.getReviewRequests(),
      state.github.getAssignedIssues(),
    ]);
    state.data.ghUser = user;
    state.data.ghMyPRs = myPRs.items || [];
    state.data.ghReviewReqs = reviewReqs.items || [];
    state.data.ghAssigned = assigned.items || [];
    const total = state.data.ghMyPRs.length + state.data.ghReviewReqs.length + state.data.ghAssigned.length;
    setBadge('github', total);
    renderGitHubPanel();
  } catch (err) {
    panel.innerHTML = renderError('GitHub', err.message);
    toast(`GitHub error: ${err.message}`, 'error');
  }
}

function renderGitHubPanel() {
  const panel = $('#panel-github');
  if (!panel) return;
  const myPRs = state.data.ghMyPRs || [];
  const reviews = state.data.ghReviewReqs || [];
  const assigned = state.data.ghAssigned || [];

  panel.innerHTML = `
    <div class="stats-row">
      <div class="stat-card"><div class="stat-value">${myPRs.length}</div><div class="stat-label">My PRs</div></div>
      <div class="stat-card"><div class="stat-value">${reviews.length}</div><div class="stat-label">Review Requests</div></div>
      <div class="stat-card"><div class="stat-value">${assigned.length}</div><div class="stat-label">Assigned Issues</div></div>
    </div>

    ${reviews.length ? `
      <h3 class="section-title">Review Requests</h3>
      <div class="card-grid">${reviews.map(pr => renderGHPRCard(pr, true)).join('')}</div>
    ` : ''}

    ${myPRs.length ? `
      <h3 class="section-title">My Pull Requests</h3>
      <div class="card-grid">${myPRs.map(pr => renderGHPRCard(pr, false)).join('')}</div>
    ` : ''}

    ${assigned.length ? `
      <h3 class="section-title">Assigned Issues</h3>
      <div class="card-grid">${assigned.map(renderGHIssueCard).join('')}</div>
    ` : ''}

    ${!reviews.length && !myPRs.length && !assigned.length ? renderEmpty('Nothing on your plate') : ''}
  `;

  // Attach review buttons
  $$('.gh-review-btn', panel).forEach(btn => {
    btn.addEventListener('click', () => {
      const [owner, repo, num] = btn.dataset.pr.split('/');
      showPRReview(owner, repo, parseInt(num));
    });
  });
}

function renderGHPRCard(pr, showReviewBtn) {
  const repo = pr.repository_url?.split('/').slice(-2).join('/') || '';
  const num = pr.number;
  const age = timeAgo(pr.updated_at);
  const [owner, repoName] = repo.split('/');

  return `
    <div class="card">
      <div class="card-header">
        <div class="card-icon github">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>
        </div>
        <div style="flex:1;min-width:0;">
          <div class="card-title"><a href="${pr.html_url}" target="_blank">#${num} ${esc(pr.title)}</a></div>
          <div class="card-meta">
            <span>${esc(repo)}</span>
            <span>${age}</span>
            ${pr.draft ? '<span class="status-pill todo">Draft</span>' : ''}
          </div>
        </div>
      </div>
      ${showReviewBtn ? `<div style="margin-top:0.5rem;"><button class="btn btn-ghost btn-sm gh-review-btn" data-pr="${owner}/${repoName}/${num}">Analyze PR</button></div>` : ''}
    </div>
  `;
}

function renderGHIssueCard(issue) {
  const repo = issue.repository_url?.split('/').slice(-2).join('/') || '';
  return `
    <div class="card">
      <div class="card-header">
        <div class="card-icon github" style="background:var(--green-soft);color:var(--green);">!</div>
        <div>
          <div class="card-title"><a href="${issue.html_url}" target="_blank">#${issue.number} ${esc(issue.title)}</a></div>
          <div class="card-meta">
            <span>${esc(repo)}</span>
            <span>${timeAgo(issue.updated_at)}</span>
          </div>
        </div>
      </div>
    </div>
  `;
}

async function showPRReview(owner, repo, number) {
  const overlay = $('#modal-overlay');
  const modal = $('#modal');
  overlay.classList.add('active');
  modal.innerHTML = `<h2>Analyzing PR #${number}...</h2><div class="skeleton skeleton-card"></div>`;

  try {
    const files = await state.github.getPRFiles(owner, repo, number);
    const suggestions = state.github.generateReviewSuggestions(files);
    const totalAdditions = files.reduce((s, f) => s + f.additions, 0);
    const totalDeletions = files.reduce((s, f) => s + f.deletions, 0);

    modal.innerHTML = `
      <h2>${owner}/${repo} #${number}</h2>
      <div class="card-meta" style="margin-bottom:1rem;">
        <span>+${totalAdditions} / -${totalDeletions}</span>
        <span>${files.length} files changed</span>
      </div>
      ${suggestions.length ? `
        <h3 class="section-title" style="margin-top:1rem;">Review Suggestions</h3>
        ${suggestions.map(s => `
          <div class="suggestion-item">
            <div class="suggestion-icon ${s.type}">${suggestionIcon(s.type)}</div>
            <div>
              <div class="suggestion-text">${esc(s.msg)}</div>
              <div class="suggestion-file">${esc(s.file)}</div>
            </div>
          </div>
        `).join('')}
      ` : '<p style="color:var(--green);margin-top:1rem;">Looks clean — no obvious issues detected.</p>'}
      <h3 class="section-title" style="margin-top:1.25rem;">Files Changed</h3>
      <div style="max-height:200px;overflow-y:auto;">
        ${files.map(f => `
          <div style="font-family:var(--mono);font-size:0.78rem;padding:0.25rem 0;color:var(--text-2);">
            <span style="color:var(--green);">+${f.additions}</span>
            <span style="color:var(--red);">-${f.deletions}</span>
            ${esc(f.filename)}
          </div>
        `).join('')}
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost btn-sm" id="modal-close">Close</button>
        <a href="https://github.com/${owner}/${repo}/pull/${number}" target="_blank" class="btn btn-primary btn-sm">Open on GitHub</a>
      </div>
    `;
    $('#modal-close').addEventListener('click', () => overlay.classList.remove('active'));
  } catch (err) {
    modal.innerHTML = `<h2>Error</h2><p style="color:var(--red);">${esc(err.message)}</p>
      <div class="modal-actions"><button class="btn btn-ghost btn-sm" id="modal-close">Close</button></div>`;
    $('#modal-close').addEventListener('click', () => overlay.classList.remove('active'));
  }

  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.classList.remove('active'); });
}

// ── GITLAB ────────────────────────────────────────────────────
async function loadGitLabData() {
  const panel = $('#panel-gitlab');
  if (!panel) return;
  try {
    const [user, myMRs, reviews, assigned, todos] = await Promise.all([
      state.gitlab.getUser(),
      state.gitlab.getMyMRs(),
      state.gitlab.getReviewRequests(),
      state.gitlab.getAssignedIssues(),
      state.gitlab.getTodos(),
    ]);
    state.data.glUser = user;
    state.data.glMyMRs = myMRs || [];
    state.data.glReviews = reviews || [];
    state.data.glAssigned = assigned || [];
    state.data.glTodos = todos || [];
    const total = state.data.glMyMRs.length + state.data.glReviews.length + state.data.glAssigned.length;
    setBadge('gitlab', total);
    renderGitLabPanel();
  } catch (err) {
    panel.innerHTML = renderError('GitLab', err.message);
    toast(`GitLab error: ${err.message}`, 'error');
  }
}

function renderGitLabPanel() {
  const panel = $('#panel-gitlab');
  if (!panel) return;
  const myMRs = state.data.glMyMRs || [];
  const reviews = state.data.glReviews || [];
  const assigned = state.data.glAssigned || [];

  panel.innerHTML = `
    <div class="stats-row">
      <div class="stat-card"><div class="stat-value">${myMRs.length}</div><div class="stat-label">My MRs</div></div>
      <div class="stat-card"><div class="stat-value">${reviews.length}</div><div class="stat-label">Assigned MRs</div></div>
      <div class="stat-card"><div class="stat-value">${assigned.length}</div><div class="stat-label">Assigned Issues</div></div>
    </div>

    ${reviews.length ? `
      <h3 class="section-title">Assigned Merge Requests</h3>
      <div class="card-grid">${reviews.map(renderGLMRCard).join('')}</div>
    ` : ''}

    ${myMRs.length ? `
      <h3 class="section-title">My Merge Requests</h3>
      <div class="card-grid">${myMRs.map(renderGLMRCard).join('')}</div>
    ` : ''}

    ${assigned.length ? `
      <h3 class="section-title">Assigned Issues</h3>
      <div class="card-grid">${assigned.map(renderGLIssueCard).join('')}</div>
    ` : ''}

    ${!reviews.length && !myMRs.length && !assigned.length ? renderEmpty('Nothing here') : ''}
  `;
}

function renderGLMRCard(mr) {
  return `
    <div class="card">
      <div class="card-header">
        <div class="card-icon gitlab">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M22.65 14.39L12 22.13 1.35 14.39a.84.84 0 01-.3-.94l1.22-3.78 2.44-7.51A.42.42 0 014.82 2a.43.43 0 01.58 0 .42.42 0 01.11.18l2.44 7.49h8.1l2.44-7.51A.42.42 0 0118.6 2a.43.43 0 01.58 0 .42.42 0 01.11.18l2.44 7.51L23 13.45a.84.84 0 01-.35.94z"/></svg>
        </div>
        <div>
          <div class="card-title"><a href="${mr.web_url}" target="_blank">!${mr.iid} ${esc(mr.title)}</a></div>
          <div class="card-meta">
            <span>${esc(mr.source_branch)} &rarr; ${esc(mr.target_branch)}</span>
            <span>${timeAgo(mr.updated_at)}</span>
            ${mr.draft ? '<span class="status-pill todo">Draft</span>' : ''}
          </div>
        </div>
      </div>
    </div>
  `;
}

function renderGLIssueCard(issue) {
  return `
    <div class="card">
      <div class="card-header">
        <div class="card-icon gitlab" style="background:var(--green-soft);color:var(--green);">!</div>
        <div>
          <div class="card-title"><a href="${issue.web_url}" target="_blank">#${issue.iid} ${esc(issue.title)}</a></div>
          <div class="card-meta">
            <span>${timeAgo(issue.updated_at)}</span>
            ${(issue.labels || []).slice(0, 3).map(l => `<span class="status-pill review">${esc(l)}</span>`).join('')}
          </div>
        </div>
      </div>
    </div>
  `;
}

// ── Overview ──────────────────────────────────────────────────
function renderOverview() {
  const panel = $('#panel-overview');
  if (!panel) return;

  const jiraCount = (state.data.jiraMyIssues || []).length;
  const ghPRs = (state.data.ghMyPRs || []).length;
  const ghReviews = (state.data.ghReviewReqs || []).length;
  const ghIssues = (state.data.ghAssigned || []).length;
  const glMRs = (state.data.glMyMRs || []).length;
  const glReviews = (state.data.glReviews || []).length;
  const glIssues = (state.data.glAssigned || []).length;

  const totalTasks = jiraCount + ghIssues + glIssues;
  const totalPRs = ghPRs + glMRs;
  const totalReviews = ghReviews + glReviews;

  // Gather urgent items
  const urgent = [];

  // Reviews are most urgent
  for (const pr of (state.data.ghReviewReqs || [])) {
    urgent.push({ type: 'gh-review', title: pr.title, url: pr.html_url, meta: `GitHub PR #${pr.number}`, time: pr.updated_at });
  }
  for (const mr of (state.data.glReviews || [])) {
    urgent.push({ type: 'gl-review', title: mr.title, url: mr.web_url, meta: `GitLab MR !${mr.iid}`, time: mr.updated_at });
  }

  // High priority Jira
  for (const issue of (state.data.jiraMyIssues || []).slice(0, 5)) {
    const f = issue.fields;
    urgent.push({
      type: 'jira',
      title: `${issue.key}: ${f.summary}`,
      url: `https://${state.tokens.jiraDomain}/browse/${issue.key}`,
      meta: `${f.status?.name} · ${f.priority?.name || 'None'}`,
      time: f.updated,
    });
  }

  panel.innerHTML = `
    <div class="stats-row">
      <div class="stat-card"><div class="stat-value">${totalTasks}</div><div class="stat-label">Open Tasks</div></div>
      <div class="stat-card"><div class="stat-value">${totalPRs}</div><div class="stat-label">My PRs / MRs</div></div>
      <div class="stat-card"><div class="stat-value">${totalReviews}</div><div class="stat-label">Reviews Needed</div></div>
    </div>

    ${urgent.length ? `
      <h3 class="section-title">What Needs Your Attention</h3>
      <div class="card-grid">
        ${urgent.slice(0, 12).map(item => `
          <div class="card">
            <div class="card-header">
              <div class="card-icon ${item.type.startsWith('gh') ? 'github' : item.type.startsWith('gl') ? 'gitlab' : 'jira'}">
                ${item.type.includes('review') ? '!' : '&bull;'}
              </div>
              <div>
                <div class="card-title"><a href="${item.url}" target="_blank">${esc(item.title)}</a></div>
                <div class="card-meta">
                  <span>${esc(item.meta)}</span>
                  ${item.time ? `<span>${timeAgo(item.time)}</span>` : ''}
                </div>
              </div>
            </div>
          </div>
        `).join('')}
      </div>
    ` : renderEmpty('Connect your tools to see your tasks')}
  `;
}

// ── Team View ─────────────────────────────────────────────────
function renderTeam() {
  const panel = $('#panel-team');
  if (!panel) return;

  const teamData = state.data.jiraTeam;

  if (!teamData || !teamData.team) {
    panel.innerHTML = `
      <div class="empty-state">
        <div class="icon">&#128101;</div>
        <p>${state.jira ? 'Select a Jira board in the Jira tab to see team activity' : 'Connect Jira to see team activity'}</p>
      </div>
    `;
    return;
  }

  const entries = Object.entries(teamData.team);
  panel.innerHTML = `
    <h3 class="section-title">Sprint: ${esc(teamData.sprint)}</h3>
    ${entries.map(([name, data]) => {
      const initials = name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase();
      const doneCount = data.issues.filter(i => i.statusCategory === 'done').length;
      const inProgress = data.issues.filter(i => i.statusCategory === 'indeterminate').length;
      return `
        <div class="swimlane">
          <div class="swimlane-header" onclick="this.parentElement.classList.toggle('collapsed')">
            <div class="swimlane-avatar">
              ${data.avatar ? `<img src="${data.avatar}" alt="">` : initials}
            </div>
            <div class="swimlane-name">${esc(name)}</div>
            <div class="swimlane-count">${doneCount}/${data.issues.length} done · ${inProgress} in progress</div>
          </div>
          <div class="swimlane-body">
            ${data.issues.map(i => {
              const statusClass = i.statusCategory === 'done' ? 'done' : i.statusCategory === 'indeterminate' ? 'progress' : 'todo';
              const priClass = (i.priority || '').toLowerCase();
              return `
                <div class="card">
                  <div class="card-header">
                    <div class="card-icon jira">${typeIcon(i.type)}</div>
                    <div>
                      <div class="card-title"><a href="${i.url}" target="_blank">${esc(i.key)}: ${esc(i.summary)}</a></div>
                      <div class="card-meta">
                        <span class="status-pill ${statusClass}">${esc(i.status)}</span>
                        ${i.priority ? `<span><span class="priority-dot ${priClass}"></span> ${esc(i.priority)}</span>` : ''}
                      </div>
                    </div>
                  </div>
                </div>
              `;
            }).join('')}
          </div>
        </div>
      `;
    }).join('')}
  `;
}

// ── Settings Modal ────────────────────────────────────────────
function showSettingsModal() {
  const overlay = $('#modal-overlay');
  const modal = $('#modal');
  overlay.classList.add('active');

  modal.innerHTML = `
    <h2>Settings</h2>
    <p style="font-size:0.85rem;color:var(--text-2);margin-bottom:1.25rem;">
      Tokens are stored locally in your browser. They never leave your device.
    </p>
    <div style="display:flex;gap:0.75rem;flex-wrap:wrap;">
      <button class="btn btn-ghost btn-sm" id="edit-tokens-btn">Edit Tokens</button>
      <button class="btn btn-danger btn-sm" id="clear-data-btn">Clear All Data</button>
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost btn-sm" id="modal-close">Close</button>
    </div>
  `;

  $('#modal-close').addEventListener('click', () => overlay.classList.remove('active'));
  $('#edit-tokens-btn').addEventListener('click', () => {
    overlay.classList.remove('active');
    showSetup();
  });
  $('#clear-data-btn').addEventListener('click', () => {
    if (confirm('This will remove all tokens and cached data. Continue?')) {
      clearTokens();
      localStorage.clear();
      indexedDB.deleteDatabase('manageme');
      location.reload();
    }
  });
  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.classList.remove('active'); });
}

// ── Helpers ───────────────────────────────────────────────────
function esc(s) {
  if (!s) return '';
  const el = document.createElement('span');
  el.textContent = s;
  return el.innerHTML;
}

function timeAgo(dateStr) {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

function typeIcon(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('bug')) return '&#128027;';
  if (t.includes('story')) return '&#128214;';
  if (t.includes('epic')) return '&#9889;';
  if (t.includes('sub')) return '&#8627;';
  return '&#9679;';
}

function suggestionIcon(type) {
  switch (type) {
    case 'security': return '&#128274;';
    case 'size': return '&#128200;';
    case 'debug': return '&#128736;';
    case 'todo': return '&#9745;';
    case 'test': return '&#9889;';
    default: return '&bull;';
  }
}

function renderError(service, msg) {
  return `<div class="empty-state"><div class="icon">&#9888;</div><p>${service}: ${esc(msg)}</p><p style="font-size:0.8rem;margin-top:0.5rem;">Check your token and try again</p></div>`;
}

function renderEmpty(msg) {
  return `<div class="empty-state"><div class="icon">&#128203;</div><p>${msg}</p></div>`;
}
