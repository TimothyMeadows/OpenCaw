"""Actual local Three.js/browser verification of already-produced motion packages.

No package/browser install, model generation, provider call or asset promotion.
Packages and fixture projects must remain under the active repository root.
"""
from pathlib import Path
import argparse
import datetime
import json
import os
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT / ".opencaw/.cache/tasks/model-to-animation-design"


def confined(value, label):
    result = Path(value).resolve(strict=True)
    if not result.is_relative_to(ROOT) or result.is_symlink():
        raise ValueError(label + " must be a real repository-local path")
    return result


def browser_path(explicit):
    if explicit:
        return str(Path(explicit).resolve(strict=True))
    if os.name == "nt":
        import winreg
        for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            for name in ("msedge.exe", "chrome.exe"):
                try:
                    with winreg.OpenKey(hive, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + name) as key:
                        value, _ = winreg.QueryValueEx(key, None)
                    if Path(value).is_file():
                        return value
                except OSError:
                    pass
    raise FileNotFoundError("Existing Edge/Chrome unavailable; configure --browser-executable. No browser downloaded.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--package", action="append", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--dependencies", default=str(TASK / "dependency-audit/browser-fixture/node_modules"))
    parser.add_argument("--browser-executable")
    args = parser.parse_args()
    project = confined(args.project_root, "project root")
    packages = [confined(item, "package") for item in args.package]
    dependencies = Path(args.dependencies).resolve()
    output = Path(args.output).resolve()
    if not dependencies.is_relative_to(ROOT) or not output.is_relative_to(ROOT):
        raise ValueError("Dependency/evidence output must remain repository-local")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Evidence output already contains an attempt; use a new directory")
    output.mkdir(parents=True, exist_ok=True)
    try:
        dependencies = confined(dependencies, "dependencies")
        executable = browser_path(args.browser_executable)
        for package in ("three", "playwright-core"):
            if not (dependencies / package / "package.json").is_file():
                raise FileNotFoundError("Existing pinned " + package + " dependency is unavailable; no install attempted.")
    except FileNotFoundError as error:
        (output / "blocked.json").write_text(json.dumps({"status": "blocked", "reason": str(error), "actualBrowser": False}) + "\n", encoding="utf-8")
        print("BLOCKED:", error)
        return 77
    selection = subprocess.run(["node", str(ROOT / "commands/lib/engine-contract.cjs"), "resolve", str(project), "--json"], cwd=ROOT, capture_output=True, text=True, timeout=30)
    if selection.returncode:
        raise ValueError("Canonical engine resolution failed: " + selection.stderr)
    engine = json.loads(selection.stdout)
    if engine["effectiveEngine"] != "THREEJS":
        raise ValueError("Actual Three.js fixture requires effective THREEJS; ENGINE.md is unchanged")
    config = {"schemaVersion": 1, "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(), "projectRoot": str(project), "packages": [str(item) for item in packages], "output": str(output), "dependencies": str(dependencies), "browserExecutable": executable, "engineSelection": engine}
    config_file = output / "browser-config.json"
    config_file.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    command = ["node", str(ROOT / "tests/test-model-animation-engine.cjs"), "--browser", "--config", str(config_file)]
    with (output / "browser.log").open("wb") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == "nt" else 0,
                                   start_new_session=os.name != "nt")
        try:
            process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=log, stderr=subprocess.STDOUT, check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=15)
            raise
    print((output / "browser.log").read_text(encoding="utf-8", errors="replace")[-6000:])
    if process.returncode:
        return process.returncode
    receipt = json.loads((output / "engine-evidence.json").read_text(encoding="utf-8"))
    if receipt.get("status") != "passed" or len(receipt.get("evidence", [])) != 3:
        raise ValueError("Incomplete actual engine evidence")
    print("Engine evidence:", output / "engine-evidence.json")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
