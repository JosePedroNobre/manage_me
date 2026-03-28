# ManageMe

A unified dev dashboard that brings all your jobs together — Jira tickets, GitHub PRs, GitLab MRs, Bitbucket PRs — with Claude AI built in to plan features and review code under your name.

Built with Flutter. Runs locally. Everything stays on your device.

## What it does

- **Team-based setup** — Create a team for each job/project, connect services per team, switch between them instantly
- **Jira** — See your To Do and In Progress tickets, change status, view descriptions and image attachments, plan implementation with AI
- **GitHub** — Your PRs, review requests, assigned issues with AI-powered code review
- **GitLab** — Merge requests, assigned issues
- **Bitbucket** — Open PRs across your workspace with AI review
- **Claude AI** — Uses your Claude Code Max subscription (no API credits), streams output live in a terminal UI, caches results, supports follow-up prompts
- **PR Review** — Claude reviews diffs and posts comments under YOUR account
- **Ticket Planning** — Claude reads your codebase + ticket attachments and tells you exactly what files to change
- **Offline-first** — API responses are cached locally, works without internet using cached data

## Architecture

```
lib/
├── main.dart                          Entry point, Provider setup
├── theme/app_theme.dart               Design system
├── services/
│   ├── storage_service.dart           Team/connection config + secure storage
│   ├── app_state.dart                 State management (ChangeNotifier)
│   ├── api_client.dart                CORS proxy-aware HTTP client
│   ├── jira_service.dart              Jira Cloud REST API v3
│   ├── github_service.dart            GitHub REST API
│   ├── gitlab_service.dart            GitLab REST API
│   ├── bitbucket_service.dart         Bitbucket Cloud REST API
│   └── claude_service.dart            Claude Code bridge client (SSE streaming)
├── screens/
│   ├── setup_screen.dart              Team creation + service config
│   ├── dashboard_screen.dart          Tab shell + usage stats
│   └── tabs/
│       ├── overview_tab.dart          Stats + Slack placeholder
│       ├── jira_tab.dart              Tickets + status change + AI planning
│       ├── github_tab.dart            PRs + issues + AI review
│       ├── gitlab_tab.dart            MRs + issues
│       └── bitbucket_tab.dart         PRs + AI review
└── widgets/
    ├── common.dart                    StatusPill, StatCard, IssueCard, etc.
    └── detail_dialog.dart             Generic detail sheet

cors_proxy.py          Local CORS proxy (port 9090) — routes browser API calls
claude_bridge.py       Claude Code bridge (port 9091) — runs CLI, streams output, proxies images
start.command          Double-click to launch everything
```

## Setup

### Prerequisites

- Flutter SDK (3.10+)
- Python 3
- Claude Code installed (VS Code extension)
- A Claude Max subscription (for AI features)

### Run

```bash
# Install dependencies
flutter pub get

# Build for web
flutter build web --release
```

Then just **double-click `start.command`** in Finder. It launches all 3 services, opens your browser, and stops everything cleanly with Ctrl+C.

```bash
# Or from terminal:
./start.command
```

Opens at **http://localhost:8080**

### Manual start (if you prefer separate terminals)

```bash
# Terminal 1 — CORS proxy (routes API calls from browser)
python3 cors_proxy.py

# Terminal 2 — Claude bridge (runs Claude Code CLI)
python3 claude_bridge.py

# Terminal 3 — Web server
cd build/web && python3 -m http.server 8080
```

### Or run natively

```bash
flutter run -d macos    # macOS desktop (no proxy needed)
flutter run -d chrome   # Chrome (needs proxy)
```

## Connecting services

### Jira
- **Domain**: `yourteam.atlassian.net`
- **Email**: Your Atlassian login email
- **Token**: Create at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

### GitHub
- **Token**: Create at [github.com/settings/tokens](https://github.com/settings/tokens?type=beta) — needs Repositories (Read), Pull Requests (Read), Issues (Read)

### GitLab
- **Domain**: `gitlab.com` or self-hosted
- **Token**: Create at [gitlab.com/-/user_settings/personal_access_tokens](https://gitlab.com/-/user_settings/personal_access_tokens) — needs `read_api`, `read_user`

### Bitbucket
- **Workspace**: The slug from your URL (e.g. `vinturas` from `bitbucket.org/vinturas`)
- **Email**: Same as Jira
- **Token**: Same Atlassian API token as Jira
- **Repos**: Comma-separated repo slugs to track, or leave empty for all

### Claude AI
- Toggle on in team setup
- Set **Project path** to your local repo so Claude can see your codebase
- Requires the bridge server running (`python3 claude_bridge.py` or `start.command`)
- Uses your existing Claude Code Max subscription — no API credits needed

## How Claude AI works

The bridge server (`claude_bridge.py`) finds the Claude Code binary from your VS Code extensions and runs it as a subprocess. It streams output back to the web app via Server-Sent Events.

| Endpoint | Purpose |
|----------|---------|
| `/implement` | Plans a Jira ticket implementation (downloads ticket images so Claude can see mockups) |
| `/review` | Reviews a PR diff |
| `/prompt` | Free-form follow-up questions |
| `/img` | Proxies Jira images with auth for the browser |
| `/browse` | Folder picker for project path |
| `/usage` | Claude Code usage stats from `~/.claude/stats-cache.json` |

PR review comments are posted using YOUR GitHub/Bitbucket token, so they appear under your name.

## Ports

| Port | Service |
|------|---------|
| 8080 | Web app |
| 9090 | CORS proxy |
| 9091 | Claude bridge |
