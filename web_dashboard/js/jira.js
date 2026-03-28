// ── Jira Cloud REST API integration ───────────────────────────
import { cacheGet, cacheSet } from './storage.js';

export class JiraClient {
  constructor(domain, email, token) {
    this.base = `https://${domain}/rest/api/3`;
    this.agileBase = `https://${domain}/rest/agile/1.0`;
    this.headers = {
      'Authorization': 'Basic ' + btoa(`${email}:${token}`),
      'Accept': 'application/json'
    };
    this.domain = domain;
  }

  async _get(url, cacheKey, ttl = 300_000) {
    const cached = await cacheGet(cacheKey);
    if (cached) return cached;
    const res = await fetch(url, { headers: this.headers });
    if (!res.ok) throw new Error(`Jira ${res.status}: ${res.statusText}`);
    const data = await res.json();
    await cacheSet(cacheKey, data, ttl);
    return data;
  }

  async getMyself() {
    return this._get(`${this.base}/myself`, 'jira_myself', 600_000);
  }

  async getBoards() {
    return this._get(`${this.agileBase}/board?maxResults=50`, 'jira_boards', 600_000);
  }

  async getBoardSprints(boardId) {
    return this._get(
      `${this.agileBase}/board/${boardId}/sprint?state=active&maxResults=5`,
      `jira_sprints_${boardId}`, 300_000
    );
  }

  async getSprintIssues(sprintId) {
    return this._get(
      `${this.agileBase}/sprint/${sprintId}/issue?maxResults=100&fields=summary,status,assignee,priority,issuetype,updated`,
      `jira_sprint_issues_${sprintId}`, 180_000
    );
  }

  async getMyIssues() {
    const jql = encodeURIComponent('assignee=currentUser() AND resolution=Unresolved ORDER BY priority DESC, updated DESC');
    return this._get(
      `${this.base}/search?jql=${jql}&maxResults=50&fields=summary,status,priority,issuetype,project,updated`,
      'jira_my_issues', 180_000
    );
  }

  async getTeamWork(boardId) {
    // Get all issues in current sprint for the board
    const sprints = await this.getBoardSprints(boardId);
    if (!sprints.values?.length) return [];
    const sprint = sprints.values[0];
    const issues = await this.getSprintIssues(sprint.id);
    // Group by assignee
    const grouped = {};
    for (const issue of (issues.issues || [])) {
      const assignee = issue.fields.assignee?.displayName || 'Unassigned';
      const avatar = issue.fields.assignee?.avatarUrls?.['32x32'] || '';
      if (!grouped[assignee]) grouped[assignee] = { avatar, issues: [] };
      grouped[assignee].issues.push({
        key: issue.key,
        summary: issue.fields.summary,
        status: issue.fields.status?.name,
        statusCategory: issue.fields.status?.statusCategory?.key,
        priority: issue.fields.priority?.name,
        type: issue.fields.issuetype?.name,
        url: `https://${this.domain}/browse/${issue.key}`
      });
    }
    return { sprint: sprint.name, team: grouped };
  }
}
