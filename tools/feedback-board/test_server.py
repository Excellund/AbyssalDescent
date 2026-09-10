"""Exercise real HTTP/CLI boundaries against disposable feedback stores."""

from concurrent.futures import ThreadPoolExecutor
import http.client
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

from board import BoardServer, ROOT, process_lock, serving_info


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="feedback http test ")
        self.data = Path(self.temp.name) / "feedback data"
        self.server = BoardServer(self.data)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        request_headers = {"Origin": self.server.origin, "X-Feedback-Token": self.server.token}
        if body is not None:
            request_headers["Content-Type"] = "application/json"
            body = json.dumps(body).encode()
        request_headers.update(headers or {})
        try:
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            content = response.read()
            return response.status, dict(response.getheaders()), content
        finally:
            connection.close()

    def mutate(self, action, payload, revision):
        status, _, content = self.request("POST", "/api/action", {"revision": revision, "action": action, "payload": payload})
        return status, json.loads(content)

    def test_assets_session_and_empty_board(self):
        for path in ("/", "/app.js", "/app.css", "/api/session", "/api/health", "/api/board"):
            status, headers, content = self.request("GET", path)
            self.assertEqual(status, 200, path)
            self.assertEqual(headers["Cache-Control"], "no-store")
            self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        board = json.loads(content)
        self.assertEqual(board["board"]["items"], [])
        self.assertEqual(board["selection"]["kind"], "empty")

    def test_http_lifecycle_and_export(self):
        status, first = self.mutate("add", {"title": "Warnings are unclear", "notes": "<script>alert(1)</script>"}, 0)
        self.assertEqual(status, 200)
        identifier = first["selection"]["item"]["id"]
        self.assertEqual(first["board"]["items"][0]["notes"], "<script>alert(1)</script>")
        status, active = self.mutate("claim", {"owner": "task-one"}, 1)
        self.assertEqual((status, active["selection"]["kind"]), (200, "active"))
        status, _ = self.mutate("claim", {"owner": "task-two"}, 2)
        self.assertEqual(status, 409)
        status, waiting = self.mutate("status", {"id": identifier, "status": "awaiting_playtest", "owner": "task-one"}, 2)
        self.assertEqual((status, waiting["selection"]["kind"]), (200, "empty"))
        status, headers, content = self.request("GET", "/api/export")
        self.assertEqual(status, 200)
        self.assertIn("attachment", headers["Content-Disposition"])
        self.assertEqual(json.loads(content), waiting["board"])
        self.assertEqual(self.request("GET", "/api/backup")[0], 200)

    def test_origins_host_token_and_paths(self):
        change = {"revision": 0, "action": "add", "payload": {"title": "Unwanted"}}
        for headers in ({"Origin": "https://example.com"}, {"Host": "example.com"},
                        {"X-Feedback-Token": "bad"}, {"Sec-Fetch-Site": "cross-site"}):
            self.assertEqual(self.request("POST", "/api/action", change, headers)[0], 403)
        self.assertEqual(self.request("GET", "/api/session", headers={"Origin": "https://example.com"})[0], 403)
        for path in ("/../store.py", "/%2e%2e/store.py", "/board.json", "/api/unknown"):
            self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.server.store.read()["revision"], 0)

    def test_bad_requests_do_not_change_saved_data(self):
        self.mutate("add", {"title": "Keep this"}, 0)
        for action, payload, revision in (("add", {"title": ""}, 1), ([], {}, 1),
                                          ("add", [], 1), ("add", {"title": "Bad revision"}, True)):
            self.assertEqual(self.mutate(action, payload, revision)[0], 400)
        self.assertEqual(self.request("POST", "/api/action", {"unknown": True})[0], 400)
        self.assertEqual(self.request("POST", "/api/action", {}, {"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.server.store.read()["revision"], 1)

    def test_two_clients_cannot_overwrite_each_other(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda title: self.mutate("add", {"title": title}, 0), ("A", "B")))
        self.assertEqual(sorted(status for status, _ in responses), [200, 409])
        self.assertEqual(len(self.server.store.read()["items"]), 1)

    def test_corrupt_store_can_recover_through_http(self):
        self.mutate("add", {"title": "Backup survives"}, 0)
        self.mutate("add", {"title": "Later change"}, 1)
        (self.data / "board.json").write_text("broken", encoding="utf-8")
        self.assertEqual(self.request("GET", "/api/board")[0], 500)
        self.assertEqual(self.request("GET", "/api/session")[0], 200)
        status, repaired = self.mutate("recover", {}, -1)
        self.assertEqual(status, 200)
        self.assertEqual([item["title"] for item in repaired["board"]["items"]], ["Backup survives"])

    def test_cli_and_http_use_the_same_revision(self):
        def cli(*args):
            result = subprocess.run([sys.executable, str(ROOT / "board.py"), "--data-dir", str(self.data), *args],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        first = cli("add", "--title", "Added by a task")
        identifier = first["selection"]["item"]["id"]
        self.assertEqual(self.mutate("edit", {"id": identifier, "notes": "Edited in browser"}, 1)[0], 200)
        self.assertEqual(cli("list")["board"]["items"][0]["notes"], "Edited in browser")
        self.assertEqual(cli("claim", "--owner", "task-reference")["selection"]["kind"], "active")

    def test_reuse_ignores_unrelated_service_on_stale_port(self):
        self.data.mkdir(parents=True, exist_ok=True)
        (self.data / "server.json").write_text(json.dumps({"port": 12345}), encoding="utf-8")
        with patch("board.build_opener") as opener:
            opener.return_value.open.return_value.__enter__.return_value.read.return_value = b"[]"
            self.assertIsNone(serving_info(self.data))

    def test_cli_parallel_claims_are_readable_and_owned_through_http(self):
        def cli(*args, expected=0):
            result = subprocess.run([sys.executable, str(ROOT / "board.py"), "--data-dir", str(self.data), *args],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, expected, result.stderr)
            return json.loads(result.stdout if expected == 0 else result.stderr)
        a = cli("add", "--title", "A")["board"]["items"][-1]["id"]
        b = cli("add", "--title", "B")["board"]["items"][-1]["id"]
        cli("claim", "--owner", "task-one", "--id", a)
        self.assertEqual(cli("claim", "--owner", "task-two", "--parallel", expected=1)["status"], 400)
        self.assertEqual(cli("claim", "--owner", "task-two", "--id", b, expected=1)["status"], 409)
        claimed = cli("claim", "--owner", "task-two", "--id", b, "--parallel")
        status, _, content = self.request("GET", "/api/board")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(content), claimed)
        self.assertEqual(["task-one", "task-two"], [item["owner"] for item in claimed["board"]["items"]])
        self.assertEqual(self.request("GET", "/api/export")[0], 200)
        status, released = self.mutate("status", {"id": b, "status": "queued", "user_override": True},
                                       claimed["board"]["revision"])
        self.assertEqual(status, 200)
        self.assertEqual(["task-one", ""], [item["owner"] for item in released["board"]["items"]])

    def test_running_server_survives_removed_source_worktree(self):
        with patch("board.ROOT", Path(self.temp.name) / "removed worktree"):
            for path in ("/", "/app.css", "/app.js"):
                self.assertEqual(self.request("GET", path)[0], 200)


@unittest.skipUnless(os.name == "nt", "Windows launcher integration")
class LauncherTests(unittest.TestCase):
    def test_windows_launcher_reuses_server_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix="feedback launch test ") as temporary:
            project = Path(temporary) / "project with spaces"
            copied = project / "tools" / "feedback-board"
            shutil.copytree(ROOT, copied, ignore=shutil.ignore_patterns("__pycache__"))
            data = project / ".feedback"
            info = None
            try:
                command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                           str(copied / "start.ps1"), "-PythonPath", sys.executable, "-NoBrowser"]
                first = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(first.returncode, 0, first.stderr)
                info = json.loads(first.stdout)
                second = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(json.loads(second.stdout), info)
                self.assertEqual(serving_info(data), info)
            finally:
                # This directory/server is created by this test; do not stop any other process.
                owned = serving_info(data)
                if owned:
                    os.kill(owned["pid"], signal.SIGTERM)
                    # Windows process termination may return before handles close.
                    with process_lock(data / "server.lock"):
                        pass


if __name__ == "__main__":
    unittest.main()
