#!/usr/bin/env python3
"""Task-local recovery and checkpoints. Python standard library only.

Bash entry points resolve the host and apply the existing Brainstorm guard.
These checks detect accidental drift; they are not a sandbox, distributed lock,
or proof that an agent's evidence semantically establishes its claims.
"""
import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile


class TaskError(Exception):
    """A safe, actionable failure that must not be silently retried."""


def now():
    return dt.datetime.now(dt.timezone.utc)


def timestamp():
    return now().isoformat(timespec="seconds").replace("+00:00", "Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")


def single_line(value, label):
    if not isinstance(value, str) or not value.strip() or any(ord(c) < 32 for c in value):
        raise TaskError(f"{label} must be a nonempty single line.")
    return value


def safe_path(root, relative, required=False):
    """Reject path escapes and every symlink component before reading/writing."""
    relative = relative.as_posix() if isinstance(relative, Path) else str(relative)
    parts = PurePosixPath(relative).parts
    if (not parts or relative.startswith("/") or "\\" in relative or
            any(p in ("..", ".git") or ":" in p for p in parts) or
            any(ord(c) < 32 for c in relative)):
        raise TaskError("Use a project-relative path without traversal or .git components.")
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise TaskError(f"Symlink paths are not supported: {relative}")
    if required and not current.is_file():
        raise TaskError(f"Missing regular file: {relative}")
    if current.exists() and not (current.is_file() or current.is_dir()):
        raise TaskError(f"Unsupported file type: {relative}")
    return current


def task_dir(root, task, create=False):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,119}", task):
        raise TaskError("Task name must be a single filesystem-safe identifier.")
    path = safe_path(root, f".ai/tasks/{task}")
    if create:
        path.mkdir(parents=True, exist_ok=True)
    return path


def sync_directory(path):
    # Windows does not support opening directories this way. File fsync remains.
    if os.name != "nt":
        fd = os.open(path, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def atomic_write(root, path, data):
    safe_path(root, path.relative_to(root))
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix=".opencaw-write-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        safe_path(root, path.relative_to(root))
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


@contextlib.contextmanager
def task_lock(root):
    # Also serializes OPEN_ISSUES.md read/modify/write across different tasks.
    parent = safe_path(root, ".ai/tasks")
    parent.mkdir(parents=True, exist_ok=True)
    lock = safe_path(root, ".ai/tasks/.execution-lock")
    try:
        lock.mkdir()
    except FileExistsError as exc:
        raise TaskError("Task execution lock exists. Check for an active writer; never remove it blindly.") from exc
    try:
        yield
    finally:
        lock.rmdir()


def load_json(root, path):
    safe_path(root, path.relative_to(root), required=True)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as exc:
        raise TaskError(f"Malformed JSON state: {path.relative_to(root)}") from exc


def run(args, root, data=None):
    try:
        result = subprocess.run(args, cwd=root, input=data, capture_output=True,
                                text=True, timeout=60, check=False,
                                env={**os.environ, "GH_HOST": "github.com", "GH_PROMPT_DISABLED": "1"})
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TaskError(f"{Path(args[0]).name} unavailable or timed out; external outcomes may be unknown.") from exc
    if result.returncode:
        # Do not echo CLI stderr: it can contain credentials or private values.
        raise TaskError(f"{Path(args[0]).name} failed. Check tool access; do not blindly repeat an external write.")
    return result.stdout


def api(root, endpoint, method="GET", payload=None):
    gh = shutil.which("gh") or shutil.which("gh.exe")
    if not gh:
        raise TaskError("GitHub CLI (gh) is required; no software will be installed.")
    args = [gh, "api", "--hostname", "github.com", "--method", method, endpoint]
    if payload is not None:
        args += ["--input", "-"]
    output = run(args, root, json.dumps(payload) if payload is not None else None)
    try:
        return json.loads(output)
    except ValueError as exc:
        raise TaskError("GitHub returned invalid JSON; any write outcome remains unknown.") from exc


def repository(root):
    actual_root = Path(run(["git", "rev-parse", "--show-toplevel"], root).strip()).resolve()
    if actual_root != root:
        raise TaskError("The resolved project must be its own Git root; no baseline/parent fallback.")
    remote = run(["git", "remote", "get-url", "origin"], root).strip()
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?", remote)
    if not match:
        raise TaskError("origin must be credential-free HTTPS or SSH on github.com.")
    name = match.group(1)
    metadata = api(root, f"repos/{name}")
    if (not isinstance(metadata, dict) or type(metadata.get("id")) is not int or
            not isinstance(metadata.get("full_name"), str) or
            metadata["full_name"].lower() != name.lower()):
        raise TaskError("GitHub repository identity does not match origin.")
    return metadata["full_name"], metadata["id"]


def section(text, heading):
    matches = list(re.finditer(r"(?m)^## " + re.escape(heading) + r"\s*$", text))
    if len(matches) > 1:
        raise TaskError(f"Duplicate {heading} sections.")
    if not matches:
        return None
    start = matches[0].end()
    following = re.search(r"(?m)^## ", text[start:])
    return start, start + following.start() if following else len(text)


def linked_issue(text):
    bounds = section(text, "Issue")
    if not bounds:
        return None
    urls = set(re.findall(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+", text[bounds[0]:bounds[1]]))
    if len(urls) > 1:
        raise TaskError("Task has conflicting issue links.")
    return next(iter(urls), None)


def checked_issue(value, repo, marker=None):
    if not isinstance(value, dict) or "pull_request" in value:
        raise TaskError("Expected a same-repository issue, not a pull request.")
    number = value.get("number")
    expected = f"https://github.com/{repo}/issues/{number}"
    if (type(number) is not int or number <= 0 or not isinstance(value.get("html_url"), str) or
            value["html_url"].lower() != expected.lower() or
            value.get("state") not in ("open", "closed")):
        raise TaskError("Invalid or cross-repository issue response.")
    if value.get("body") is not None and not isinstance(value["body"], str):
        raise TaskError("Malformed issue body in GitHub response.")
    if marker and marker not in (value.get("body") or "").splitlines():
        raise TaskError("Issue operation marker does not match the recorded intent.")
    return value


def lookup_issue(root, repo, url, marker=None):
    if not isinstance(url, str):
        raise TaskError("Malformed recorded issue URL.")
    match = re.fullmatch(r"https://github\.com/" + re.escape(repo) + r"/issues/([1-9][0-9]*)", url, re.I)
    if not match:
        raise TaskError("Linked issue does not belong to the resolved repository.")
    return checked_issue(api(root, f"repos/{repo}/issues/{match.group(1)}"), repo, marker)


def find_operation(root, repo, marker):
    matches = {}
    # Paginate the repository endpoint, not eventually indexed search. Still no
    # claim that an empty read proves an interrupted POST never succeeded.
    for page in range(1, 1001):
        values = api(root, f"repos/{repo}/issues?state=all&per_page=100&page={page}")
        if not isinstance(values, list):
            raise TaskError("Malformed issue listing; reconciliation is incomplete.")
        for value in values:
            if not isinstance(value, dict):
                raise TaskError("Malformed item in issue listing.")
            if value.get("body") is not None and not isinstance(value["body"], str):
                raise TaskError("Malformed issue body in listing.")
            if "pull_request" not in value and marker in (value.get("body") or "").splitlines():
                issue = checked_issue(value, repo, marker)
                matches[issue["number"]] = issue
        if len(values) < 100:
            break
    else:
        raise TaskError("Issue pagination limit reached; reconciliation is incomplete.")
    if len(matches) > 1:
        raise TaskError("Multiple issues have the operation marker. Resolve the conflict; no write was attempted.")
    return next(iter(matches.values()), None)


def persist_issue(root, task, issue):
    task_dir(root, task)
    path = safe_path(root, f".ai/tasks/{task}/TASK.md", required=True)
    text = path.read_text(encoding="utf-8")
    url = issue["html_url"]
    bounds = section(text, "Issue")
    existing = linked_issue(text)
    if existing and existing.lower() != url.lower():
        raise TaskError("Task issue changed during execution; reconcile local state first.")
    if not existing:
        if bounds:
            # Preserve non-link notes and every following section.
            text = text[:bounds[1]].rstrip() + "\n\n" + url + "\n\n" + text[bounds[1]:]
        else:
            text = text.rstrip() + "\n\n## Issue\n\n" + url + "\n"
        atomic_write(root, path, text.encode("utf-8"))
    tracking = safe_path(root, ".ai/tasks/OPEN_ISSUES.md")
    lines = tracking.read_text(encoding="utf-8").splitlines() if tracking.exists() else []
    lines = [line for line in lines if line.lower() != url.lower()]
    if issue["state"] == "open":
        lines.append(url)
    atomic_write(root, tracking, ("\n".join(lines) + ("\n" if lines else "")).encode("utf-8"))
    return url


def create_issue(root, task, title=None, body_file=None, reconcile_only=False, retry_reason=None):
    task_dir(root, task)
    task_path = safe_path(root, f".ai/tasks/{task}/TASK.md", required=True)
    title = single_line(title or f"Task: {task}", "Issue title")
    if retry_reason:
        single_line(retry_reason, "Explicit retry authorization reason")
    if retry_reason and reconcile_only:
        raise TaskError("Reconcile-only cannot authorize another write.")
    body = None
    if body_file:
        candidate = Path(body_file)
        if candidate.is_absolute():
            try:
                body_file = candidate.relative_to(root).as_posix()
            except ValueError as exc:
                raise TaskError("Issue body must be inside the project.") from exc
        body = safe_path(root, body_file, required=True).read_text(encoding="utf-8")
    with task_lock(root):
        repo, repo_id = repository(root)
        operation = digest(f"opencaw:task-issue:v1\0{repo_id}\0{task}".encode())
        marker = f"<!-- opencaw-task-issue:v1 operation={operation} -->"
        journal = safe_path(root, f".ai/tasks/{task}/operations/create-issue.json")
        state = load_json(root, journal) if journal.exists() else None
        if state is not None and (not isinstance(state, dict) or state.get("version") != 1 or
                state.get("operation") != operation or state.get("repository_id") != repo_id or
                state.get("state") not in ("pending", "confirmed") or not isinstance(state.get("attempts"), list)):
            raise TaskError("Operation journal is malformed or belongs to a different repository/task.")
        text = task_path.read_text(encoding="utf-8")
        existing = linked_issue(text)
        if state and state["state"] == "confirmed":
            issue = lookup_issue(root, repo, state.get("url", ""), marker)
            return persist_issue(root, task, issue)
        if existing and state is None:
            # Legacy/imported explicit issue links need not carry our marker.
            issue = lookup_issue(root, repo, existing)
            return persist_issue(root, task, issue)
        issue = find_operation(root, repo, marker)
        if issue is None:
            if reconcile_only:
                raise TaskError("No matching issue observed. Outcome is unresolved; reconcile-only will not create one.")
            if state is not None and not retry_reason:
                raise TaskError("Prior issue creation may have succeeded. No match observed; stop or use --retry-confirmed-absent only after explicit human reconciliation.")
            if state is None and retry_reason:
                raise TaskError("Retry authorization requires an existing pending operation.")
            if existing:
                raise TaskError("A pending operation conflicts with the task issue link.")
            if body is None:
                bounds = section(text, "Issue")
                clean = text[:bounds[0]] + text[bounds[1]:] if bounds else text
                body = f"OpenCaw task issue for `{task}`.\n\nTask file: `.ai/tasks/{task}/TASK.md`\n\n{clean}"
            if "<!-- opencaw-task-issue:" in body:
                raise TaskError("Issue body must not supply an operation marker.")
            body = body.rstrip() + "\n\n" + marker + "\n"
            if state is None:
                state = {"version": 1, "repository_id": repo_id, "operation": operation, "state": "pending", "attempts": []}
            state["attempts"].append({"started_at": timestamp(), "request_sha256": digest(encoded({"title": title, "body": body})),
                                      "authorization": retry_reason or "initial task issue creation"})
            journal.parent.mkdir(parents=True, exist_ok=True)
            # Durable intent comes BEFORE the only non-idempotent operation.
            atomic_write(root, journal, encoded(state))
            issue = checked_issue(api(root, f"repos/{repo}/issues", "POST", {"title": title, "body": body}), repo, marker)
        if state is None:
            state = {"version": 1, "repository_id": repo_id, "operation": operation, "attempts": []}
            journal.parent.mkdir(parents=True, exist_ok=True)
        state.update(state="confirmed", url=issue["html_url"], confirmed_at=timestamp())
        # A crash after this write is repaired without another issue creation.
        atomic_write(root, journal, encoded(state))
        return persist_issue(root, task, issue)


def create_task(root, task, title, no_issue=False):
    task_dir(root, task)
    single_line(title or task, "Task title")
    with task_lock(root):
        task_dir(root, task, create=True)
        target = safe_path(root, f".ai/tasks/{task}/TASK.md")
        if not target.exists():
            baseline = Path(__file__).resolve().parents[2]
            template = baseline / "skills/create-task-file/references/task-template.md"
            content = template.read_text(encoding="utf-8").replace("{{TASK_TITLE}}", title or task)
            atomic_write(root, target, content.encode("utf-8"))
    if not no_issue:
        print("Issue created/linked: " + create_issue(root, task, title or task))
    return str(target)


def fingerprint(root, relative):
    path = safe_path(root, relative, required=True)
    with path.open("rb") as stream:
        before = os.fstat(stream.fileno())
        value = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
        after = os.fstat(stream.fileno())
    current = path.stat()
    signature = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode)
    if signature(before) != signature(after) or signature(after) != signature(current):
        raise TaskError(f"File changed while hashing: {relative}")
    return {"sha256": value.hexdigest(), "size": after.st_size, "executable": bool(after.st_mode & 0o111)}


def git_head(root):
    actual = Path(run(["git", "rev-parse", "--show-toplevel"], root).strip()).resolve()
    if actual != root:
        raise TaskError("Checkpoint requires the resolved project Git root.")
    # A checkpoint needs an actual candidate base, not an invented/unborn SHA.
    head = run(["git", "rev-parse", "--verify", "HEAD"], root).strip()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", head):
        raise TaskError("No valid candidate commit is available.")
    return head


MATRIX_COLUMNS = ["ID", "Acceptance claim", "Evidence class", "Expected observation", "Evidence location", "Actual observation", "Verdict", "Limits and freshness"]
VERDICTS = {"verified", "contradicted", "inferred", "unknown", "stale"}


def acceptance_rows(text):
    rows, reading, found = [], False, 0
    fence = None
    for line in text.splitlines():
        fence_match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if fence_match:
            token = fence_match.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            reading = False
            continue
        if fence is not None:
            continue
        cells = [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]
        if cells == MATRIX_COLUMNS:
            found += 1
            reading = True
            continue
        if not reading:
            continue
        if not line.strip().startswith("|"):
            reading = False
            continue
        if all(re.fullmatch(r":?-+:?", c.replace(" ", "")) for c in cells):
            continue
        if (len(cells) != len(MATRIX_COLUMNS) or not all(cells) or
                not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", cells[0]) or cells[6] not in VERDICTS):
            raise TaskError("Malformed acceptance matrix row; retain the canonical eight columns and verdicts.")
        rows.append(dict(zip(MATRIX_COLUMNS, cells)))
    if found != 1 or not rows or len({r["ID"] for r in rows}) != len(rows):
        raise TaskError("Exactly one nonempty canonical acceptance matrix with unique IDs is required.")
    return rows


def deadline_value(value):
    if value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value):
        raise TaskError("Deadline must be canonical UTC: YYYY-MM-DDTHH:MM:SSZ.")
    try:
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError as exc:
        raise TaskError("Invalid deadline.") from exc


def window_exhausted(window):
    if not isinstance(window, dict) or set(window) != {"deadline", "failed_epochs", "max_failed_epochs"}:
        raise TaskError("Malformed execution window.")
    failed, maximum = window["failed_epochs"], window["max_failed_epochs"]
    if type(failed) is not int or failed < 0 or (maximum is not None and (type(maximum) is not int or maximum < 1)):
        raise TaskError("Validation counts must be nonnegative, with a positive maximum when specified.")
    deadline = deadline_value(window["deadline"])
    return (deadline is not None and now() >= deadline) or (maximum is not None and failed >= maximum)


def operation_states(root, task):
    directory = safe_path(root, f".ai/tasks/{task}/operations")
    result = {}
    if directory.exists():
        for path in sorted(directory.glob("*.json")):
            record = load_json(root, path)
            if not isinstance(record, dict) or record.get("state") not in ("pending", "confirmed"):
                raise TaskError("Malformed external-operation state; do not treat it as complete.")
            result[path.relative_to(root).as_posix()] = record["state"]
    return result


def checkpoint_paths(root, task):
    directory = safe_path(root, f".ai/tasks/{task}/checkpoints")
    if not directory.exists():
        return []
    paths = sorted(directory.glob("checkpoint-*.json"))
    for index, path in enumerate(paths, 1):
        if path.name != f"checkpoint-{index:06d}.json":
            raise TaskError("Checkpoint history has a gap or invalid filename.")
        safe_path(root, path.relative_to(root), required=True)
    return paths


def record_checkpoint(root, args):
    task_dir(root, args.task)
    single_line(args.next_action, "Next action")
    contract = f".ai/tasks/{args.task}/TASK.md"
    acceptance = args.acceptance or contract
    with task_lock(root):
        history = checkpoint_paths(root, args.task)
        previous = load_json(root, history[-1]) if history else None
        if previous is not None and (not isinstance(previous, dict) or previous.get("version") != 1 or
                previous.get("task") != args.task or previous.get("contract") != contract or
                "window" not in previous or previous.get("status") not in
                ("in-progress", "stopped", "blocked", "ready-for-review", "completed")):
            raise TaskError("Malformed prior checkpoint; do not reset its execution window.")
        old_window = previous.get("window") if isinstance(previous, dict) else None
        if old_window is not None:
            window_exhausted(old_window)  # Validate before inheriting any limits.
        defaults = old_window or {"deadline": None, "failed_epochs": 0, "max_failed_epochs": None}
        window = {key: getattr(args, key) if getattr(args, key) is not None else defaults[key]
                  for key in ("deadline", "failed_epochs", "max_failed_epochs")}
        if args.reauthorize_window:
            single_line(args.reauthorize_window, "Window reauthorization reason")
        elif old_window:
            extended_deadline = (old_window["deadline"] is not None and
                                 deadline_value(window["deadline"]) > deadline_value(old_window["deadline"]))
            extended_count = (old_window["max_failed_epochs"] is not None and
                              window["max_failed_epochs"] > old_window["max_failed_epochs"])
            if extended_deadline or extended_count or window["failed_epochs"] < old_window["failed_epochs"]:
                raise TaskError("Increasing a window or resetting failures requires --reauthorize-window with explicit human authorization.")
        exhausted = window_exhausted(window)
        must_remain_stopped = (previous and previous.get("status") in {"stopped", "blocked"}
                               and not args.reauthorize_window)
        acceptance_rows(safe_path(root, acceptance, required=True).read_text(encoding="utf-8"))
        operations = operation_states(root, args.task)
        paths = sorted(set([contract, acceptance] + args.artifact + args.evidence + list(operations)))
        prefix = f".ai/tasks/{args.task}/checkpoints/"
        if any(str(p).startswith(prefix) for p in paths):
            raise TaskError("Checkpoint records cannot be their own candidate or evidence.")
        head = git_head(root)
        files = {p: fingerprint(root, p) for p in paths}
        if git_head(root) != head or any(fingerprint(root, p) != files[p] for p in paths):
            raise TaskError("Candidate changed during checkpoint creation.")
        state = "stopped" if exhausted or must_remain_stopped else args.status
        record = {"version": 1, "task": args.task, "created_at": timestamp(), "git_head": head,
                  "contract": contract, "acceptance": acceptance, "artifacts": sorted(set(args.artifact)),
                  "evidence": sorted(set(args.evidence)), "files": files, "operations": operations,
                  "status": state, "next_action": args.next_action, "window": window,
                  "window_reauthorization": args.reauthorize_window}
        directory = safe_path(root, f".ai/tasks/{args.task}/checkpoints")
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f"checkpoint-{len(history) + 1:06d}.json"
        atomic_write(root, target, encoded(record))
        return f"{target.relative_to(root)} (status: {state}; recorded hashes are not verification verdicts)"


def validate_checkpoint(root, task, phase):
    task_dir(root, task)
    history = checkpoint_paths(root, task)
    if not history:
        raise TaskError("No checkpoint exists. Inspect the workspace and evidence before recording one.")
    record = load_json(root, history[-1])
    contract = f".ai/tasks/{task}/TASK.md"
    if (not isinstance(record, dict) or record.get("version") != 1 or record.get("task") != task or
            record.get("contract") != contract or not isinstance(record.get("files"), dict) or
            not isinstance(record.get("artifacts"), list) or not record["artifacts"] or
            not isinstance(record.get("evidence"), list) or not isinstance(record.get("operations"), dict) or
            record.get("status") not in ("in-progress", "stopped", "blocked", "ready-for-review", "completed")):
        raise TaskError("Malformed checkpoint contract.")
    single_line(record.get("next_action", ""), "Recorded next action")
    exhausted = window_exhausted(record.get("window"))
    required = [contract, record.get("acceptance")] + record["artifacts"] + record["evidence"] + list(record["operations"])
    if any(not isinstance(p, str) or p not in record["files"] for p in required):
        raise TaskError("Checkpoint omits required contract, artifact, or evidence hashes.")
    if git_head(root) != record.get("git_head"):
        raise TaskError("Stale checkpoint: candidate HEAD changed. Inspect and re-verify affected claims.")
    for path, expected in record["files"].items():
        if fingerprint(root, path) != expected:
            raise TaskError(f"Stale checkpoint: {path} changed. Inspect and re-verify affected claims.")
    operations = operation_states(root, task)
    if operations != record["operations"]:
        raise TaskError("External-operation state changed since the checkpoint; reconcile and record a new checkpoint.")
    if exhausted or record["status"] in {"stopped", "blocked"}:
        raise TaskError("Execution is stopped or blocked. Preserve evidence and obtain explicit reauthorization before a new window.")
    rows = acceptance_rows(safe_path(root, record["acceptance"], required=True).read_text(encoding="utf-8"))
    if phase == "complete":
        if record["status"] not in {"ready-for-review", "completed"} or not record["evidence"]:
            raise TaskError("Completion requires ready-for-review/completed state and saved evidence files.")
        text = safe_path(root, contract, required=True).read_text(encoding="utf-8")
        declarations = re.findall(r"(?m)^- Optional acceptance IDs: (.+)$", text)
        if len(declarations) != 1:
            raise TaskError("Declare optional acceptance IDs exactly once in TASK.md (use none when all are required).")
        optional = set() if declarations[0] == "none" else {s.strip() for s in declarations[0].split(",")}
        if not optional <= {row["ID"] for row in rows}:
            raise TaskError("Optional acceptance declaration contains an unknown ID.")
        for row in rows:
            allowed = {"verified", "inferred", "unknown"} if row["ID"] in optional else {"verified"}
            if row["Verdict"] not in allowed:
                raise TaskError(f"Acceptance {row['ID']} blocks completion: {row['Verdict']}.")
        if "pending" in operations.values():
            raise TaskError("An external write has an unresolved outcome; completion is blocked.")
    if (checkpoint_paths(root, task) != history or git_head(root) != record["git_head"] or
            any(fingerprint(root, p) != expected for p, expected in record["files"].items())):
        raise TaskError("Checkpoint or HEAD changed during validation; inspect again.")
    return ("Mechanical checkpoint checks passed for declared files only. "
            "Semantic evidence review and mode-specific publication approval are still required.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    subs = parser.add_subparsers(dest="command", required=True)
    create = subs.add_parser("create-task")
    create.add_argument("task")
    create.add_argument("title", nargs="?")
    create.add_argument("--no-issue", action="store_true")
    issue = subs.add_parser("create-issue")
    issue.add_argument("task")
    issue.add_argument("title", nargs="?")
    issue.add_argument("body_file", nargs="?")
    issue.add_argument("--reconcile-only", action="store_true")
    issue.add_argument("--retry-confirmed-absent", dest="retry_reason")
    checkpoint = subs.add_parser("checkpoint")
    checkpoint.add_argument("task")
    checkpoint.add_argument("--artifact", action="append", required=True)
    checkpoint.add_argument("--evidence", action="append", default=[])
    checkpoint.add_argument("--acceptance")
    checkpoint.add_argument("--next-action", required=True)
    checkpoint.add_argument("--status", choices=["in-progress", "stopped", "blocked", "ready-for-review", "completed"], default="in-progress")
    checkpoint.add_argument("--deadline")
    checkpoint.add_argument("--failed-epochs", type=int)
    checkpoint.add_argument("--max-failed-epochs", type=int)
    checkpoint.add_argument("--reauthorize-window", help="Explicit human authorization reason; never infer this permission.")
    validate = subs.add_parser("validate")
    validate.add_argument("task")
    validate.add_argument("--phase", choices=["resume", "complete"], default="resume")
    args = parser.parse_args(argv)
    try:
        root = Path(args.root).resolve(strict=True)
        if not root.is_dir():
            raise TaskError("Project root must be a directory.")
        if args.command == "create-task":
            result = create_task(root, args.task, args.title, args.no_issue)
        elif args.command == "create-issue":
            result = create_issue(root, args.task, args.title, args.body_file, args.reconcile_only, args.retry_reason)
        elif args.command == "checkpoint":
            result = record_checkpoint(root, args)
        else:
            result = validate_checkpoint(root, args.task, args.phase)
        print(result)
        return 0
    except (TaskError, OSError, UnicodeError) as exc:
        print(f"Task execution blocked: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    if sys.version_info < (3, 9):
        print("Python 3.9+ is required; no software was installed.", file=sys.stderr)
        sys.exit(2)
    sys.exit(main())
