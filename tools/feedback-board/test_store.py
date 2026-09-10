"""Focused storage tests. Every write is isolated in a temporary directory."""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from store import Store, StoreError, resolve_data_dir, select_next


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="feedback store tests ")
        self.addCleanup(self.temp.cleanup)
        self.store = Store(Path(self.temp.name) / ".feedback")
        self.board = self.store.read()

    def change(self, action, **payload):
        self.board = self.store.mutate(action, payload, self.board["revision"])
        return self.board

    def add(self, title):
        return self.change("add", title=title)["items"][-1]["id"]

    def expect_error(self, status, action, payload, revision=None):
        before = self.store.path.read_bytes()
        with self.assertRaises(StoreError) as caught:
            self.store.mutate(action, payload, self.board["revision"] if revision is None else revision)
        self.assertEqual(status, caught.exception.status, caught.exception)
        self.assertEqual(before, self.store.path.read_bytes())
        return caught.exception

    def test_empty_board_and_restart(self):
        self.assertEqual({"schema_version": 1, "revision": 0, "items": []}, self.board)
        self.assertEqual({"kind": "empty", "item": None}, select_next(self.board))
        self.assertTrue((self.store.data_dir / ".gdignore").is_file())
        self.assertEqual(self.board, Store(self.store.data_dir).read())
        self.expect_error(409, "claim", {"owner": "task-1"})

    def test_append_edit_order_restart_and_backup(self):
        first = self.add("First")
        self.add("Second")
        prior = deepcopy(self.board)
        self.change("edit", id=first, notes="Two lines\nAnother line", build_id="dev-123",
                    source_link="https://example.test/feedback?q=hello")
        self.assertEqual(["First", "Second"], [i["title"] for i in self.board["items"]])
        self.assertEqual(first, self.board["items"][0]["id"])
        self.assertEqual(prior, json.loads(self.store.backup_path.read_text(encoding="utf-8")))
        self.assertEqual(self.board, Store(self.store.data_dir).read())

    def test_reorder_preserves_nonqueue_positions_and_blocked_priority(self):
        a, b, c, d = [self.add(t) for t in "ABCD"]
        self.change("status", id=b, status="blocked", blocked_reason="Needs reproduction")
        self.change("claim", owner="task-one", id=c)
        self.change("reorder", ids=[d, b, a])
        self.assertEqual([d, b, c, a], [i["id"] for i in self.board["items"]])
        self.assertEqual("active", select_next(self.board)["kind"])
        self.change("status", id=c, status="awaiting_playtest", owner="task-one")
        self.assertEqual(d, select_next(self.board)["item"]["id"])
        self.expect_error(400, "reorder", {"ids": [a, a, b]})
        self.expect_error(400, "reorder", {"ids": [d, a]})
        self.expect_error(400, "reorder", {"ids": [d, b, c, a]})

    def test_blocked_items_keep_position_and_all_blocked_reported(self):
        a, b = self.add("A"), self.add("B")
        self.change("status", id=a, status="blocked", blocked_reason="Needs input")
        self.assertEqual(b, select_next(self.board)["item"]["id"])
        self.change("status", id=b, status="blocked", blocked_reason="Needs asset")
        self.assertEqual({"kind": "blocked", "item": None}, select_next(self.board))
        self.assertIn("blocked", str(self.expect_error(409, "claim", {"owner": "task"})))
        self.change("status", id=a, status="queued")
        self.assertEqual([a, b], [i["id"] for i in self.board["items"]])
        self.assertEqual(a, select_next(self.board)["item"]["id"])
        self.assertEqual("", self.board["items"][0]["blocked_reason"])

    def test_claim_resume_exclusivity_and_owner_release(self):
        a, b = self.add("A"), self.add("B")
        self.change("claim", owner="task-one")
        self.assertEqual(a, select_next(self.board)["item"]["id"])
        original = deepcopy(self.board)
        self.change("claim", owner="task-one")
        self.assertEqual(original, self.board)
        self.expect_error(409, "claim", {"owner": "task-two"})
        self.expect_error(409, "claim", {"owner": "task-one", "id": b})
        self.expect_error(409, "status", {"id": a, "status": "awaiting_playtest"})
        self.expect_error(409, "status", {"id": a, "status": "queued", "owner": "task-two"})
        self.change("status", id=a, status="awaiting_playtest", owner="task-one")
        self.change("claim", owner="task-two")
        self.assertEqual(b, select_next(self.board)["item"]["id"])
        self.change("status", id=b, status="queued", user_override=True)
        self.assertEqual("", self.board["items"][1]["owner"])

    def test_explicit_item_selection_does_not_reorder(self):
        a, b, c = [self.add(t) for t in "ABC"]
        self.change("claim", owner="explicit-task", id=c)
        self.assertEqual([a, b, c], [i["id"] for i in self.board["items"]])
        self.change("status", id=c, status="awaiting_playtest", owner="explicit-task")
        self.assertEqual(a, select_next(self.board)["item"]["id"])

    def test_parallel_claims_preserve_order_and_resume_each_owner(self):
        a, b, c = [self.add(t) for t in "ABC"]
        self.change("claim", owner="task-one", id=a)
        self.expect_error(409, "claim", {"owner": "task-two", "id": c})
        self.change("claim", owner="task-two", id=c, parallel=True)
        self.assertEqual([a, b, c], [item["id"] for item in self.board["items"]])
        self.assertEqual(["task-one", "", "task-two"], [item["owner"] for item in self.board["items"]])
        self.assertEqual(a, select_next(self.board)["item"]["id"])
        self.assertEqual(self.board, Store(self.store.data_dir).read())
        original = deepcopy(self.board)
        self.change("claim", owner="task-two")
        self.change("claim", owner="task-two", id=c, parallel=True)
        self.assertEqual(original, self.board)
        self.expect_error(409, "claim", {"owner": "task-three"})
        self.expect_error(409, "claim", {"owner": "task-three", "id": c, "parallel": True})
        self.expect_error(409, "claim", {"owner": "task-two", "id": b, "parallel": True})

    def test_parallel_claim_requires_explicit_queued_item(self):
        a, b = self.add("A"), self.add("B")
        self.change("claim", owner="task-one")
        self.expect_error(400, "claim", {"owner": "task-two", "parallel": True})
        self.expect_error(400, "claim", {"owner": "task-two", "parallel": True, "id": ""})
        self.expect_error(400, "claim", {"owner": "task-two", "parallel": "yes", "id": b})
        self.expect_error(404, "claim", {"owner": "task-two", "parallel": True, "id": "missing"})
        self.change("status", id=b, status="blocked", blocked_reason="Needs reproduction")
        self.expect_error(409, "claim", {"owner": "task-two", "parallel": True, "id": b})
        self.assertEqual(a, select_next(self.board)["item"]["id"])

    def test_parallel_status_and_reorder_affect_only_selected_claim(self):
        a, b, c, d = [self.add(t) for t in "ABCD"]
        self.change("claim", owner="task-one", id=a)
        self.change("claim", owner="task-two", id=c, parallel=True)
        self.change("reorder", ids=[d, b])
        self.assertEqual([a, d, c, b], [item["id"] for item in self.board["items"]])
        first_claim = deepcopy(self.board["items"][0])
        for status in ("queued", "blocked", "awaiting_playtest", "archived"):
            self.expect_error(409, "status", {"id": c, "status": status, "owner": "task-one",
                                               "blocked_reason": "Blocked for this test" if status == "blocked" else ""})
        self.change("status", id=c, status="awaiting_playtest", owner="task-two")
        self.assertEqual(first_claim, self.board["items"][0])
        self.assertEqual(a, select_next(self.board)["item"]["id"])
        self.change("claim", owner="task-three", id=b, parallel=True)
        self.change("status", id=b, status="archived", owner="task-three")
        self.assertEqual(first_claim, self.board["items"][0])
        self.change("status", id=a, status="awaiting_playtest", owner="task-one")
        self.assertEqual(d, select_next(self.board)["item"]["id"])

    def test_parallel_claim_race_rejects_stale_write_then_retries(self):
        a, b = self.add("A"), self.add("B")
        observed = self.board["revision"]
        def claim(pair):
            identifier, owner = pair
            try:
                self.store.mutate("claim", {"id": identifier, "owner": owner, "parallel": True}, observed)
                return identifier, owner, 200
            except StoreError as exc:
                return identifier, owner, exc.status
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(claim, ((a, "task-one"), (b, "task-two"))))
        self.assertEqual([200, 409], sorted(result[2] for result in results))
        self.board = self.store.read()
        identifier, owner, _ = next(result for result in results if result[2] == 409)
        self.change("claim", id=identifier, owner=owner, parallel=True)
        self.assertEqual(["task-one", "task-two"], [item["owner"] for item in self.board["items"]])

    def test_awaiting_done_archive_and_reopen_append(self):
        a, b = self.add("A"), self.add("B")
        self.change("claim", owner="task")
        self.change("status", id=a, status="awaiting_playtest", owner="task")
        self.change("status", id=a, status="done")
        self.change("status", id=a, status="queued")
        self.assertEqual([b, a], [i["id"] for i in self.board["items"]])
        self.change("status", id=b, status="archived")
        self.change("status", id=b, status="queued")
        self.assertEqual([a, b], [i["id"] for i in self.board["items"]])
        self.change("claim", owner="task")
        self.change("status", id=a, status="awaiting_playtest", owner="task")
        self.change("status", id=a, status="queued")
        self.assertEqual([b, a], [i["id"] for i in self.board["items"]])

    def test_input_validation_is_atomic(self):
        a = self.add("A")
        invalid = [
            ("add", {}), ("add", {"title": "  "}), ("add", {"title": "A" * 301}),
            ("add", {"title": "X", "notes": "\x00"}), ("add", {"title": 7}),
            ("add", {"title": "X", "owner": "task"}),
            ("edit", {"id": a, "source_link": "javascript:alert(1)"}),
            ("edit", {"id": a, "source_link": "https://user:pass@example.test"}),
            ("edit", {"id": a, "source_link": "https://example.test:99999"}),
            ("edit", {"id": a, "source_link": "https://example.test/\n"}),
            ("edit", {"id": a, "status": "done"}),
            ("status", {"id": a, "status": "in_progress"}),
            ("status", {"id": a, "status": "blocked"}),
            ("status", {"id": a, "status": "done"}),
            ("status", {"id": a, "status": "archived", "user_override": "yes"}),
            ("claim", {"owner": ""}), ("unknown", {}),
        ]
        for action, payload in invalid:
            with self.subTest(action=action, payload=payload):
                self.expect_error(400, action, payload)
        self.expect_error(404, "edit", {"id": "missing", "title": "X"})
        self.expect_error(400, "add", {"title": "X"}, revision=True)

    def test_stale_revisions_reject_without_lost_edits(self):
        observed = self.board["revision"]
        self.add("Browser edit")
        self.expect_error(409, "add", {"title": "Stale agent edit"}, revision=observed)
        self.assertEqual(["Browser edit"], [i["title"] for i in self.store.read()["items"]])
        self.expect_error(409, "restore", {"board": self.board}, revision=-1)

    def test_restore_uses_local_revision_and_backs_up_current(self):
        self.add("Original")
        exported = deepcopy(self.board)
        self.add("Later")
        current = deepcopy(self.board)
        exported["revision"] = 2000
        self.change("restore", board=exported)
        self.assertEqual(current["revision"] + 1, self.board["revision"])
        self.assertEqual(["Original"], [i["title"] for i in self.board["items"]])
        self.assertEqual(current, json.loads(self.store.backup_path.read_text(encoding="utf-8")))

    def test_invalid_import_does_not_change_current_or_backup(self):
        self.add("Original")
        valid = deepcopy(self.board)
        bad_boards = []
        duplicate = deepcopy(valid)
        duplicate["items"].append(deepcopy(duplicate["items"][0]))
        bad_boards.append(duplicate)
        for field, value in [("schema_version", True), ("schema_version", 2), ("revision", True),
                             ("revision", -1), ("items", {})]:
            malformed = deepcopy(valid)
            malformed[field] = value
            bad_boards.append(malformed)
        for field, value in [("status", "unknown"), ("created_at", "yesterday"),
                             ("updated_at", "2026-09-10T12:00:00"), ("owner", "orphan"),
                             ("blocked_reason", "orphan"), ("id", "bad/id")]:
            malformed = deepcopy(valid)
            malformed["items"][0][field] = value
            bad_boards.append(malformed)
        missing = deepcopy(valid)
        del missing["items"][0]["notes"]
        bad_boards.append(missing)
        two_active = deepcopy(valid)
        two_active["items"][0].update(status="in_progress", owner="task")
        second = deepcopy(two_active["items"][0])
        second["id"] = "FB-another"
        two_active["items"].append(second)
        bad_boards.append(two_active)
        backup = self.store.backup_path.read_bytes()
        for invalid in bad_boards:
            with self.subTest(board=invalid):
                self.expect_error(400, "restore", {"board": invalid})
                self.assertEqual(backup, self.store.backup_path.read_bytes())

    def test_failed_primary_replace_preserves_previous_board(self):
        self.add("Original")
        original_replace = os.replace

        def fail_primary(source, destination):
            if Path(destination) == self.store.path:
                raise OSError("simulated disk failure")
            original_replace(source, destination)

        with patch("store.os.replace", side_effect=fail_primary):
            self.expect_error(500, "add", {"title": "Unsaved"})
        self.assertEqual(self.board, self.store.read())
        self.assertEqual(self.board, json.loads(self.store.backup_path.read_text(encoding="utf-8")))
        self.assertEqual([], list(self.store.data_dir.glob(".board-*.tmp")))

    def test_failed_backup_save_does_not_touch_primary_or_backup(self):
        self.add("Original")
        backup = self.store.backup_path.read_bytes()
        with patch("store.os.fsync", side_effect=OSError("simulated full disk")):
            self.expect_error(500, "add", {"title": "Unsaved"})
        self.assertEqual(backup, self.store.backup_path.read_bytes())

    def test_failed_primary_write_reserves_revision_before_retry(self):
        self.add("Original")
        previous_revision = self.board["revision"]
        original_replace = os.replace

        def fail_primary(source, destination):
            if Path(destination) == self.store.path:
                raise OSError("simulated failed primary write")
            original_replace(source, destination)

        with patch("store.os.replace", side_effect=fail_primary):
            self.expect_error(500, "add", {"title": "Unsaved"})
        self.change("add", title="Retry")
        self.assertEqual(previous_revision + 2, self.board["revision"])
        self.assertEqual(["Original", "Retry"], [i["title"] for i in self.board["items"]])

    def test_corrupt_primary_recovery_retains_backup_and_corrupt_copy(self):
        self.add("Original")
        self.add("Later")
        backup = self.store.backup_path.read_bytes()
        self.store.path.write_bytes(b"{broken json")
        with self.assertRaises(StoreError) as caught:
            self.store.read()
        self.assertEqual(500, caught.exception.status)
        self.expect_error(500, "recover", {}, revision=self.board["revision"])
        restored = self.store.mutate("recover", {}, -1)
        self.assertEqual(["Original"], [i["title"] for i in restored["items"]])
        self.assertEqual(self.board["revision"] + 1, restored["revision"])
        self.assertEqual(backup, self.store.backup_path.read_bytes())
        corrupt = list(self.store.data_dir.glob("board.corrupt-*.json"))
        self.assertEqual(1, len(corrupt))
        self.assertEqual(b"{broken json", corrupt[0].read_bytes())
        self.expect_error(409, "add", {"title": "Stale browser"}, revision=self.board["revision"])

    def test_recover_valid_primary_uses_current_revision(self):
        self.add("Original")
        self.add("Later")
        revision = self.board["revision"]
        prior = deepcopy(self.board)
        self.change("recover")
        self.assertEqual(revision + 1, self.board["revision"])
        self.assertEqual(["Original"], [i["title"] for i in self.board["items"]])
        self.assertEqual(prior, json.loads(self.store.backup_path.read_text(encoding="utf-8")))
        self.change("recover")
        self.assertEqual(["Original", "Later"], [i["title"] for i in self.board["items"]])

    def test_export_restore_repairs_corrupt_primary_without_valid_backup(self):
        self.add("Original")
        exported = deepcopy(self.board)
        self.store.path.write_text("broken", encoding="utf-8")
        self.store.backup_path.write_text("also broken", encoding="utf-8")
        self.expect_error(500, "recover", {}, revision=-1)
        repaired = self.store.mutate("restore", {"board": exported}, -1)
        self.assertEqual(exported["items"], repaired["items"])
        self.assertEqual(exported["revision"] + 1, repaired["revision"])
        self.expect_error(409, "add", {"title": "Stale browser"}, revision=exported["revision"])
        self.assertEqual("also broken", self.store.backup_path.read_text(encoding="utf-8"))
        self.assertEqual("broken", next(self.store.data_dir.glob("board.corrupt-*.json")).read_text(encoding="utf-8"))

    def test_missing_primary_with_backup_requires_explicit_recovery(self):
        self.add("Original")
        self.add("Later")
        self.store.path.unlink()
        with self.assertRaises(StoreError):
            self.store.read()
        repaired = self.store.mutate("recover", {}, -1)
        self.assertEqual(["Original"], [i["title"] for i in repaired["items"]])

    def test_duplicate_json_properties_are_rejected(self):
        self.store.path.write_text('{"schema_version":1,"revision":0,"revision":1,"items":[]}', encoding="utf-8")
        with self.assertRaises(StoreError) as caught:
            self.store.read()
        self.assertIn("Duplicate JSON", str(caught.exception))

    def test_concurrent_threads_one_revision_has_one_winner(self):
        barrier = threading.Barrier(8)

        def mutate(number):
            other = Store(self.store.data_dir)
            barrier.wait(timeout=10)
            try:
                other.mutate("add", {"title": f"Item {number}"}, 0)
                return 200
            except StoreError as exc:
                return exc.status

        with ThreadPoolExecutor(max_workers=8) as pool:
            outcomes = list(pool.map(mutate, range(8)))
        self.assertEqual(1, outcomes.count(200))
        self.assertEqual(7, outcomes.count(409))
        self.assertEqual(1, len(self.store.read()["items"]))

    def test_concurrent_processes_share_the_same_lock(self):
        worker = """
from pathlib import Path
import sys, time
from store import Store, StoreError
root, number = Path(sys.argv[1]), sys.argv[2]
(root / ('ready-' + number)).touch()
deadline = time.monotonic() + 20
while not (root / 'go').exists():
    if time.monotonic() > deadline:
        raise RuntimeError('Barrier timeout')
    time.sleep(0.01)
try:
    Store(root / '.feedback').mutate('add', {'title': 'Process ' + number}, 0)
    print(200)
except StoreError as exc:
    print(exc.status)
"""
        processes = [subprocess.Popen([sys.executable, "-c", worker, self.temp.name, str(n)],
                                      cwd=Path(__file__).parent, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True) for n in range(6)]
        try:
            deadline = time.monotonic() + 15
            while len(list(Path(self.temp.name).glob("ready-*"))) != 6:
                if time.monotonic() > deadline:
                    self.fail("Subprocesses did not reach the test barrier.")
                time.sleep(0.025)
            (Path(self.temp.name) / "go").touch()
            outputs = [p.communicate(timeout=20) for p in processes]
            self.assertTrue(all(p.returncode == 0 for p in processes), outputs)
            outcomes = [int(stdout.strip()) for stdout, _ in outputs]
            self.assertEqual(1, outcomes.count(200))
            self.assertEqual(5, outcomes.count(409))
            self.assertEqual(1, len(self.store.read()["items"]))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


@unittest.skipUnless(shutil.which("git"), "Git is required for worktree resolution tests")
class WorktreeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="feedback worktree tests ")
        self.addCleanup(self.temp.cleanup)
        self.primary = Path(self.temp.name) / "primary checkout"
        self.primary.mkdir()
        self.git(self.primary, "init")
        self.git(self.primary, "config", "user.name", "Feedback Test")
        self.git(self.primary, "config", "user.email", "feedback-test@example.invalid")
        (self.primary / "README.md").write_text("Test fixture", encoding="utf-8")
        self.git(self.primary, "add", "README.md")
        self.git(self.primary, "commit", "-m", "Fixture")

    def git(self, path, *args):
        return subprocess.run(["git", "-c", f"safe.directory={path.as_posix()}", "-C", str(path), *args],
                              capture_output=True, text=True, check=True, timeout=15)

    def test_linked_worktrees_and_branch_switch_use_primary_store(self):
        linked = Path(self.temp.name) / "linked worktree with spaces"
        self.git(self.primary, "worktree", "add", "-b", "feedback-test", str(linked))
        primary_dir = resolve_data_dir(self.primary)
        self.assertEqual(self.primary / ".feedback", primary_dir)
        self.assertEqual(primary_dir, resolve_data_dir(linked))
        nested = linked / "nested"
        nested.mkdir()
        self.assertEqual(primary_dir, resolve_data_dir(nested))
        store = Store(primary_dir)
        empty = store.read()
        saved = store.mutate("add", {"title": "Shared feedback"}, empty["revision"])
        self.git(self.primary, "checkout", "-b", "another-primary-branch")
        self.assertEqual(primary_dir, resolve_data_dir(self.primary))
        self.assertEqual(saved, Store(resolve_data_dir(linked)).read())
        self.assertFalse((linked / ".feedback").exists())

    def test_non_git_copy_uses_its_project_root(self):
        standalone = Path(self.temp.name) / "standalone copy"
        standalone.mkdir()
        self.assertEqual(standalone / ".feedback", resolve_data_dir(standalone))

    def test_git_failure_does_not_create_worktree_local_store(self):
        with patch("store.subprocess.run", side_effect=OSError("git unavailable")):
            with self.assertRaises(StoreError):
                resolve_data_dir(self.primary)
        self.assertFalse((self.primary / ".feedback").exists())


if __name__ == "__main__":
    unittest.main()
