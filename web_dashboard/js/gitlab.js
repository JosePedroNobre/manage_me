// ── GitLab REST API integration ───────────────────────────────
import { cacheGet, cacheSet } from './storage.js';

export class GitLabClient {
  constructor(domain, token) {
    this.base = `https://${domain}/api/v4`;
    this.headers = {
      'PRIVATE-TOKEN': token,
      'Accept': 'application/json'
    };
    this.domain = domain;
  }

  async _get(url, cacheKey, ttl = 180_000) {
    const cached = await cacheGet(cacheKey);
    if (cached) return cached;
    const res = await fetch(url, { headers: this.headers });
    if (!res.ok) throw new Error(`GitLab ${res.status}: ${res.statusText}`);
    const data = await res.json();
    await cacheSet(cacheKey, data, ttl);
    return data;
  }

  async getUser() {
    return this._get(`${this.base}/user`, 'gl_user', 600_000);
  }

  async getMyMRs() {
    return this._get(
      `${this.base}/merge_requests?state=opened&scope=created_by_me&per_page=30&order_by=updated_at`,
      'gl_my_mrs', 180_000
    );
  }

  async getReviewRequests() {
    return this._get(
      `${this.base}/merge_requests?state=opened&scope=assigned_to_me&per_page=30&order_by=updated_at`,
      'gl_review_reqs', 180_000
    );
  }

  async getAssignedIssues() {
    return this._get(
      `${this.base}/issues?state=opened&scope=assigned_to_me&per_page=30&order_by=updated_at`,
      'gl_assigned_issues', 180_000
    );
  }

  async getTodos() {
    return this._get(
      `${this.base}/todos?state=pending&per_page=30`,
      'gl_todos', 120_000
    );
  }

  async getProjects() {
    return this._get(
      `${this.base}/projects?membership=true&per_page=50&order_by=last_activity_at`,
      'gl_projects', 300_000
    );
  }

  async getProjectMRs(projectId) {
    return this._get(
      `${this.base}/projects/${projectId}/merge_requests?state=opened&per_page=30&order_by=updated_at`,
      `gl_proj_mrs_${projectId}`, 180_000
    );
  }

  async getMRChanges(projectId, mrIid) {
    return this._get(
      `${this.base}/projects/${projectId}/merge_requests/${mrIid}/changes`,
      `gl_mr_changes_${projectId}_${mrIid}`, 300_000
    );
  }
}
