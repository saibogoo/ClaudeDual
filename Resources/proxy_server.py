#!/usr/bin/env python3
"""
Claude Dual Proxy Server

A lightweight HTTP proxy that forwards requests to upstream API providers,
handling model name mapping and authentication scheme conversion.

Usage:
    python3 proxy_server.py <config_file>

Config file format (JSON):
    {
        "port": 18790,
        "target_url": "https://api.example.com/v1",
        "api_key": "sk-...",
        "auth_scheme": "bearer",
        "model_name": "upstream-model-name",
        "model_names": ["claude-sonnet-5", "claude-opus-5"],
        "model_mappings": {
            "claude-sonnet-5": "provider-sonnet-model",
            "claude-opus-5": "provider-opus-model"
        },
        "one_million_models": ["claude-sonnet-5"]
    }
"""

import sys
import json
import http.client
import urllib.parse
import socketserver
import http.server
import os


def load_config(config_path: str) -> dict:
    """Load configuration from JSON file."""
    with open(config_path, 'r') as f:
        config = json.load(f)
    api_key_env = config.get('api_key_env')
    if api_key_env:
        config['api_key'] = os.environ.get(api_key_env, '')
    return config


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    """HTTP request handler that forwards requests to upstream API."""

    config: dict = {}

    def log_message(self, format: str, *args) -> None:
        """Suppress default logging."""
        pass

    def _send_json(self, status: int, data: dict) -> None:
        """Send a JSON response."""
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_models(self) -> None:
        """Return local model metadata for Claude Desktop gateway checks."""
        default_models = [
            "claude-fable-5",
            "claude-opus-5",
            "claude-sonnet-5",
            "claude-haiku-4-5-20251001",
        ]
        configured_models = self.config.get("model_names")
        models = [model for model in configured_models if isinstance(model, str) and model] \
            if isinstance(configured_models, list) else default_models
        if not models:
            models = default_models
        one_million_models = self.config.get("one_million_models", [])
        self._send_json(200, {
            "object": "list",
            "data": [
                {
                    "type": "model",
                    "id": model,
                    "object": "model",
                    "display_name": model,
                    "owned_by": "claude-dual",
                    "created": 1767225600,
                    "created_at": "2026-01-01T00:00:00Z",
                    "context_window": 1000000 if model in one_million_models else 200000,
                }
                for model in models
            ],
            "has_more": False,
            "first_id": models[0],
            "last_id": models[-1],
        })

    def _is_models_request(self) -> bool:
        """Return whether the request targets the local models endpoint."""
        path = urllib.parse.urlparse(self.path).path.rstrip('/')
        return path == '/v1/models'

    def _forward(self, method: str) -> None:
        """Forward request to upstream API."""
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length else b''

        # Map model name in request body
        if body:
            try:
                data = json.loads(body)
                if isinstance(data, dict) and 'model' in data:
                    incoming_model = data['model']
                    model_mappings = self.config.get('model_mappings', {})
                    data['model'] = model_mappings.get(
                        incoming_model,
                        self.config['model_name'],
                    )
                    body = json.dumps(data).encode()
            except Exception:
                pass

        # Parse target URL
        target = urllib.parse.urlparse(self.config['target_url'])
        host = target.netloc
        base_path = target.path.rstrip('/') or ''

        # Handle /v1 prefix
        if base_path.endswith('/v1') and self.path.startswith('/v1/'):
            path = base_path[:-3] + self.path
        else:
            path = base_path + self.path

        # Create connection
        is_https = target.scheme == 'https'
        if is_https:
            conn = http.client.HTTPSConnection(host, timeout=120)
        else:
            conn = http.client.HTTPConnection(host, timeout=120)

        # Build headers
        headers = {}
        for k, v in self.headers.items():
            kl = k.lower()
            if kl not in ('host', 'content-length', 'transfer-encoding',
                          'connection', 'authorization', 'x-api-key',
                          'anthropic-api-key'):
                headers[k] = v

        # Add authentication
        auth_scheme = self.config.get('auth_scheme', 'bearer')
        api_key = self.config.get('api_key', '')
        if api_key:
            if auth_scheme == 'x-api-key':
                headers['x-api-key'] = api_key
            elif auth_scheme == 'anthropic-api-key':
                headers['anthropic-api-key'] = api_key
            else:
                headers['Authorization'] = 'Bearer ' + api_key

        headers['Content-Length'] = str(len(body))
        headers['Host'] = host

        try:
            # Forward request
            conn.request(method, path, body=body, headers=headers)
            resp = conn.getresponse()

            # Send response
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                kl = k.lower()
                if kl not in ('transfer-encoding', 'connection', 'content-length'):
                    self.send_header(k, v)
            self.end_headers()

            # Stream SSE line-by-line to avoid buffering token output.
            content_type = resp.getheader('Content-Type', '')
            if 'text/event-stream' in content_type.lower():
                while True:
                    line = resp.readline()
                    if not line:
                        break
                    self.wfile.write(line)
                    self.wfile.flush()
            else:
                while True:
                    chunk = resp.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()

        except Exception as e:
            self.send_error(502, str(e))
        finally:
            conn.close()

    def do_POST(self) -> None:
        if self._is_models_request():
            self._handle_models()
            return
        self._forward('POST')

    def do_GET(self) -> None:
        if self._is_models_request():
            self._handle_models()
            return
        self._forward('GET')

    def do_OPTIONS(self) -> None:
        if self._is_models_request():
            self._handle_models()
            return
        self._forward('OPTIONS')


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <config_file>", file=sys.stderr)
        sys.exit(1)

    config = load_config(sys.argv[1])
    ProxyHandler.config = config

    port = config['port']
    with socketserver.TCPServer(("127.0.0.1", port), ProxyHandler) as httpd:
        httpd.serve_forever()


if __name__ == '__main__':
    main()
