"""Real local Three.js/browser verification of exported MODEL_TO_ACTION packages.

Uses existing test dependencies and an installed browser. Installs nothing.
"""
from pathlib import Path
import argparse
import datetime
import json
import os
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = ROOT / '.opencaw/.cache/tasks/model-to-animation-design/dependency-audit/browser-fixture/node_modules'


def confined(value, label, exists=True):
    candidate = Path(value).absolute()
    if not candidate.is_relative_to(ROOT):
        raise ValueError(label + ' must remain repository-local')
    current = ROOT
    for part in candidate.relative_to(ROOT).parts:
        current = current / part
        if current.is_symlink() or (hasattr(current, 'is_junction') and current.is_junction()):
            raise ValueError(label + ' cannot traverse links/junctions')
    result = candidate.resolve(strict=exists)
    if not result.is_relative_to(ROOT):
        raise ValueError(label + ' escapes repository')
    return result


def browser_path(explicit):
    if explicit:
        return str(Path(explicit).resolve(strict=True))
    if os.name == 'nt':
        import winreg
        for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            for name in ('msedge.exe', 'chrome.exe'):
                try:
                    with winreg.OpenKey(hive, 'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\' + name) as key:
                        value, _ = winreg.QueryValueEx(key, None)
                    if Path(value).is_file():
                        return value
                except OSError:
                    pass
    raise FileNotFoundError('Existing Edge/Chrome unavailable; configure --browser-executable. No browser downloaded.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root', required=True)
    parser.add_argument('--package', action='append', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--dependencies', default=str(DEPENDENCIES))
    parser.add_argument('--browser-executable')
    args = parser.parse_args()
    project = confined(args.project_root, 'project root')
    packages = [confined(item, 'action package') for item in args.package]
    output = confined(args.output, 'evidence output', False)
    if output.exists() and any(output.iterdir()):
        raise ValueError('Evidence attempt already exists; choose an empty new output')
    output.mkdir(parents=True, exist_ok=True)
    try:
        dependencies = confined(args.dependencies, 'test dependencies')
        executable = browser_path(args.browser_executable)
        for package in ('three', 'playwright-core'):
            if not (dependencies / package / 'package.json').is_file():
                raise FileNotFoundError('Existing pinned ' + package + ' unavailable; no install attempted')
    except FileNotFoundError as error:
        (output / 'blocked.json').write_text(json.dumps({'status': 'blocked', 'reason': str(error), 'actualBrowser': False}) + '\n', encoding='utf-8')
        print('BLOCKED:', error)
        return 77
    resolved = subprocess.run(['node', str(ROOT / 'commands/lib/engine-contract.cjs'), 'resolve', str(project), '--json'], cwd=ROOT, capture_output=True, text=True, timeout=30)
    if resolved.returncode:
        raise ValueError('Canonical engine resolution failed: ' + resolved.stderr)
    engine = json.loads(resolved.stdout)
    if engine['effectiveEngine'] != 'THREEJS':
        raise ValueError('Actual fixture requires effective THREEJS; ENGINE.md is unchanged')
    config = {'schemaVersion': 1, 'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'projectRoot': str(project), 'packages': [str(item) for item in packages], 'output': str(output), 'dependencies': str(dependencies), 'browserExecutable': executable, 'engineSelection': engine}
    config_file = output / 'browser-config.json'
    config_file.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    command = ['node', str(ROOT / 'tests/test-model-action-engine.cjs'), '--browser', '--config', str(config_file)]
    with (output / 'browser.log').open('wb') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == 'nt' else 0,
                                   start_new_session=os.name != 'nt')
        try:
            process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=log, stderr=subprocess.STDOUT, check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=15)
            raise
    print((output / 'browser.log').read_text(encoding='utf-8', errors='replace')[-6000:])
    if process.returncode:
        return process.returncode
    receipt = json.loads((output / 'engine-evidence.json').read_text(encoding='utf-8'))
    if receipt.get('status') != 'passed' or len(receipt.get('evidence', [])) != 3:
        raise ValueError('Incomplete actual action runtime evidence')
    print('Engine evidence:', output / 'engine-evidence.json')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
