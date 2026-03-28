#!/usr/bin/env python3
"""
ManageMe — Local CORS Proxy

Runs on http://localhost:9090 and forwards API requests to Jira/GitHub/GitLab,
adding the necessary CORS headers so Flutter Web can make cross-origin calls.

Usage:
    python3 cors_proxy.py              # default port 9090
    python3 cors_proxy.py 9999         # custom port

How it works:
    GET  http://localhost:9090/https://api.github.com/user
    →  proxies to https://api.github.com/user with your original headers
    →  returns the response with Access-Control-Allow-Origin: *
"""

import sys
import http.server
import urllib.request
import urllib.error

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9090


class CORSProxyHandler(http.server.BaseHTTPRequestHandler):

    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Expose-Headers', '*')
        self.send_header('Access-Control-Max-Age', '86400')

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        self._proxy('GET')

    def do_POST(self):
        self._proxy('POST')

    def do_PUT(self):
        self._proxy('PUT')

    def do_DELETE(self):
        self._proxy('DELETE')

    def do_PATCH(self):
        self._proxy('PATCH')

    def _proxy(self, method):
        # The target URL is everything after the leading /
        target_url = self.path[1:]  # strip leading /

        if not target_url.startswith('http'):
            self.send_response(400)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(b'Bad request: URL must start with http(s)://')
            return

        # Read request body if present
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # Forward headers (except host)
        forward_headers = {}
        for key in self.headers:
            lower = key.lower()
            if lower in ('host', 'origin', 'referer', 'connection', 'accept-encoding'):
                continue
            forward_headers[key] = self.headers[key]

        try:
            req = urllib.request.Request(target_url, data=body, headers=forward_headers, method=method)
            with urllib.request.urlopen(req, timeout=30) as resp:
                response_body = resp.read()
                self.send_response(resp.status)
                self._send_cors_headers()
                # Forward response headers
                for key, val in resp.getheaders():
                    lower = key.lower()
                    if lower in ('access-control-allow-origin', 'transfer-encoding', 'connection', 'content-encoding'):
                        continue
                    self.send_header(key, val)
                self.send_header('Content-Length', str(len(response_body)))
                self.end_headers()
                self.wfile.write(response_body)
        except urllib.error.HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self._send_cors_headers()
            self.send_header('Content-Length', str(len(error_body)))
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            error_msg = f'Proxy error: {e}'.encode()
            self.send_response(502)
            self._send_cors_headers()
            self.send_header('Content-Length', str(len(error_msg)))
            self.end_headers()
            self.wfile.write(error_msg)

    def log_message(self, format, *args):
        method_and_url = args[0] if args else ''
        status = args[1] if len(args) > 1 else ''
        # Compact log
        print(f'  [{status}] {method_and_url}')


def main():
    server = http.server.HTTPServer(('127.0.0.1', PORT), CORSProxyHandler)
    print(f'''
╔══════════════════════════════════════════════╗
║  ManageMe CORS Proxy                         ║
║  Running on http://localhost:{PORT:<5}            ║
║                                              ║
║  Leave this running while using the web app  ║
║  Press Ctrl+C to stop                        ║
╚══════════════════════════════════════════════╝
''')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nProxy stopped.')
        server.server_close()


if __name__ == '__main__':
    main()
