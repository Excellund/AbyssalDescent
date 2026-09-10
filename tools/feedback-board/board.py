"""Local feedback board HTTP service, launcher and agent command line."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import ProxyHandler, build_opener
import webbrowser

from store import MAX_BYTES, Store, StoreError, resolve_data_dir, select_next


ROOT = Path(__file__).resolve().parent
MAX_BODY = MAX_BYTES * 2
ASSETS = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.css": ("app.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
}


def envelope(board):
    return {"board": board, "selection": select_next(board)}


def project_key(data_dir):
    return hashlib.sha256(os.path.normcase(str(Path(data_dir).resolve())).encode()).hexdigest()


@contextmanager
def process_lock(path, *, wait=True):
    """OS-owned lock; a terminated process cannot leave a stale lock behind."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\0")
            handle.flush()
        deadline = time.monotonic() + (20 if wait else 0)
        while True:
            try:
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise StoreError("The feedback board is already starting or running.", 409)
                time.sleep(0.05)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_UN)


class BoardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, data_dir, port=0):
        self.data_dir = Path(data_dir).resolve()
        self.store = Store(self.data_dir)
        self.token = secrets.token_urlsafe(32)
        self.key = project_key(self.data_dir)
        # Keep the running board usable if its launching worktree is removed.
        self.asset_fallback = {name: (ROOT / "static" / name).read_bytes() for name, _ in ASSETS.values()}
        super().__init__(("127.0.0.1", port), BoardHandler)
        self.origin = f"http://127.0.0.1:{self.server_port}"


class BoardHandler(BaseHTTPRequestHandler):
    server_version = "FeedbackBoard/1"

    def log_message(self, fmt, *args):
        # Do not put user-supplied URLs/content in the service log.
        pass

    def reply(self, status, body, content_type="application/json; charset=utf-8", filename=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        if filename:
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.end_headers()
        self.wfile.write(body)

    def guarded(self, mutation=False):
        if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
            raise StoreError("Use the board's local address.", 403)
        origin = self.headers.get("Origin")
        if origin and origin != self.server.origin:
            raise StoreError("This request is not from the feedback board.", 403)
        if self.headers.get("Sec-Fetch-Site") == "cross-site":
            raise StoreError("Cross-site requests are not allowed.", 403)
        if mutation:
            token = self.headers.get("X-Feedback-Token", "")
            if not secrets.compare_digest(token, self.server.token):
                raise StoreError("Reload the board before saving this change.", 403)

    def do_GET(self):
        try:
            self.guarded()
            if self.path in ASSETS:
                name, content_type = ASSETS[self.path]
                try:
                    content = (ROOT / "static" / name).read_bytes()
                except FileNotFoundError:
                    content = self.server.asset_fallback[name]
                self.reply(200, content, content_type)
            elif self.path == "/api/session":
                self.reply(200, {"token": self.server.token})
            elif self.path == "/api/health":
                self.reply(200, {"app": "abyssal-feedback-board", "project": self.server.key, "pid": os.getpid()})
            elif self.path == "/api/board":
                self.reply(200, envelope(self.server.store.read()))
            elif self.path == "/api/export":
                self.reply(200, self.server.store.read(), filename="abyssal-feedback.json")
            elif self.path == "/api/backup":
                path = self.server.data_dir / "board.backup.json"
                if not path.is_file():
                    raise StoreError("No recovery backup is available yet.", 404)
                self.reply(200, path.read_bytes(), filename="abyssal-feedback-backup.json")
            else:
                raise StoreError("Not found.", 404)
        except StoreError as exc:
            self.reply(exc.status, {"error": str(exc)})
        except OSError:
            self.reply(500, {"error": "The board could not read its files. Check access and try again."})

    def do_POST(self):
        try:
            self.guarded(mutation=True)
            if self.path != "/api/action":
                raise StoreError("Not found.", 404)
            if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
                raise StoreError("Send feedback changes as JSON.", 415)
            if self.headers.get("Transfer-Encoding"):
                raise StoreError("Chunked requests are not supported.", 400)
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise StoreError("Invalid request size.", 400)
            if not 0 < size <= MAX_BODY:
                raise StoreError("The request is empty or exceeds 20 MiB.", 413)
            self.connection.settimeout(10)
            try:
                request = json.loads(self.rfile.read(size))
            except (ValueError, UnicodeError):
                raise StoreError("The request is not valid JSON.", 400)
            if not isinstance(request, dict) or set(request) != {"revision", "action", "payload"}:
                raise StoreError("A change needs revision, action and payload.", 400)
            board = self.server.store.mutate(request["action"], request["payload"], request["revision"])
            self.reply(200, envelope(board))
        except StoreError as exc:
            self.reply(exc.status, {"error": str(exc)})
        except OSError:
            self.reply(500, {"error": "The change could not be saved. Your previous feedback is retained; try again."})


def serving_info(data_dir):
    """Only reuse our server for this exact canonical data directory."""
    try:
        info = json.loads((data_dir / "server.json").read_text(encoding="utf-8"))
        port = info["port"]
        if type(port) is not int or not 0 < port < 65536:
            return None
        url = f"http://127.0.0.1:{port}"
        opener = build_opener(ProxyHandler({}))
        with opener.open(url + "/api/health", timeout=1) as response:
            health = json.load(response)
        if (isinstance(health, dict) and health.get("app") == "abyssal-feedback-board"
                and health.get("project") == project_key(data_dir) and type(health.get("pid")) is int):
            return {"url": url, "pid": health["pid"]}
    except (OSError, ValueError, KeyError, TypeError, URLError):
        pass
    return None


def serve(data_dir, port):
    with process_lock(data_dir / "server.lock", wait=False):
        with BoardServer(data_dir, port) as server:
            info_path = data_dir / "server.json"
            temporary = data_dir / "server.json.tmp"
            temporary.write_text(json.dumps({"port": server.server_port, "pid": os.getpid()}), encoding="utf-8")
            os.replace(temporary, info_path)
            print(json.dumps({"url": server.origin, "pid": os.getpid()}), flush=True)
            try:
                server.serve_forever(poll_interval=0.25)
            except KeyboardInterrupt:
                pass
            finally:
                info_path.unlink(missing_ok=True)


def launch(data_dir, port=0, no_browser=False):
    with process_lock(data_dir / "launch.lock"):
        info = serving_info(data_dir)
        if info is None:
            command = [sys.executable, str(ROOT / "board.py"), "--data-dir", str(data_dir), "serve", "--port", str(port)]
            options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
            with (data_dir / "server.log").open("ab") as log:
                child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, cwd=str(ROOT), **options)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                info = serving_info(data_dir)
                if info:
                    break
                if child.poll() is not None:
                    raise StoreError(f"The board could not start. See {data_dir / 'server.log'}.", 500)
                time.sleep(0.1)
            if info is None:
                child.terminate()
                child.wait(timeout=5)
                raise StoreError("The feedback board did not become ready in time.", 500)
    if not no_browser:
        webbrowser.open(info["url"])
    return info


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--project", type=Path, default=ROOT.parent.parent)
    result.add_argument("--data-dir", type=Path, help="Explicit isolated data directory for tests")
    sub = result.add_subparsers(dest="command", required=True)
    for name in ("list", "next"):
        sub.add_parser(name)
    for name in ("add", "edit"):
        command = sub.add_parser(name)
        if name == "edit":
            command.add_argument("id")
        command.add_argument("--title", required=name == "add")
        for field in ("notes", "build-id", "source-link"):
            command.add_argument("--" + field)
        command.add_argument("--revision", type=int)
    claim = sub.add_parser("claim")
    claim.add_argument("--owner", required=True)
    claim.add_argument("--id", help="Explicit user-selected queued item; does not reorder the queue")
    claim.add_argument("--parallel", action="store_true",
                       help="Allow another task's active claim only for user-requested parallel work; requires --id")
    claim.add_argument("--revision", type=int)
    status = sub.add_parser("status")
    status.add_argument("id")
    status.add_argument("status", choices=["queued", "blocked", "awaiting_playtest", "done", "archived"])
    status.add_argument("--reason", default="")
    status.add_argument("--owner", default="")
    status.add_argument("--user-override", action="store_true")
    status.add_argument("--revision", type=int)
    order = sub.add_parser("reorder")
    order.add_argument("ids", nargs="+")
    order.add_argument("--user-ordered", action="store_true", required=True)
    order.add_argument("--revision", type=int)
    export = sub.add_parser("export")
    export.add_argument("--output", type=Path)
    restore = sub.add_parser("restore")
    restore.add_argument("file", type=Path)
    restore.add_argument("--revision", type=int)
    recover = sub.add_parser("recover")
    recover.add_argument("--revision", type=int, required=True)
    recover.add_argument("--yes", action="store_true", required=True)
    for name in ("serve", "launch"):
        command = sub.add_parser(name)
        command.add_argument("--port", type=int, default=0)
        if name == "launch":
            command.add_argument("--no-browser", action="store_true")
    return result


def run(args):
    data_dir = args.data_dir.resolve() if args.data_dir else resolve_data_dir(args.project)
    if args.command == "serve":
        serve(data_dir, args.port)
        return None
    if args.command == "launch":
        return launch(data_dir, args.port, args.no_browser)
    store = Store(data_dir)
    if args.command == "list":
        return envelope(store.read())
    if args.command == "next":
        return select_next(store.read())
    if args.command == "export":
        board = store.read()
        if args.output:
            with args.output.open("x", encoding="utf-8") as output:
                json.dump(board, output, ensure_ascii=False, indent=2)
                output.write("\n")
            return {"exported": str(args.output.resolve())}
        return board
    payload = {}
    if args.command in ("add", "edit"):
        payload = {key: getattr(args, key) for key in ("title", "notes", "build_id", "source_link") if getattr(args, key) is not None}
        if args.command == "edit":
            payload["id"] = args.id
    elif args.command == "claim":
        payload = {"owner": args.owner}
        if args.id:
            payload["id"] = args.id
        if args.parallel:
            payload["parallel"] = True
    elif args.command == "status":
        payload = {"id": args.id, "status": args.status, "blocked_reason": args.reason, "owner": args.owner, "user_override": args.user_override}
    elif args.command == "reorder":
        payload = {"ids": args.ids}
    elif args.command == "restore":
        payload = {"board": json.loads(args.file.read_text(encoding="utf-8-sig"))}
    revision = args.revision if args.revision is not None else store.read()["revision"]
    return envelope(store.mutate(args.command, payload, revision))


def main():
    try:
        output = run(parser().parse_args())
        if output is not None:
            # ASCII escapes keep the CLI usable under the Windows console code page.
            print(json.dumps(output, indent=2))
        return 0
    except (StoreError, OSError, ValueError) as exc:
        print(json.dumps({"error": str(exc), "status": getattr(exc, "status", 500)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
