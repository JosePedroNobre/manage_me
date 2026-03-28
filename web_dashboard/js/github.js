// ── GitHub REST API integration ───────────────────────────────
import { cacheGet, cacheSet } from './storage.js';

export class GitHubClient {
  constructor(token) {
    this.base = 'https://api.github.com';
    this.headers = {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json'
    };
  }

  async _get(url, cacheKey, ttl = 180_000) {
    const cached = await cacheGet(cacheKey);
    if (cached) return cached;
    const res = await fetch(url, { headers: this.headers });
    if (!res.ok) throw new Error(`GitHub ${res.status}: ${res.statusText}`);
    const data = await res.json();
    await cacheSet(cacheKey, data, ttl);
    return data;
  }

  async getUser() {
    return this._get(`${this.base}/user`, 'gh_user', 600_000);
  }

  async getMyPRs() {
    const user = await this.getUser();
    const q = encodeURIComponent(`is:pr is:open author:${user.login}`);
    return this._get(`${this.base}/search/issues?q=${q}&per_page=30&sort=updated`, 'gh_my_prs', 180_000);
  }

  async getReviewRequests() {
    const user = await this.getUser();
    const q = encodeURIComponent(`is:pr is:open review-requested:${user.login}`);
    return this._get(`${this.base}/search/issues?q=${q}&per_page=30&sort=updated`, 'gh_review_reqs', 180_000);
  }

  async getAssignedIssues() {
    const q = encodeURIComponent('is:issue is:open assignee:@me');
    return this._get(`${this.base}/search/issues?q=${q}&per_page=30&sort=updated`, 'gh_assigned', 180_000);
  }

  async getOrgRepos(org) {
    return this._get(`${this.base}/orgs/${org}/repos?per_page=100&sort=updated`, `gh_repos_${org}`, 300_000);
  }

  async getRepoPRs(owner, repo) {
    return this._get(
      `${this.base}/repos/${owner}/${repo}/pulls?state=open&per_page=30&sort=updated`,
      `gh_prs_${owner}_${repo}`, 180_000
    );
  }

  async getPRFiles(owner, repo, number) {
    return this._get(
      `${this.base}/repos/${owner}/${repo}/pulls/${number}/files?per_page=100`,
      `gh_pr_files_${owner}_${repo}_${number}`, 300_000
    );
  }

  async getPRDetails(owner, repo, number) {
    return this._get(
      `${this.base}/repos/${owner}/${repo}/pulls/${number}`,
      `gh_pr_detail_${owner}_${repo}_${number}`, 180_000
    );
  }

  generateReviewSuggestions(files) {
    const suggestions = [];
    for (const f of files) {
      if (f.additions > 300) {
        suggestions.push({ file: f.filename, type: 'size', msg: `Large change (+${f.additions} lines) — consider splitting` });
      }
      if (f.filename.includes('test') && f.changes === 0) {
        suggestions.push({ file: f.filename, type: 'test', msg: 'Test file unchanged — verify coverage' });
      }
      if (f.patch?.includes('TODO') || f.patch?.includes('FIXME') || f.patch?.includes('HACK')) {
        suggestions.push({ file: f.filename, type: 'todo', msg: 'Contains TODO/FIXME — address before merge?' });
      }
      if (f.patch?.includes('console.log') || f.patch?.includes('debugger')) {
        suggestions.push({ file: f.filename, type: 'debug', msg: 'Debug statements found — remove before merge' });
      }
      if (f.filename.match(/\.(env|key|pem|secret)/)) {
        suggestions.push({ file: f.filename, type: 'security', msg: 'Sensitive file modified — verify no secrets exposed' });
      }
      if (f.patch && (f.patch.match(/password/gi) || f.patch.match(/api[_-]?key/gi))) {
        suggestions.push({ file: f.filename, type: 'security', msg: 'Possible credential in diff — double-check' });
      }
    }
    return suggestions;
  }
}
