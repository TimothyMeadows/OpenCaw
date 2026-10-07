#!/usr/bin/env python3
"""Offline regressions: real temporary Git/filesystem state, fake GitHub API.

No test contacts GitHub or changes repositories outside its own temporary root.
"""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("task_execution", ROOT / "commands/lib/task-execution.py")
execution = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(execution)


class FakeGitHub:
    def __init__(self, root):
        self.root = root
        self.issues = []
        self.posts = 0
        self.fail_after_create = False
        self.fail_before_create = False
        self.fail_reads = False
        self.repo_id = 42
        self.pages = []

    def issue(self, number, body="unrelated", state="open"):
        return {"number": number, "html_url": f"https://github.com/example/project/issues/{number}",
                "body": body, "state": state}

    def __call__(self, root, endpoint, method="GET", payload=None):
        if self.fail_reads and method == "GET":
            raise execution.TaskError("Simulated read failure")
        if endpoint == "repos/example/project":
            return {"id": self.repo_id, "full_name": "example/project"}
        if method == "POST":
            self.posts += 1
            # The intent must already be durable before the remote write.
            journal = root / ".ai/tasks/work/operations/create-issue.json"
            assert json.loads(journal.read_text())["state"] == "pending"
            if self.fail_before_create:
                raise execution.TaskError("Simulated uncertain write")
            value = self.issue(max([i["number"] for i in self.issues] + [0]) + 1, payload["body"])
            self.issues.append(value)
            if self.fail_after_create:
                raise execution.TaskError("Simulated response lost after remote success")
            return value
        if "?state=all" in endpoint:
            page = int(endpoint.rsplit("=", 1)[1])
            self.pages.append(page)
            return self.issues[(page - 1) * 100:page * 100]
        number = int(endpoint.rsplit("/", 1)[1])
        for issue in self.issues:
            if issue["number"] == number:
                return issue
        raise execution.TaskError("Simulated missing issue")


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".task-execution-test-", dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "OpenCaw Test")
        self.git("config", "user.email", "opencaw-test@example.invalid")
        self.git("config", "core.autocrlf", "false")
        self.git("remote", "add", "origin", "https://github.com/example/project.git")
        (self.root / "seed.txt").write_text("original\n")
        self.git("add", "seed.txt")
        self.git("commit", "-qm", "test baseline")
        execution.create_task(self.root, "work", "Work", no_issue=True)
        self.task = self.root / ".ai/tasks/work/TASK.md"
        self.api = FakeGitHub(self.root)
        self.patch = mock.patch.object(execution, "api", self.api)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True,
                              text=True, check=True).stdout.strip()

    def create(self, **kwargs):
        return execution.create_issue(self.root, "work", **kwargs)

    def journal(self):
        return json.loads((self.root / ".ai/tasks/work/operations/create-issue.json").read_text())

    def prepare(self, verdict="verified"):
        text = self.task.read_text().replace("| unknown | Not yet observed |", f"| {verdict} | Current local fixture |")
        text = text.replace("| unavailable | Not yet checked |", "| evidence.txt | Observed expected result |")
        self.task.write_text(text)
        (self.root / "artifact.txt").write_text("candidate\n")
        (self.root / "evidence.txt").write_text("fixture proof\n")

    def checkpoint(self, **kwargs):
        args = dict(task="work", artifact=["artifact.txt"], evidence=["evidence.txt"], acceptance=None,
                    next_action="Review the saved evidence before PR readiness.", status="ready-for-review",
                    deadline=None, failed_epochs=None, max_failed_epochs=None, reauthorize_window=None)
        args.update(kwargs)
        return execution.record_checkpoint(self.root, argparse.Namespace(**args))

    def validate(self, phase="resume"):
        return execution.validate_checkpoint(self.root, "work", phase)

    def latest(self):
        return execution.checkpoint_paths(self.root, "work")[-1]


class IssueRecoveryTests(Fixture):
    def test_normal_creation_and_reuse(self):
        first = self.create()
        self.assertEqual(first, self.create())
        self.assertEqual(self.api.posts, 1)
        self.assertEqual(self.journal()["state"], "confirmed")
        self.assertEqual((self.root / ".ai/tasks/OPEN_ISSUES.md").read_text().splitlines(), [first])

    def test_lost_response_reconciles_without_another_post(self):
        self.api.fail_after_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.assertEqual(self.journal()["state"], "pending")
        self.api.fail_after_create = False
        self.assertTrue(self.create().endswith("/1"))
        self.assertEqual(self.api.posts, 1)

    def test_confirmed_remote_result_repairs_failed_local_persistence(self):
        with mock.patch.object(execution, "persist_issue", side_effect=OSError("simulated disk failure")):
            with self.assertRaises(OSError):
                self.create()
        self.assertEqual(self.journal()["state"], "confirmed")
        self.create()
        self.assertEqual(self.api.posts, 1)
        self.assertIn("/issues/1", self.task.read_text())

    def test_no_match_after_ambiguous_post_blocks_retry(self):
        self.api.fail_before_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.api.fail_before_create = False
        with self.assertRaisesRegex(execution.TaskError, "Prior issue creation"):
            self.create()
        self.assertEqual(self.api.posts, 1)

    def test_explicit_absence_authorization_retains_attempt_history(self):
        self.api.fail_before_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.api.fail_before_create = False
        self.create(retry_reason="Operator inspected GitHub and explicitly authorized retry.")
        self.assertEqual(len(self.journal()["attempts"]), 2)
        self.assertEqual(self.api.posts, 2)

    def test_reconcile_only_never_creates(self):
        with self.assertRaisesRegex(execution.TaskError, "reconcile-only"):
            self.create(reconcile_only=True)
        self.assertEqual(self.api.posts, 0)
        self.assertFalse((self.root / ".ai/tasks/work/operations").exists())

    def test_reconcile_only_and_retry_are_mutually_exclusive(self):
        with self.assertRaises(execution.TaskError):
            self.create(reconcile_only=True, retry_reason="not allowed")
        self.assertEqual(self.api.posts, 0)

    def test_duplicate_remote_markers_block(self):
        self.api.fail_after_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.api.issues.append(self.api.issue(2, self.api.issues[0]["body"]))
        with self.assertRaisesRegex(execution.TaskError, "Multiple issues"):
            self.create()
        self.assertEqual(self.api.posts, 1)

    def test_marker_recovery_without_local_journal(self):
        self.create()
        url = self.api.issues[0]["html_url"]
        self.task.write_text(self.task.read_text().replace(url, ""))
        (self.root / ".ai/tasks/work/operations/create-issue.json").unlink()
        self.create()
        self.assertEqual(self.api.posts, 1)

    def test_pagination_includes_closed_issues_and_excludes_prs(self):
        self.api.issues = [self.api.issue(i) for i in range(1, 101)]
        self.api.fail_after_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.api.issues[-1]["state"] = "closed"
        self.api.issues.append({**self.api.issue(102, self.api.issues[-1]["body"]), "pull_request": {}})
        self.api.fail_after_create = False
        self.create()
        self.assertIn(2, self.api.pages)
        self.assertEqual(self.api.posts, 1)
        self.assertEqual((self.root / ".ai/tasks/OPEN_ISSUES.md").read_text(), "")

    def test_legacy_explicit_link_is_verified_and_reused(self):
        self.api.issues = [self.api.issue(7)]
        self.task.write_text(self.task.read_text() + "\nhttps://github.com/example/project/issues/7\n")
        self.create()
        self.assertEqual(self.api.posts, 0)

    def test_unrelated_issue_in_goal_is_not_the_task_link(self):
        self.task.write_text(self.task.read_text().replace("## Goal", "## Goal\n\nSee https://github.com/example/project/issues/9"))
        self.assertTrue(self.create().endswith("/1"))
        self.assertEqual(self.api.posts, 1)

    def test_preserves_sections_after_issue(self):
        self.task.write_text(self.task.read_text() + "\n## User Notes\n\nKeep this note.\n")
        self.create()
        self.assertIn("## User Notes\n\nKeep this note.", self.task.read_text())
        self.assertEqual(execution.linked_issue(self.task.read_text()), self.api.issues[0]["html_url"])

    def test_cross_repository_link_blocks(self):
        self.task.write_text(self.task.read_text() + "\nhttps://github.com/other/project/issues/7\n")
        with self.assertRaisesRegex(execution.TaskError, "does not belong"):
            self.create()
        self.assertEqual(self.api.posts, 0)

    def test_repository_identity_drift_blocks(self):
        self.create()
        self.api.repo_id = 43
        with self.assertRaisesRegex(execution.TaskError, "different repository"):
            self.create()
        self.assertEqual(self.api.posts, 1)

    def test_network_read_failure_does_not_create(self):
        self.api.fail_reads = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.assertEqual(self.api.posts, 0)

    def test_missing_confirmed_issue_is_not_recreated(self):
        self.create()
        self.api.issues.clear()
        with self.assertRaises(execution.TaskError):
            self.create()
        self.assertEqual(self.api.posts, 1)

    def test_malformed_journal_is_not_overwritten(self):
        operations = self.root / ".ai/tasks/work/operations"
        operations.mkdir()
        journal = operations / "create-issue.json"
        journal.write_text("{broken")
        with self.assertRaisesRegex(execution.TaskError, "Malformed JSON"):
            self.create()
        self.assertEqual(journal.read_text(), "{broken")
        self.assertEqual(self.api.posts, 0)

    def test_lock_blocks_same_and_different_tasks(self):
        execution.create_task(self.root, "other", "Other", no_issue=True)
        with execution.task_lock(self.root):
            for name in ("work", "other"):
                with self.assertRaisesRegex(execution.TaskError, "lock exists"):
                    execution.create_issue(self.root, name)
        self.assertEqual(self.api.posts, 0)

    def test_invalid_task_names_are_rejected(self):
        for name in ("../escape", "/tmp/escape", "a/b", "a\\b", ".", ""):
            with self.subTest(name=name), self.assertRaises(execution.TaskError):
                execution.create_task(self.root, name, "No", no_issue=True)

    def test_symlinked_operation_directory_is_rejected(self):
        target = self.root / "unrelated"
        target.mkdir()
        (self.root / ".ai/tasks/work/operations").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(execution.TaskError, "Symlink"):
            self.create()
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(self.api.posts, 0)

    def test_insecure_or_credentialed_remote_is_rejected(self):
        for remote in ("http://github.com/example/project.git", "https://user:secret@github.com/example/project.git", "https://example.invalid/example/project.git"):
            self.git("remote", "set-url", "origin", remote)
            with self.assertRaisesRegex(execution.TaskError, "origin must"):
                self.create()
        self.assertEqual(self.api.posts, 0)

    def test_existing_task_is_not_rewritten_by_scaffold(self):
        self.task.write_text(self.task.read_text() + "\nUser work survives.\n")
        before = self.task.read_bytes()
        execution.create_task(self.root, "work", "Changed title", no_issue=True)
        self.assertEqual(before, self.task.read_bytes())

    def test_issue_body_cannot_escape_project(self):
        with self.assertRaises(execution.TaskError):
            self.create(body_file="../outside.md")
        self.assertEqual(self.api.posts, 0)


class CheckpointTests(Fixture):
    def test_fresh_checkpoint_and_read_only_validation(self):
        self.prepare()
        self.checkpoint()
        before = {p.relative_to(self.root).as_posix(): p.read_bytes()
                  for p in self.root.rglob("*") if p.is_file() and ".git" not in p.parts}
        self.assertIn("declared files only", self.validate("complete"))
        after = {p.relative_to(self.root).as_posix(): p.read_bytes()
                 for p in self.root.rglob("*") if p.is_file() and ".git" not in p.parts}
        self.assertEqual(before, after)

    def test_dirty_tracked_artifact_content_is_bound(self):
        self.prepare()
        (self.root / "seed.txt").write_text("dirty one\n")
        self.checkpoint(artifact=["seed.txt"])
        (self.root / "seed.txt").write_text("dirty two\n")
        with self.assertRaisesRegex(execution.TaskError, "Stale checkpoint"):
            self.validate()

    def test_untracked_artifact_content_is_bound(self):
        self.prepare()
        self.checkpoint()
        (self.root / "artifact.txt").write_text("new bytes\n")
        with self.assertRaisesRegex(execution.TaskError, "Stale checkpoint"):
            self.validate()

    def test_changed_or_missing_evidence_blocks(self):
        self.prepare()
        self.checkpoint()
        (self.root / "evidence.txt").unlink()
        with self.assertRaisesRegex(execution.TaskError, "Missing regular file"):
            self.validate()

    def test_changed_task_contract_blocks(self):
        self.prepare()
        self.checkpoint()
        self.task.write_text(self.task.read_text() + "\nScope changed.\n")
        with self.assertRaisesRegex(execution.TaskError, "Stale checkpoint"):
            self.validate()

    def test_changed_head_blocks(self):
        self.prepare()
        self.checkpoint()
        self.git("commit", "--allow-empty", "-qm", "new candidate")
        with self.assertRaisesRegex(execution.TaskError, "HEAD changed"):
            self.validate()

    def test_required_nonverified_verdicts_block_completion(self):
        for verdict in ("unknown", "inferred", "stale", "contradicted"):
            with self.subTest(verdict=verdict):
                self.prepare()
                text = self.task.read_text()
                for old in execution.VERDICTS:
                    text = text.replace(f"| {old} | Current local fixture |", f"| {verdict} | Current local fixture |")
                self.task.write_text(text)
                self.checkpoint()
                with self.assertRaisesRegex(execution.TaskError, "blocks completion"):
                    self.validate("complete")

    def test_declared_optional_unknown_is_nonblocking(self):
        self.prepare("unknown")
        self.task.write_text(self.task.read_text().replace("Optional acceptance IDs: none", "Optional acceptance IDs: A-001"))
        self.checkpoint()
        self.validate("complete")

    def test_optional_declaration_unknown_id_blocks(self):
        self.prepare()
        self.task.write_text(self.task.read_text().replace("Optional acceptance IDs: none", "Optional acceptance IDs: A-999"))
        self.checkpoint()
        with self.assertRaisesRegex(execution.TaskError, "unknown ID"):
            self.validate("complete")

    def test_expired_window_records_stopped_and_preserves_next_action(self):
        self.prepare()
        result = self.checkpoint(deadline="2000-01-01T00:00:00Z")
        self.assertIn("status: stopped", result)
        self.assertIn("Review the saved evidence", json.loads(self.latest().read_text())["next_action"])
        with self.assertRaisesRegex(execution.TaskError, "reauthorization"):
            self.validate()

    def test_failed_epoch_limit_is_inherited_not_reset(self):
        self.prepare()
        self.checkpoint(failed_epochs=1, max_failed_epochs=2)
        self.checkpoint()
        self.assertEqual(json.loads(self.latest().read_text())["window"]["failed_epochs"], 1)
        self.checkpoint(failed_epochs=2)
        with self.assertRaisesRegex(execution.TaskError, "stopped"):
            self.validate()
        self.checkpoint()
        self.assertEqual(json.loads(self.latest().read_text())["status"], "stopped")

    def test_reset_or_extension_requires_explicit_reauthorization(self):
        self.prepare()
        self.checkpoint(failed_epochs=1, max_failed_epochs=2, deadline="2090-01-01T00:00:00Z")
        for change in ({"failed_epochs": 0}, {"max_failed_epochs": 3}, {"deadline": "2091-01-01T00:00:00Z"}):
            with self.subTest(change=change), self.assertRaisesRegex(execution.TaskError, "reauthorize-window"):
                self.checkpoint(**change)

    def test_reauthorization_preserves_history(self):
        self.prepare()
        self.checkpoint(failed_epochs=2, max_failed_epochs=2)
        previous, data = self.latest(), self.latest().read_bytes()
        self.checkpoint(failed_epochs=0, reauthorize_window="Owner explicitly authorized another bounded run.")
        self.validate()
        self.assertEqual(previous.read_bytes(), data)

    def test_pending_external_operation_blocks_completion(self):
        self.prepare()
        self.api.fail_before_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        self.checkpoint()
        with self.assertRaisesRegex(execution.TaskError, "unresolved outcome"):
            self.validate("complete")

    def test_new_external_operation_invalidates_checkpoint(self):
        self.prepare()
        self.checkpoint()
        self.api.fail_before_create = True
        with self.assertRaises(execution.TaskError):
            self.create()
        with self.assertRaisesRegex(execution.TaskError, "External-operation state changed"):
            self.validate()

    def test_history_is_append_only_and_latest_is_used(self):
        self.prepare()
        self.checkpoint()
        first, before = self.latest(), self.latest().read_bytes()
        self.checkpoint(status="blocked")
        self.assertEqual(first.read_bytes(), before)
        with self.assertRaisesRegex(execution.TaskError, "stopped or blocked"):
            self.validate()

    def test_missing_checkpoint_does_not_create_state(self):
        with self.assertRaisesRegex(execution.TaskError, "No checkpoint"):
            self.validate()
        self.assertFalse((self.root / ".ai/tasks/work/checkpoints").exists())

    def test_symlink_evidence_is_rejected(self):
        self.prepare()
        (self.root / "link.txt").symlink_to(self.root / "evidence.txt")
        with self.assertRaisesRegex(execution.TaskError, "Symlink"):
            self.checkpoint(evidence=["link.txt"])

    def test_omitted_contract_hash_is_rejected(self):
        self.prepare()
        self.checkpoint()
        record = json.loads(self.latest().read_text())
        del record["files"][record["contract"]]
        self.latest().write_text(json.dumps(record))
        with self.assertRaisesRegex(execution.TaskError, "omits required"):
            self.validate()

    def test_malformed_acceptance_matrix_is_rejected(self):
        self.prepare()
        self.task.write_text(self.task.read_text().replace("| verified |", "| pass |"))
        with self.assertRaisesRegex(execution.TaskError, "canonical eight columns"):
            self.checkpoint()

    def test_unrelated_work_is_never_modified(self):
        self.prepare()
        (self.root / "seed.txt").write_text("user's uncommitted work\n")
        self.checkpoint()
        self.validate()
        self.assertEqual((self.root / "seed.txt").read_text(), "user's uncommitted work\n")
        self.assertIn("M seed.txt", self.git("status", "--short"))

    def test_negative_epoch_count_is_rejected(self):
        self.prepare()
        with self.assertRaisesRegex(execution.TaskError, "nonnegative"):
            self.checkpoint(failed_epochs=-1)

    def test_checkpoint_gap_is_rejected(self):
        self.prepare()
        self.checkpoint()
        self.latest().rename(self.latest().with_name("checkpoint-000002.json"))
        with self.assertRaisesRegex(execution.TaskError, "history has a gap"):
            self.validate()

    def test_malformed_prior_checkpoint_cannot_reset_window(self):
        self.prepare()
        self.checkpoint(failed_epochs=2, max_failed_epochs=2)
        record = json.loads(self.latest().read_text())
        del record["window"]
        self.latest().write_text(json.dumps(record))
        with self.assertRaisesRegex(execution.TaskError, "Malformed prior checkpoint"):
            self.checkpoint()

    def test_fenced_matrix_examples_do_not_count_as_acceptance(self):
        self.prepare()
        text = self.task.read_text()
        table = text[text.index("| ID | Acceptance claim"):text.index("## Review")]
        self.task.write_text(text + "\n```markdown\n" + table + "```\n")
        self.checkpoint()
        self.validate("complete")

    def test_changed_evidence_bytes_are_stale(self):
        self.prepare()
        self.checkpoint()
        (self.root / "evidence.txt").write_text("different evidence\n")
        with self.assertRaisesRegex(execution.TaskError, "Stale checkpoint"):
            self.validate()

    def test_no_evidence_file_blocks_completion(self):
        self.prepare()
        self.checkpoint(evidence=[])
        with self.assertRaisesRegex(execution.TaskError, "saved evidence files"):
            self.validate("complete")

    def test_checkpoint_does_not_complete_an_in_progress_task(self):
        self.prepare()
        self.checkpoint(status="in-progress")
        with self.assertRaisesRegex(execution.TaskError, "ready-for-review"):
            self.validate("complete")

    def test_cli_and_help(self):
        self.prepare()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            code = execution.main(["--root", str(self.root), "checkpoint", "work", "--artifact", "artifact.txt", "--evidence", "evidence.txt", "--next-action", "Review evidence."])
        self.assertEqual(code, 0)
        self.assertIn("recorded hashes are not verification verdicts", output.getvalue())
        for name in ("create-task-file", "create-task-issue", "record-task-checkpoint", "validate-task-checkpoint"):
            result = subprocess.run(["bash", str(ROOT / "commands" / f"{name}.sh"), "--help"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
