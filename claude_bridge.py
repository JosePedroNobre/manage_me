#!/usr/bin/env python3
"""
ManageMe — Claude Code Bridge Server

Runs on http://localhost:9091 and proxies AI review requests through
the local Claude Code CLI, using your existing Max subscription.

Usage:
    python3 claude_bridge.py              # default port 9091
    python3 claude_bridge.py 9999         # custom port
"""

import sys
import os
import glob
import json
import subprocess
import http.server
import shutil
import urllib.request
import urllib.error

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9091

_claude_path_cache = None

# Usage tracking
_usage = {
    'total_requests': 0,
    'reviews': 0,
    'plans': 0,
    'prompts': 0,
    'total_chars_out': 0,
    'started_at': None,
}

def _track(label, chars=0):
    _usage['total_requests'] += 1
    _usage[label] = _usage.get(label, 0) + 1
    _usage['total_chars_out'] += chars

def _find_claude():
    """Find the Claude Code binary — checks PATH, then VS Code extensions."""
    global _claude_path_cache
    if _claude_path_cache:
        return _claude_path_cache

    # 1. Check PATH
    found = shutil.which('claude')
    if found:
        _claude_path_cache = found
        return found

    # 2. Check VS Code extensions (macOS)
    home = os.path.expanduser('~')
    patterns = [
        os.path.join(home, '.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude'),
        os.path.join(home, '.vscode-insiders/extensions/anthropic.claude-code-*/resources/native-binary/claude'),
    ]
    for pattern in patterns:
        matches = sorted(glob.glob(pattern), reverse=True)  # newest version first
        for match in matches:
            if os.path.isfile(match) and os.access(match, os.X_OK):
                _claude_path_cache = match
                return match

    # 3. Common install locations
    for path in ['/usr/local/bin/claude', os.path.join(home, '.local/bin/claude'), os.path.join(home, 'bin/claude')]:
        if os.path.isfile(path):
            _claude_path_cache = path
            return path

    return None


def _run_claude_streaming(handler, prompt, label, project_path=None):
    """Run Claude Code CLI with stream-json and send live text chunks via SSE."""
    claude_bin = _find_claude()
    if not claude_bin:
        raise Exception('Claude Code not found.')

    cwd = project_path if project_path and os.path.isdir(project_path) else '/tmp'
    print(f'  Running from: {cwd}')

    process = subprocess.Popen(
        [claude_bin, '-p', prompt, '--output-format', 'stream-json', '--verbose', '--permission-mode', 'bypassPermissions'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        cwd=cwd,
    )

    handler.send_response(200)
    handler._cors()
    handler.send_header('Content-Type', 'text/event-stream')
    handler.send_header('Cache-Control', 'no-cache')
    handler.end_headers()

    full_text = []
    result_text = ''

    def send_sse(data):
        try:
            handler.wfile.write(f'data: {json.dumps(data)}\n\n'.encode())
            handler.wfile.flush()
        except:
            pass

    try:
        for raw_line in process.stdout:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                msg = json.loads(raw_line)
            except:
                # Not JSON — send raw line as text
                send_sse({"type": "text", "text": raw_line + '\n'})
                full_text.append(raw_line + '\n')
                continue

            msg_type = msg.get('type', '')

            # content_block_delta — streaming text chunks
            if msg_type == 'content_block_delta':
                chunk = msg.get('delta', {}).get('text', '')
                if chunk:
                    full_text.append(chunk)
                    send_sse({"type": "text", "text": chunk})

            # content_block_start
            elif msg_type == 'content_block_start':
                block = msg.get('content_block', {})
                if block.get('type') == 'text' and block.get('text'):
                    chunk = block['text']
                    full_text.append(chunk)
                    send_sse({"type": "text", "text": chunk})

            # result — final complete text
            elif msg_type == 'result':
                result_text = msg.get('result', '')

            # assistant message (initial)
            elif msg_type == 'assistant':
                content = msg.get('message', {}).get('content', [])
                for block in content:
                    if block.get('type') == 'text' and block.get('text'):
                        chunk = block['text']
                        full_text.append(chunk)
                        send_sse({"type": "text", "text": chunk})

    except Exception as e:
        print(f'  Stream error: {e}')

    process.wait(timeout=120)

    # Use result_text if available (it's the clean final output), else join chunks
    response_text = result_text if result_text else ''.join(full_text).strip()
    if not response_text:
        stderr_out = process.stderr.read() if process.stderr else ''
        response_text = stderr_out.strip() or 'No response from Claude'

    _usage['total_chars_out'] += len(response_text)
    print(f'  {label} done — {len(response_text)} chars')
    return response_text, None


class BridgeHandler(http.server.BaseHTTPRequestHandler):

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        """Handle GET routes."""
        if self.path == '/usage':
            # Merge local bridge stats with real Claude Code stats
            stats = dict(_usage)
            try:
                stats_file = os.path.join(os.path.expanduser('~'), '.claude', 'stats-cache.json')
                if os.path.exists(stats_file):
                    with open(stats_file) as f:
                        claude_stats = json.load(f)
                    activity = claude_stats.get('dailyActivity', [])
                    stats['claude_total_messages'] = sum(x.get('messageCount', 0) for x in activity)
                    stats['claude_total_tool_calls'] = sum(x.get('toolCallCount', 0) for x in activity)
                    stats['claude_total_sessions'] = sum(x.get('sessionCount', 0) for x in activity)
                    stats['claude_total_days'] = len(activity)
                    # Last 7 days for sparkline
                    recent = activity[-7:] if len(activity) >= 7 else activity
                    stats['claude_recent'] = [{'date': x['date'], 'messages': x['messageCount']} for x in recent]
                    # Today
                    from datetime import date
                    today = date.today().isoformat()
                    today_data = next((x for x in activity if x['date'] == today), None)
                    stats['claude_today_messages'] = today_data['messageCount'] if today_data else 0
                    stats['claude_today_tools'] = today_data['toolCallCount'] if today_data else 0
                    # Weekly stats
                    from datetime import date, timedelta
                    today_d = date.today()
                    week_start = today_d - timedelta(days=today_d.weekday())
                    next_monday = week_start + timedelta(days=7)
                    week_msgs = sum(x['messageCount'] for x in activity if x['date'] >= week_start.isoformat())
                    week_tools = sum(x['toolCallCount'] for x in activity if x['date'] >= week_start.isoformat())
                    week_sessions = sum(x['sessionCount'] for x in activity if x['date'] >= week_start.isoformat())
                    # Average daily to estimate weekly cap usage
                    avg_daily = stats['claude_total_messages'] / max(len(activity), 1)
                    estimated_weekly_cap = avg_daily * 7 * 3  # rough estimate
                    usage_pct = min(99, int(week_msgs / max(estimated_weekly_cap, 1) * 100)) if estimated_weekly_cap > 0 else 0
                    stats['week_messages'] = week_msgs
                    stats['week_tools'] = week_tools
                    stats['week_sessions'] = week_sessions
                    stats['week_reset'] = f'{next_monday.isoformat()}T11:00:00'
                    stats['week_reset_label'] = next_monday.strftime('%a, %H:00').replace('00:00', '11:00')
                    stats['usage_pct'] = usage_pct
            except Exception as e:
                stats['claude_stats_error'] = str(e)
            result = json.dumps(stats).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(result)))
            self.end_headers()
            self.wfile.write(result)
            return
        if self.path.startswith('/img'):
            return self._handle_image_proxy()
        if not self.path.startswith('/browse'):
            self.send_response(404)
            self._cors()
            self.end_headers()
            return

        from urllib.parse import unquote, urlparse, parse_qs
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        folder = unquote(params.get('path', [os.path.expanduser('~')])[0])

        try:
            entries = []
            # Parent
            parent = os.path.dirname(folder)
            if parent != folder:
                entries.append({'name': '..', 'path': parent, 'isDir': True})
            for name in sorted(os.listdir(folder)):
                if name.startswith('.'):
                    continue
                full = os.path.join(folder, name)
                if os.path.isdir(full):
                    entries.append({'name': name, 'path': full, 'isDir': True})
            result = json.dumps({'current': folder, 'entries': entries}).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(result)))
            self.end_headers()
            self.wfile.write(result)
        except Exception as e:
            error = json.dumps({'error': str(e)}).encode()
            self.send_response(500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def do_POST(self):
        if self.path not in ('/review', '/implement', '/prompt', '/implement-with-images'):
            self.send_response(404)
            self._cors()
            self.end_headers()
            self.wfile.write(b'Not found')
            return

        if self.path == '/implement' or self.path == '/implement-with-images':
            return self._handle_implement()

        if self.path == '/prompt':
            return self._handle_prompt()

        # /review

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
            pr_title = data.get('prTitle', '')
            pr_description = data.get('prDescription', '')
            diff = data.get('diff', '')

            prompt = f"""You are me — a developer reviewing a colleague's pull request. Write your comments exactly as I would: natural, direct, no fluff, no emojis, no AI-sounding language. Just talk like a normal developer leaving feedback on specific lines of code.

Rules:
- Only comment on actual changed lines in the diff. Don't comment on unchanged code.
- Reference the specific line or block you're talking about (e.g. "In the handleSubmit function..." or "Line where you set the state...")
- Keep each comment short — one or two sentences, like a real inline PR comment
- Sound human. Say things like "This might break if...", "Nit: maybe rename this to...", "Looks good but I'd watch out for...", "Why not use X here instead?"
- Never use emojis, bullet points, or headers
- Never say "Great work!" or "LGTM" unless the code is genuinely clean
- If something is fine, just say so briefly — don't over-explain

Severity guide:
- "critical" = will break in production or is a security hole
- "warning" = probably a bug or will cause issues
- "suggestion" = style, naming, or minor improvement

Format as JSON array only, no other text:
[{{"file": "path/to/file", "line": 42, "comment": "your comment here", "severity": "warning"}}]

The "line" field must be a line number from the NEW version of the file (the + side of the diff). Pick the most relevant changed line for each comment. If a comment applies to a block of code, use the first line of that block. Every comment MUST have a line number — no exceptions.

If nothing to flag:
[{{"file": "general", "line": 0, "comment": "Looks solid, nothing jumps out.", "severity": "info"}}]

PR: {pr_title}
{f'Context: {pr_description}' if pr_description else ''}

Diff:
{diff[:15000]}"""

            project_path = data.get('projectPath', '')
            _track('reviews')
            print(f'  Reviewing PR: {pr_title}...')

            import re
            response_text, comments = _run_claude_streaming(self, prompt, 'review', project_path)

            json_match = re.search(r'\[[\s\S]*\]', response_text)
            if json_match:
                try:
                    comments = json.loads(json_match.group(0))
                except:
                    comments = [{"file": "general", "comment": response_text, "severity": "info"}]
            else:
                comments = [{"file": "general", "comment": response_text, "severity": "info"}]

            final_event = json.dumps({"type": "done", "comments": comments, "raw": response_text})
            self.wfile.write(f'data: {final_event}\n\n'.encode())
            self.wfile.flush()
            print(f'  Done — {len(comments)} comments')

        except subprocess.TimeoutExpired:
            error = json.dumps({"error": "Claude Code timed out (120s)"}).encode()
            self.send_response(504)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

        except Exception as e:
            error = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def _handle_implement(self):
        import tempfile
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
            ticket_key = data.get('key', '')
            summary = data.get('summary', '')
            description = data.get('description', '')
            ticket_type = data.get('type', 'task')
            priority = data.get('priority', '')
            images = data.get('images', [])  # [{url, filename, auth}]

            # Download images to temp dir so Claude can see them
            image_paths = []
            if images:
                tmp_dir = tempfile.mkdtemp(prefix=f'manageme_{ticket_key}_')
                print(f'  Downloading {len(images)} images to {tmp_dir}')
                for img in images:
                    try:
                        img_url = img.get('url', '')
                        img_name = img.get('filename', 'image.png')
                        img_auth = img.get('auth', '')
                        headers = {'Accept': 'image/*,*/*'}
                        if img_auth:
                            headers['Authorization'] = f'Basic {img_auth}'
                        req = urllib.request.Request(img_url, headers=headers)
                        with urllib.request.urlopen(req, timeout=15) as resp:
                            img_path = os.path.join(tmp_dir, img_name)
                            with open(img_path, 'wb') as f:
                                f.write(resp.read())
                            image_paths.append(img_path)
                            print(f'    Downloaded: {img_name}')
                    except Exception as e:
                        print(f'    Failed to download {img.get("filename", "?")}: {e}')

            image_context = ''
            if image_paths:
                image_context = f"""

IMPORTANT: This ticket has {len(image_paths)} attached images (screenshots/mockups). They have been downloaded locally. Read them to understand the expected UI:
{chr(10).join(f'- {p}' for p in image_paths)}

Look at these images carefully before proposing the implementation. The UI should match what's shown in the screenshots."""

            prompt = f"""You are a senior Flutter/Dart developer. You need to IMPLEMENT this Jira ticket — not review code, not look at PRs, not analyze existing changes. This is about BUILDING A NEW FEATURE or FIXING A BUG from scratch.

Do NOT look at git history, PRs, or diffs. Focus entirely on what needs to be built based on the ticket description below.

Ticket: {ticket_key}
Type: {ticket_type}
Priority: {priority}
Title: {summary}

Requirements:
{description if description else '(no description — use the title as the requirement)'}
{image_context}

When implementing or modifying UI, always check ~/Downloads/ for design mockup images before starting. View all relevant images first, compare against existing code, then implement changes to match the design.

You are working on a Flutter project. Think like a senior developer who knows the Flutter ecosystem deeply — state management with Provider, clean architecture, proper widget composition, Dart best practices.

For each file that needs to change, explain:
- The exact Dart/Flutter code changes needed
- Widget structure if UI is involved
- State management approach
- Any new models, services, or utilities needed

Be specific with Dart code patterns. Reference actual Flutter APIs, widget names, and Dart syntax.

IMPORTANT: Never add comments in the code. Write clean, self-documenting code. Variable names, function names, and structure should make the intent obvious. No inline comments, no docstrings, no TODO comments. Clean code only.

Respond in JSON:
{{"files": [{{"path": "lib/path/to/file.dart", "changes": "Detailed description of what to implement in this file, including specific Flutter widgets, state logic, and Dart code patterns to use"}}], "edge_cases": ["Specific edge case relevant to Flutter/Dart"]}}"""

            _track('plans')
            print(f'  Planning: {ticket_key} — {summary}')

            claude_bin = _find_claude()
            if not claude_bin:
                raise Exception('Claude Code not found.')

            project_path = data.get('projectPath', '')
            import re
            response_text, _ = _run_claude_streaming(self, prompt, 'implement', project_path)

            json_match = re.search(r'\{[\s\S]*\}', response_text)
            if json_match:
                try:
                    plan = json.loads(json_match.group(0))
                except:
                    plan = {"files": [{"path": "general", "changes": response_text}], "edge_cases": []}
            else:
                plan = {"files": [{"path": "general", "changes": response_text}], "edge_cases": []}

            final_event = json.dumps({"type": "done", "plan": plan, "raw": response_text})
            self.wfile.write(f'data: {final_event}\n\n'.encode())
            self.wfile.flush()
            print(f'  Done — plan for {ticket_key}')

        except subprocess.TimeoutExpired:
            error = json.dumps({"error": "Claude Code timed out"}).encode()
            self.send_response(504)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

        except Exception as e:
            error = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def _handle_image_proxy(self):
        """Proxy Jira images with auth baked in — browsers can't send auth headers on <img> tags."""
        from urllib.parse import unquote, urlparse, parse_qs
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        url = unquote(params.get('url', [''])[0])
        auth = params.get('auth', [''])[0]

        if not url:
            self.send_response(400)
            self._cors()
            self.end_headers()
            return

        try:
            headers = {'Accept': 'image/*,*/*'}
            if auth:
                headers['Authorization'] = f'Basic {auth}'
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=15) as resp:
                img_data = resp.read()
                content_type = resp.headers.get('Content-Type', 'image/png')
                self.send_response(200)
                self._cors()
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', str(len(img_data)))
                self.send_header('Cache-Control', 'max-age=3600')
                self.end_headers()
                self.wfile.write(img_data)
        except Exception as e:
            self.send_response(502)
            self._cors()
            self.end_headers()
            self.wfile.write(f'Image proxy error: {e}'.encode())

    def _handle_prompt(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
            prompt = data.get('prompt', '')
            project_path = data.get('projectPath', '')
            context_text = data.get('context', '')

            full_prompt = prompt
            if context_text:
                full_prompt = f"""Context from previous conversation:
{context_text}

User's follow-up:
{prompt}"""

            _track('prompts')
            print(f'  Prompt: {prompt[:80]}...')
            response_text, _ = _run_claude_streaming(self, full_prompt, 'prompt', project_path)

            final_event = json.dumps({"type": "done", "raw": response_text})
            self.wfile.write(f'data: {final_event}\n\n'.encode())
            self.wfile.flush()

        except Exception as e:
            error = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def log_message(self, format, *args):
        pass  # quiet logs, we print our own


def main():
    claude_bin = _find_claude()
    if claude_bin:
        try:
            result = subprocess.run([claude_bin, '--version'], capture_output=True, text=True, timeout=5)
            print(f'  Claude Code: {result.stdout.strip()}')
            print(f'  Binary: {claude_bin}')
        except Exception:
            print(f'  Claude found at: {claude_bin}')
    else:
        print('  WARNING: Claude Code not found! Install it or check VS Code extensions.')

    import datetime
    _usage['started_at'] = datetime.datetime.now().isoformat()
    server = http.server.HTTPServer(('127.0.0.1', PORT), BridgeHandler)
    print(f'''
╔═══════════════════════════════════════════════╗
║  ManageMe — Claude Code Bridge                ║
║  Running on http://localhost:{PORT:<5}             ║
║                                               ║
║  Reviews use your Claude Max subscription     ║
║  No API credits needed                        ║
║  Press Ctrl+C to stop                         ║
╚═══════════════════════════════════════════════╝
''')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nBridge stopped.')
        server.server_close()


if __name__ == '__main__':
    main()
