"""Shared, revisioned storage for the local game feedback board.

Both the browser server and command line use this module. No game saves or
network services are involved. Callers must supply the revision they observed.
"""

from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time
from typing import Any
from urllib.parse import urlsplit
import uuid


SCHEMA_VERSION = 1
MAX_BYTES = 10 * 1024 * 1024
MAX_ITEMS = 2000
STATUSES = {"queued", "blocked", "in_progress", "awaiting_playtest", "done", "archived"}
TEXT_LIMITS = {"title": 300, "notes": 20000, "build_id": 200, "source_link": 2000,
               "blocked_reason": 2000, "owner": 300}
ITEM_FIELDS = {"id", "title", "notes", "build_id", "source_link", "status",
               "blocked_reason", "owner", "created_at", "updated_at"}
TRANSITIONS = {
    "queued": {"blocked", "archived"},
    "blocked": {"queued", "archived"},
    "in_progress": {"queued", "blocked", "awaiting_playtest", "archived"},
    "awaiting_playtest": {"done", "queued", "archived"},
    "done": {"queued", "archived"},
    "archived": {"queued"},
}
_THREAD_LOCKS: dict[str, threading.RLock] = {}
_THREAD_LOCKS_GUARD = threading.Lock()


class StoreError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


def resolve_data_dir(project: Path) -> Path:
    """Find the primary checkout, including when launched in a linked worktree."""
    project = Path(project).resolve()
    if not project.is_dir():
        raise StoreError("The project directory does not exist.")
    # Trust only the explicitly selected local checkout, not every git repository.
    checkout = next((p for p in (project, *project.parents) if (p / ".git").exists()), None)
    if checkout is None:
        return project / ".feedback"
    try:
        result = subprocess.run(
            ["git", "-c", f"safe.directory={checkout.as_posix()}", "-C", str(checkout),
             "worktree", "list", "--porcelain", "-z"],
            capture_output=True, check=True, timeout=15,
        )
        records = result.stdout.decode("utf-8").split("\0")
        first = next(record[9:] for record in records if record.startswith("worktree "))
        primary = Path(first).resolve()
        if not primary.is_dir():
            raise StoreError("The primary checkout is unavailable; reconnect it before using feedback.", 500)
        return primary / ".feedback"
    except StoreError:
        raise
    except (OSError, subprocess.SubprocessError, UnicodeError, StopIteration) as exc:
        raise StoreError("Cannot locate the primary checkout; no separate feedback store was created.", 500) from exc


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _text(value: Any, name: str, required: bool = False) -> str:
    if not isinstance(value, str) or len(value) > TEXT_LIMITS[name] or "\x00" in value:
        raise StoreError(f"{name} must be text of at most {TEXT_LIMITS[name]} characters without null bytes.")
    if required and not value.strip():
        raise StoreError(f"{name} is required.")
    if name == "source_link" and value:
        try:
            parsed = urlsplit(value)
            valid = (parsed.scheme.lower() in {"http", "https"} and bool(parsed.hostname)
                     and not parsed.username and not parsed.password
                     and not any(c.isspace() or ord(c) < 32 for c in value))
            _ = parsed.port  # Reject invalid/out-of-range ports as well.
        except ValueError:
            valid = False
        if not valid:
            raise StoreError("source_link must be an HTTP or HTTPS URL without credentials.")
    return value


def _timestamp(value: Any) -> None:
    try:
        if not isinstance(value, str) or len(value) > 50:
            raise ValueError()
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError()
    except ValueError as exc:
        raise StoreError("Item timestamps must be ISO 8601 dates with a timezone.") from exc


def validate_board(board: Any) -> dict:
    """Validate the complete persisted/imported schema without coercing values."""
    if not isinstance(board, dict) or set(board) != {"schema_version", "revision", "items"}:
        raise StoreError("Board must contain schema_version, revision, and items.")
    if type(board["schema_version"]) is not int or board["schema_version"] != SCHEMA_VERSION:
        raise StoreError("Unsupported board schema version.")
    if type(board["revision"]) is not int or not 0 <= board["revision"] <= 2**53 - 2:
        raise StoreError("Board revision must be a nonnegative safe integer.")
    if not isinstance(board["items"], list) or len(board["items"]) > MAX_ITEMS:
        raise StoreError(f"Board must have an items list with at most {MAX_ITEMS} items.")
    ids = set()
    active_owners = set()
    for item in board["items"]:
        if not isinstance(item, dict) or set(item) != ITEM_FIELDS:
            raise StoreError("Every item must contain exactly the documented item fields.")
        identifier = item["id"]
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", identifier):
            raise StoreError("Item ID must be 1–80 letters, digits, hyphens, or underscores.")
        if identifier in ids:
            raise StoreError("Item IDs must be unique.")
        ids.add(identifier)
        for field in TEXT_LIMITS:
            _text(item[field], field, field == "title")
        status = item["status"]
        if not isinstance(status, str) or status not in STATUSES:
            raise StoreError("Unknown item status.")
        if status == "blocked" and not item["blocked_reason"].strip():
            raise StoreError("Blocked items require a reason.")
        if status != "blocked" and item["blocked_reason"]:
            raise StoreError("Only blocked items can have a blocked reason.")
        if status == "in_progress":
            _text(item["owner"], "owner", True)
            if item["owner"] in active_owners:
                raise StoreError("Each task can own only one development claim.")
            active_owners.add(item["owner"])
        elif item["owner"]:
            raise StoreError("Only an in-progress item can have a claim owner.")
        for field in ("created_at", "updated_at"):
            _timestamp(item[field])
    try:
        encoded = json.dumps(board, ensure_ascii=False).encode("utf-8")
    except (ValueError, UnicodeError) as exc:
        raise StoreError("Board contains invalid text.") from exc
    if len(encoded) > MAX_BYTES:
        raise StoreError("Board exceeds the 10 MiB storage limit.")
    return board


def select_next(board: dict) -> dict:
    for item in board["items"]:
        if item["status"] == "in_progress":
            return {"kind": "active", "item": deepcopy(item)}
    for item in board["items"]:
        if item["status"] == "queued":
            return {"kind": "next", "item": deepcopy(item)}
    return {"kind": "blocked" if any(i["status"] == "blocked" for i in board["items"]) else "empty",
            "item": None}


def _json_object(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property.")
        result[key] = value
    return result


class Store:
    def __init__(self, data_dir: Path):
        self.data_dir = Path(data_dir).resolve()
        self.path = self.data_dir / "board.json"
        self.backup_path = self.data_dir / "board.backup.json"
        self.revision_path = self.data_dir / "revision.json"
        with _THREAD_LOCKS_GUARD:
            self._thread_lock = _THREAD_LOCKS.setdefault(os.path.normcase(str(self.data_dir)), threading.RLock())

    @contextmanager
    def _locked(self):
        with self._thread_lock:
            try:
                self.data_dir.mkdir(parents=True, exist_ok=True)
                (self.data_dir / ".gdignore").touch(exist_ok=True)
                with (self.data_dir / "board.lock").open("a+b") as lock_file:
                    if lock_file.seek(0, os.SEEK_END) == 0:
                        lock_file.write(b"\0")
                        lock_file.flush()
                    deadline = time.monotonic() + 10
                    while True:
                        try:
                            lock_file.seek(0)
                            if os.name == "nt":
                                import msvcrt
                                msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
                            else:
                                import fcntl
                                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                            break
                        except OSError as exc:
                            if time.monotonic() >= deadline:
                                raise StoreError("Feedback is busy in another process; retry shortly.", 409) from exc
                            time.sleep(0.025)
                    try:
                        yield
                    finally:
                        lock_file.seek(0)
                        if os.name == "nt":
                            import msvcrt
                            msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
                        else:
                            import fcntl
                            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            except StoreError:
                raise
            except OSError as exc:
                raise StoreError(f"Cannot access feedback storage: {exc}", 500) from exc

    def _load(self, path: Path) -> dict:
        try:
            with path.open("rb") as stream:
                data = stream.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise StoreError("Board exceeds the 10 MiB storage limit.")
            return validate_board(json.loads(data.decode("utf-8"), object_pairs_hook=_json_object))
        except (OSError, ValueError, UnicodeError, StoreError) as exc:
            raise StoreError(f"Cannot read {path.name}: {exc}. Restore a JSON export or recover the backup.", 500) from exc

    def _atomic_write(self, path: Path, board: dict) -> None:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                             prefix=".board-", suffix=".tmp", dir=self.data_dir,
                                             delete=False) as stream:
                temporary = Path(stream.name)
                json.dump(board, stream, ensure_ascii=False, separators=(",", ":"))
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
        except (OSError, ValueError, UnicodeError) as exc:
            raise StoreError(f"Cannot save feedback; the previous file was kept: {exc}", 500) from exc
        finally:
            if temporary is not None:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    pass

    def _read_unlocked(self) -> dict:
        if not self.path.exists():
            if self.backup_path.exists() or self.revision_path.exists():
                raise StoreError("board.json is missing from an existing store. Recover the backup or restore an export.", 500)
            initial = {"schema_version": SCHEMA_VERSION, "revision": 0, "items": []}
            self._atomic_write(self.revision_path, {"revision": 0})
            self._atomic_write(self.path, initial)
            return initial
        board = self._load(self.path)
        # Upgrade an existing/exported local board without changing its revision.
        if not self.revision_path.exists():
            self._atomic_write(self.revision_path, {"revision": board["revision"]})
        return board

    def read(self) -> dict:
        with self._locked():
            return self._read_unlocked()

    def mutate(self, action: str, payload: dict, expected_revision: int) -> dict:
        if not isinstance(action, str):
            raise StoreError("Mutation action must be text.")
        if not isinstance(payload, dict) or any(not isinstance(key, str) for key in payload):
            raise StoreError("Mutation payload must be an object.")
        if type(expected_revision) is not int or expected_revision < -1:
            raise StoreError("An integer expected_revision is required.")
        with self._locked():
            try:
                current = self._read_unlocked()
            except StoreError:
                if action not in {"recover", "restore"} or expected_revision != -1:
                    raise
                current = None
            if current is not None and expected_revision != current["revision"]:
                raise StoreError("Feedback changed since it was loaded. Reload before retrying; nothing was overwritten.", 409)
            if action == "recover":
                self._fields(payload, set())
                replacement = deepcopy(self._load(self.backup_path))
                replacement["revision"] = self._next_revision(current, replacement)
                validate_board(replacement)
                self._atomic_write(self.revision_path, {"revision": replacement["revision"]})
                # Keep an undo copy when the primary is valid; never back up corrupt data.
                if current is None:
                    self._preserve_corrupt()
                else:
                    self._atomic_write(self.backup_path, current)
                self._atomic_write(self.path, replacement)
                return replacement
            if action == "restore":
                self._fields(payload, {"board"})
                replacement = deepcopy(validate_board(payload.get("board")))
            else:
                if current is None:
                    raise StoreError("Recover the board before editing.", 500)
                replacement = deepcopy(current)
                self._apply(replacement, action, payload)
                if replacement == current:
                    return current
            replacement["revision"] = self._next_revision(current)
            validate_board(replacement)
            # Reserve before touching the primary, even if a later save fails. This
            # prevents a pre-recovery browser revision matching the repaired board.
            self._atomic_write(self.revision_path, {"revision": replacement["revision"]})
            if current is not None:
                self._atomic_write(self.backup_path, current)
            else:
                self._preserve_corrupt()
            self._atomic_write(self.path, replacement)
            return replacement

    def _next_revision(self, current: dict | None, recovery: dict | None = None) -> int:
        floor = current["revision"] if current else -1
        if recovery is not None:
            floor = max(floor, recovery["revision"])
        if self.revision_path.exists():
            try:
                with self.revision_path.open("rb") as stream:
                    fence = json.loads(stream.read(4096).decode("utf-8"), object_pairs_hook=_json_object)
                if (not isinstance(fence, dict) or set(fence) != {"revision"}
                        or type(fence["revision"]) is not int or not 0 <= fence["revision"] <= 2**53 - 2):
                    raise ValueError("Invalid revision fence")
                floor = max(floor, fence["revision"])
            except (OSError, ValueError, UnicodeError) as exc:
                raise StoreError("Cannot read revision.json; preserve and repair this revision file before editing.", 500) from exc
        elif current is None:
            # A manually removed fence cannot provide an exact high-water mark.
            # Use a time-based revision above normal counters and the last backup.
            floor = max(floor + 1, time.time_ns() // 1_000_000)
            if self.backup_path.exists():
                try:
                    floor = max(floor, self._load(self.backup_path)["revision"] + 1)
                except StoreError:
                    pass
        return floor + 1

    def _preserve_corrupt(self) -> None:
        if self.path.exists():
            suffix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8]
            try:
                shutil.copyfile(self.path, self.data_dir / f"board.corrupt-{suffix}.json")
            except OSError as exc:
                raise StoreError("Cannot preserve the damaged board; recovery was not applied.", 500) from exc

    @staticmethod
    def _fields(payload: dict, allowed: set) -> None:
        if set(payload) - allowed:
            raise StoreError("Unexpected mutation fields: " + ", ".join(sorted(set(payload) - allowed)))

    @staticmethod
    def _item(board: dict, identifier: Any) -> dict:
        if not isinstance(identifier, str):
            raise StoreError("An item id is required.")
        for item in board["items"]:
            if item["id"] == identifier:
                return item
        raise StoreError("Feedback item does not exist.", 404)

    def _apply(self, board: dict, action: str, payload: dict) -> None:
        if action == "add":
            self._fields(payload, {"title", "notes", "build_id", "source_link"})
            now = _now()
            item = {field: _text(payload.get(field, ""), field, field == "title")
                    for field in ("title", "notes", "build_id", "source_link")}
            item.update(id="FB-" + uuid.uuid4().hex[:16], status="queued", blocked_reason="", owner="",
                        created_at=now, updated_at=now)
            board["items"].append(item)
        elif action == "edit":
            self._fields(payload, {"id", "title", "notes", "build_id", "source_link"})
            item = self._item(board, payload.get("id"))
            for field in ("title", "notes", "build_id", "source_link"):
                if field in payload:
                    item[field] = _text(payload[field], field, field == "title")
            item["updated_at"] = _now()
        elif action == "reorder":
            self._fields(payload, {"ids"})
            ordered = payload.get("ids")
            positions = [n for n, item in enumerate(board["items"]) if item["status"] in {"queued", "blocked"}]
            pool = {board["items"][n]["id"]: board["items"][n] for n in positions}
            if (not isinstance(ordered, list) or any(not isinstance(i, str) for i in ordered)
                    or len(ordered) != len(pool) or set(ordered) != set(pool)):
                raise StoreError("Reorder must list every queued and blocked item exactly once.")
            for n, identifier in zip(positions, ordered):
                board["items"][n] = pool[identifier]
        elif action == "claim":
            self._fields(payload, {"owner", "id", "parallel"})
            owner = _text(payload.get("owner"), "owner", True)
            parallel = payload.get("parallel", False)
            if type(parallel) is not bool:
                raise StoreError("parallel must be a boolean.")
            if parallel and not payload.get("id"):
                raise StoreError("Parallel development requires an explicit item ID.")
            existing = next((item for item in board["items"]
                             if item["status"] == "in_progress" and item["owner"] == owner), None)
            if existing is not None:
                if payload.get("id") and payload["id"] != existing["id"]:
                    raise StoreError("Continue your existing claim before selecting another item.", 409)
                return
            selected = select_next(board)
            if selected["kind"] == "active" and not parallel:
                raise StoreError(f"Work is already claimed by {selected['item']['owner']}.", 409)
            item = self._item(board, payload["id"]) if "id" in payload else None
            if item is None:
                if selected["kind"] == "empty":
                    raise StoreError("The feedback queue is empty.", 409)
                if selected["kind"] == "blocked":
                    raise StoreError("Every remaining feedback item is blocked.", 409)
                item = self._item(board, selected["item"]["id"])
            if item["status"] == "in_progress":
                raise StoreError(f"Work is already claimed by {item['owner']}.", 409)
            if item["status"] != "queued":
                raise StoreError("Only a queued item can be claimed. Unblock or reopen it first.", 409)
            item.update(status="in_progress", owner=owner, updated_at=_now())
        elif action == "status":
            self._fields(payload, {"id", "status", "blocked_reason", "owner", "user_override"})
            item = self._item(board, payload.get("id"))
            new_status = payload.get("status")
            override = payload.get("user_override", False)
            if type(override) is not bool:
                raise StoreError("user_override must be a boolean.")
            if not isinstance(new_status, str) or new_status not in STATUSES or new_status == "in_progress":
                raise StoreError("Choose a valid destination status; use claim to begin development.")
            old_status = item["status"]
            if new_status != old_status and new_status not in TRANSITIONS[old_status]:
                raise StoreError(f"Cannot move {old_status} feedback directly to {new_status}.")
            if old_status == "in_progress" and not override and payload.get("owner") != item["owner"]:
                raise StoreError("Only the owning task can change this claim; a user can explicitly release it.", 409)
            reason = _text(payload.get("blocked_reason", item["blocked_reason"]), "blocked_reason", True) if new_status == "blocked" else ""
            item.update(status=new_status, owner="", blocked_reason=reason, updated_at=_now())
            if new_status == "queued" and old_status in {"awaiting_playtest", "done", "archived"}:
                board["items"].remove(item)
                board["items"].append(item)
        else:
            raise StoreError("Unknown feedback action.")
