"""Actual MODEL_TO_ACTION apphost/Blender/browser integration on owned fixtures.

Human receipts and fixture promotion are synthetic test assertions only.
No installation, provider, external artwork or production asset promotion.
"""
from pathlib import Path
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT / '.opencaw/.cache/tasks/model-to-action'
BLENDER = Path(os.environ.get('BLENDER_EXE') or shutil.which('blender') or 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe')
APPHOST = ROOT / 'commands/lib/model-to-action/bin/Debug/net10.0/ModelToAction.exe'
DLL = APPHOST.with_suffix('.dll')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if not BLENDER.is_file() or not DLL.is_file():
        raise SystemExit('BLOCKED: existing Blender4.5 and built action apphost required; no software installed')
    evidence = TASK / 'evidence'
    evidence.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='a-', dir=evidence))
    project = work / 'p'
    calls, checks = [], []

    def check(value, message):
        assert value, message
        checks.append(message)
        print('PASS ACTUAL:', message, flush=True)

    def invoke(args, label, expected=True, timeout=180):
        result = subprocess.run([str(item) for item in args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        log = work / (str(len(calls)).zfill(3) + '-' + label + '.log')
        log.write_bytes(result.stdout)
        calls.append({'args': [str(item) for item in args], 'exitCode': result.returncode, 'log': str(log.relative_to(ROOT))})
        (work / 'commands.json').write_text(json.dumps(calls, indent=2) + '\n', encoding='utf-8')
        assert (result.returncode == 0) == expected, label + ' unexpected exit ' + str(result.returncode) + '\n' + result.stdout.decode(errors='replace')[-6000:]
        return result

    def write(relative, value):
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
        return relative

    invoke([BLENDER, '--background', '--factory-startup', '--disable-autoexec', '--python-exit-code', '1', '--python',
            ROOT / 'tests/fixtures/model-action/create_assets.py', '--', '--output', project], 'original-source-fixture')
    shutil.copyfile(ROOT / 'STYLE.md', project / 'STYLE.md')
    invoke(['node', ROOT / 'commands/lib/engine-contract.cjs', 'generate', project, '--inline', 'THREEJS'], 'engine')
    context = json.loads(invoke(['node', ROOT / 'commands/lib/engine-contract.cjs', 'resolve', project], 'resolve-engine').stdout)
    source_path = project / 'source/motion-package.json'
    source = json.loads(source_path.read_text(encoding='utf-8'))
    source['engine'] = context
    source_path.write_text(json.dumps(source, indent=2) + '\n', encoding='utf-8')
    fixture_task = project / '.opencaw/.cache/tasks/fixture/TASK.md'
    fixture_task.parent.mkdir(parents=True, exist_ok=True)
    fixture_task.write_text('# Controlled action fixture\n\nOriginal engineering assets only. All human receipts are synthetic test assertions.\n', encoding='utf-8')
    review = {'schemaVersion': 1, 'kind': 'source-motion', 'decision': 'approved', 'human': True,
              'reviewer': 'fixture-source-reviewer', 'reason': 'SYNTHETIC TEST ONLY; actual Blender-authored original source, no production human approval',
              'rights': {'authorized': True, 'license': 'Original controlled OpenCaw engineering model and motion clips'},
              'motionPackageSha256': sha(source_path), 'modelSha256': source['model']['sha256'], 'rigId': source['rig']['id'],
              'clips': [{'id': clip['id'], 'motionSha256': clip['motionSha256']} for clip in source['clips']]}
    source_review = write('.opencaw/.cache/tasks/fixture/source-review.json', review)
    executable = [APPHOST] if os.name == 'nt' and APPHOST.is_file() else ['dotnet', DLL]

    def command(operation, manifest=None, *extra, expected=True):
        args = [*executable, operation, '--root', project, '--baseline-root', ROOT]
        if manifest:
            args += ['--manifest', manifest]
        return invoke([*args, *extra], operation, expected)

    def initialize(asset, recipe='action-recipe.json', receipt=source_review, expected=True):
        command('init', None, '--task', 'fixture', '--asset', asset, '--version', 'v1', '--actor', 'fixture-builder',
                '--motion-package', 'source/motion-package.json', '--recipe', recipe, '--source-review', receipt,
                '--blender', BLENDER, expected=expected)
        return '.opencaw/.cache/tasks/fixture/model-to-action/' + asset + '/v1/manifest.json'

    def state(manifest):
        return json.loads((project / manifest).read_text(encoding='utf-8'))

    def artifact(manifest, stage, key):
        return state(manifest)['stages'][stage]['artifacts'][key]

    def approve(manifest, kind, runtime=None):
        current = json.loads(command('status', manifest).stdout)
        reviewer = 'fixture-independent' if kind == 'independent' else 'fixture-human'
        receipt = {'kind': kind, 'decision': 'approved', 'human': True, 'reviewer': reviewer,
                   'reason': 'SYNTHETIC CONTROLLED TEST ASSERTION; no production acceptance',
                   'fingerprint': current['approvalFingerprints'][kind]}
        if runtime:
            receipt['runtime'] = runtime
        path = write('.opencaw/.cache/tasks/fixture/' + kind + '-review.json', receipt)
        command('record', manifest, '--kind', kind, '--reviewer', reviewer, '--evidence', path)

    denied = copy.deepcopy(review)
    denied['rights']['authorized'] = False
    denied_review = write('.opencaw/.cache/tasks/fixture/denied-review.json', denied)
    initialize('denied', receipt=denied_review, expected=False)
    check(not (project / '.art-staging/model-to-action/denied').exists(), 'unauthorized source rights cause no production staging')
    missing = json.loads((project / 'action-recipe.json').read_text())
    missing['actions'][0]['steps'][0]['clip'] = 'missing-actual-clip'
    missing_recipe = write('missing-recipe.json', missing)
    initialize('missing', recipe=missing_recipe, expected=False)
    check(not (project / '.art-staging/model-to-action/missing').exists(), 'missing source clip fails before production staging')

    manifest = initialize('actor')
    source_hash = sha(project / source['model']['path'])
    command('doctor', manifest)
    command('export', manifest, expected=False)
    check('export' not in state(manifest)['stages'], 'stage ordering rejects export before composition')
    for stage in ('inspect', 'compose', 'export', 'review'):
        command(stage, manifest)
    command('validate', manifest)
    package_path = project / artifact(manifest, 'export', 'package')
    package = json.loads(package_path.read_text(encoding='utf-8'))
    check(package['schemaVersion'] == 'opencaw-action-package/v1', 'actual export produces profiled action package')
    check({action['id'] for action in package['actions']} == {'dance-pattern', 'chained-combo', 'charge-cast'}, 'all three requested action families have actual composite clips')
    check(all(len(action['steps']) > 1 and action['motionSha256'] for action in package['actions']), 'compound actions preserve ordered steps and actual sampled output hashes')
    check(package['engine']['effectiveEngine'] == 'THREEJS', 'action package consumes canonical selected engine')
    check(package['sourceMotion']['rights'] == review['rights'] and package['sourceMotion']['sourceReviewSha256'] == sha(project / source_review), 'standalone action export preserves exact source rights and review ancestry')
    check(sha(project / source['model']['path']) == source_hash, 'actual composition leaves original motion GLB immutable')
    for key in ('model', 'source', 'motion'):
        check(sha(project / package[key]['path']) == package[key]['sha256'], 'export binds actual ' + key + ' bytes')
    native_review = json.loads((project / artifact(manifest, 'review', 'reviewReport')).read_text(encoding='utf-8'))
    check(len(native_review['packets']) == 3 and sum(len(packet['frames']) for packet in native_review['packets']) > 6, 'technical review covers complete actual sequences and camera/time boundaries')
    check(package['verification']['status'] == 'pending', 'native sequence export does not manufacture runtime acceptance')
    command('promote', manifest, '--destination', 'assets/models/actions', expected=False)
    check(not (project / 'assets/models/actions').exists(), 'reviewed source alone cannot promote composed actions')

    # Real freshness guards reject changed inputs without adding producer attempts.
    history = len(state(manifest)['history'])
    recipe_path = project / 'action-recipe.json'
    original_recipe = recipe_path.read_bytes()
    recipe_path.write_bytes(original_recipe + b'\n')
    command('validate', manifest, expected=False)
    recipe_path.write_bytes(original_recipe)
    check(len(state(manifest)['history']) == history, 'changed recipe is rejected without production state writes')
    engine_path = project / 'ENGINE.md'
    original_engine = engine_path.read_bytes()
    invoke(['node', ROOT / 'commands/lib/engine-contract.cjs', 'generate', project, '--inline', 'UNITY'], 'conflicting-engine')
    command('validate', manifest, expected=False)
    engine_path.write_bytes(original_engine)
    command('validate', manifest)
    check(len(state(manifest)['history']) == history, 'changed engine is rejected before another native producer attempt')

    output = project / '.opencaw/.cache/tasks/fixture/action-browser'
    args = [sys.executable, ROOT / 'tests/test-model-action-engine.py', '--project-root', project, '--package', package_path, '--output', output]
    browser = subprocess.run([str(value) for value in args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    (work / 'browser.log').write_bytes(browser.stdout)
    assert browser.returncode in (0, 77), browser.stdout.decode(errors='replace')[-6000:]
    actual_browser = browser.returncode == 0
    if not actual_browser and os.environ.get('OPENCAW_REQUIRE_ACTION_BROWSER') == '1':
        raise AssertionError('Actual action browser acceptance required; prerequisites unavailable')
    if actual_browser:
        observed = json.loads((output / 'engine-evidence.json').read_text(encoding='utf-8'))
        check(observed['status'] == 'passed', 'actual browser verifies composite poses, attached effects and fixed-target presentation')
        approve(manifest, 'action')
        command('promote', manifest, '--destination', 'assets/models/actions', expected=False)
        approve(manifest, 'independent')
        runtime = {'status': 'passed', 'engine': 'THREEJS', 'modelSha256': package['model']['sha256'],
                   'packageSha256': sha(package_path), 'evidence': observed['evidence']}
        approve(manifest, 'human', runtime)
        command('promote', manifest, '--destination', 'assets/models/actions')
        promoted = json.loads((project / 'assets/models/actions/action-package.json').read_text(encoding='utf-8'))
        check(promoted['model']['path'].startswith('assets/models/actions/') and sha(project / promoted['model']['path']) == promoted['model']['sha256'], 'synthetic fixture promotion rebinds and preserves actual composite model bytes')
        command('promote', manifest, '--destination', 'assets/models/actions', expected=False)
        check(True, 'fixture promotion cannot overwrite existing reviewed output')
    else:
        print('BLOCKED: actual browser unavailable; no automatic installation or approval fabricated', flush=True)

    result = {'status': 'pass', 'checks': len(checks), 'actualCli': True, 'actualBlender': True,
              'actualBrowser': actual_browser, 'humanAssertions': 'synthetic-test-only', 'productionPromotion': False,
              'project': str(project.relative_to(ROOT)), 'assertions': checks}
    (work / 'verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    (evidence / 'native-action-latest.txt').write_text(str(work) + '\n', encoding='utf-8')
    print('PASS:', len(checks), 'actual action CLI/Blender checks; actual browser:', actual_browser)
    print('Synthetic human assertions/fixture promotion only. Evidence:', work)


if __name__ == '__main__':
    main()
