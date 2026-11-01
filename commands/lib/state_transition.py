#!/usr/bin/env python3
"""Inspect or prepare a persistent local-state fence. Never adopts old approvals."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys

LEGACY = '.opencaw/.cache'
CACHE = '.hephaera/.cache'
MARKER = CACHE + '/STATE_TRANSITION.json'
BOOTSTRAP = re.compile(r'<!--\s*OPENCAW_BOOTSTRAP_(?:START|END)\s*-->')


class TransitionError(Exception):
    pass


def linked(observed):
    return stat.S_ISLNK(observed.st_mode) or bool(getattr(observed, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400))


def root_path(value):
    if not str(value) or re.search(r'[\x00-\x1f]', str(value)):
        raise TransitionError('An explicit project root is required for state transition checks.')
    value = str(value)
    if os.name == 'nt':
        value = re.sub(r'^/(?:mnt/)?([a-zA-Z])/', lambda match: match[1].upper() + ':/', value)
    root = Path(value).absolute()
    if linked(root.lstat()) or not root.is_dir():
        raise TransitionError('State transition root must be a real directory.')
    return root


def entry(root, relative, kind):
    current = root
    parts = relative.split('/')
    for index, part in enumerate(parts):
        current = current / part
        try:
            observed = current.lstat()
        except FileNotFoundError:
            return None
        if linked(observed):
            raise TransitionError('Symlink state transition paths are not allowed.')
        directory = index < len(parts) - 1 or kind == 'directory'
        if directory and not stat.S_ISDIR(observed.st_mode):
            raise TransitionError('State transition directory collides with another file type.')
        if not directory and not stat.S_ISREG(observed.st_mode):
            raise TransitionError('State transition metadata must be a regular file.')
    return current


def inspect(value):
    root = root_path(value)
    legacy = entry(root, LEGACY, 'directory')
    marker = entry(root, MARKER, 'file')
    agents = entry(root, 'AGENTS.md', 'file')
    if agents and agents.stat().st_size > 1048576:
        raise TransitionError('AGENTS metadata exceeds the state transition inspection bound.')
    bootstrap = bool(agents and BOOTSTRAP.search(agents.read_text(encoding='utf-8')))
    return dict(schemaVersion='hephaera-state-transition-inspection/v1', legacyCache=LEGACY,
                canonicalCache=CACHE, marker=MARKER, legacyPresent=bool(legacy), markerPresent=bool(marker),
                legacyBootstrap=bootstrap, productionBlocked=bool(legacy or marker or bootstrap),
                automaticMigration=False,
                notes='Read-only metadata discovery; no receipts, approvals, journals or private media were opened or rebound.')


def require_issue_writes_allowed(value, task):
    if not isinstance(task, str) or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', task):
        raise TransitionError('A safe task identity is required for issue transition checks.')
    root = root_path(value)
    state = inspect(root)
    if state['markerPresent'] or state['legacyBootstrap'] or entry(root, LEGACY + '/tasks/' + task, 'directory'):
        raise TransitionError('State transition blocks this task issue write; preserve and reconcile its original operation identity before creating or retrying an issue.')
    return state


def require_local_state_prepared(value):
    state = inspect(value)
    if (state['legacyPresent'] or state['legacyBootstrap']) and not state['markerPresent']:
        raise TransitionError('Prepare the state transition explicitly before creating canonical local state: state-transition.sh prepare.')
    return state


def prepare(value):
    root = root_path(value)
    state = inspect(root)
    if state['markerPresent'] or not state['productionBlocked']:
        return dict(state, prepared=state['markerPresent'])
    # Only this explicit operation creates the fence. Discovery remains read-only.
    entry(root, CACHE, 'directory')
    destination = root / MARKER
    destination.parent.mkdir(parents=True, exist_ok=True)
    entry(root, CACHE, 'directory')
    payload = dict(schemaVersion='hephaera-state-transition/v1', status='prepared',
                   legacyInstall=LEGACY.split('/')[0], legacyCache=LEGACY, canonicalCache=CACHE,
                   productionBlocked=True, automaticApprovalMigration=False,
                   reason='Legacy bytes and original operation/approval identities are preserved; no adoption or execution readiness is granted.')
    try:
        with destination.open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(payload, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        pass
    return dict(inspect(root), prepared=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['inspect', 'prepare'])
    parser.add_argument('--root', required=True)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(inspect(args.root) if args.operation == 'inspect' else prepare(args.root), indent=2))
        return 0
    except (TransitionError, OSError, UnicodeError) as error:
        print('State transition blocked: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    if sys.version_info < (3, 9):
        print('Python 3.9+ is required; no software was installed.', file=sys.stderr)
        sys.exit(2)
    sys.exit(main())
