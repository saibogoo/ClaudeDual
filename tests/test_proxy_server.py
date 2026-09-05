import http.client
import http.server
import importlib.util
import json
import os
import pathlib
import socketserver
import tempfile
import threading
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "claude_dual_proxy", ROOT / "Resources" / "proxy_server.py"
)
PROXY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PROXY)


class RecordingUpstream(http.server.BaseHTTPRequestHandler):
    request_path = None
    request_headers = None
    request_body = None

    def log_message(self, _format, *_args):
        pass

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", "0"))
        type(self).request_path = self.path
        type(self).request_headers = dict(self.headers)
        type(self).request_body = json.loads(self.rfile.read(content_length))
        body = b'{"id":"response-test","object":"response","status":"completed"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


class ProxyServerTests(unittest.TestCase):
    def setUp(self):
        self.upstream = ReusableTCPServer(("127.0.0.1", 0), RecordingUpstream)
        self.upstream_thread = threading.Thread(target=self.upstream.serve_forever, daemon=True)
        self.upstream_thread.start()

        upstream_port = self.upstream.server_address[1]
        PROXY.ProxyHandler.config = {
            "target_url": f"http://127.0.0.1:{upstream_port}/v1",
            "api_key": "upstream-secret",
            "auth_scheme": "bearer",
            "model_name": "mapped-codex-model",
            "model_names": ["claude-mapped-a", "claude-mapped-b"],
            "model_mappings": {
                "claude-mapped-a": "upstream-model-a",
                "claude-mapped-b": "upstream-model-b",
            },
            "one_million_models": ["claude-mapped-a"],
        }
        self.proxy = ReusableTCPServer(("127.0.0.1", 0), PROXY.ProxyHandler)
        self.proxy_thread = threading.Thread(target=self.proxy.serve_forever, daemon=True)
        self.proxy_thread.start()

    def tearDown(self):
        self.proxy.shutdown()
        self.proxy.server_close()
        self.upstream.shutdown()
        self.upstream.server_close()

    def test_forwards_responses_api_with_model_mapping_and_upstream_auth(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.proxy.server_address[1])
        connection.request(
            "POST",
            "/v1/responses",
            body=json.dumps({"model": "claude-mapped-a", "input": "hello"}),
            headers={"Authorization": "Bearer local-token", "Content-Type": "application/json"},
        )
        response = connection.getresponse()
        payload = json.loads(response.read())
        connection.close()

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["status"], "completed")
        self.assertEqual(RecordingUpstream.request_path, "/v1/responses")
        self.assertEqual(RecordingUpstream.request_body["model"], "upstream-model-a")
        self.assertEqual(
            RecordingUpstream.request_headers["Authorization"], "Bearer upstream-secret"
        )

    def test_models_endpoint_returns_configured_mapping_names(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.proxy.server_address[1])
        connection.request("GET", "/v1/models")
        response = connection.getresponse()
        payload = json.loads(response.read())
        connection.close()

        self.assertEqual(response.status, 200)
        self.assertEqual([model["id"] for model in payload["data"]], ["claude-mapped-a", "claude-mapped-b"])
        self.assertEqual(payload["first_id"], "claude-mapped-a")
        self.assertEqual(payload["last_id"], "claude-mapped-b")
        self.assertEqual(payload["data"][0]["context_window"], 1000000)
        self.assertEqual(payload["data"][1]["context_window"], 200000)

    def test_unknown_model_uses_fallback_mapping(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.proxy.server_address[1])
        connection.request(
            "POST",
            "/v1/responses",
            body=json.dumps({"model": "unlisted-model", "input": "hello"}),
            headers={"Content-Type": "application/json"},
        )
        response = connection.getresponse()
        response.read()
        connection.close()

        self.assertEqual(response.status, 200)
        self.assertEqual(RecordingUpstream.request_body["model"], "mapped-codex-model")


class ProxyConfigurationTests(unittest.TestCase):
    def test_load_config_reads_key_from_inherited_environment(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as config_file:
            json.dump({"api_key_env": "CLAUDE_DUAL_TEST_KEY"}, config_file)
            config_file.flush()
            old_value = os.environ.get("CLAUDE_DUAL_TEST_KEY")
            os.environ["CLAUDE_DUAL_TEST_KEY"] = "environment-secret"
            try:
                config = PROXY.load_config(config_file.name)
            finally:
                if old_value is None:
                    os.environ.pop("CLAUDE_DUAL_TEST_KEY", None)
                else:
                    os.environ["CLAUDE_DUAL_TEST_KEY"] = old_value

        self.assertEqual(config["api_key"], "environment-secret")


if __name__ == "__main__":
    unittest.main()
