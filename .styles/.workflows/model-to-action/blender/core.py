"""Fixed action batch guards and scene primitives, adapted from OpenCaw motion core.

Internal reuse: model-to-animation/blender/core.py helpers are adapted locally so
the action batch has a complete separately pinned bundle and no dynamic imports.
These lifetime/file guards are not an operating-system sandbox.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
from urllib.parse import urlparse

sys.dont_write_bytecode = True


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def finite(value, label, minimum=None, maximum=None, integer=False):
    if type(value) not in (int, float) or not math.isfinite(value) or integer and type(value) is not int:
        raise ValueError(label + ' must be a finite ' + ('integer' if integer else 'number'))
    if minimum is not None and value < minimum or maximum is not None and value > maximum:
        raise ValueError(label + ' exceeds its bounds')
    return value


def vector(value, count, label):
    if not isinstance(value, list) or len(value) != count:
        raise ValueError(label + ' requires ' + str(count) + ' values')
    return [finite(item, label) for item in value]


def text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(label + ' requires nonempty text')
    return value


def safe_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', value) or value == '..':
        raise ValueError('Unsafe semantic identity')
    return value


def no_excluded_providers(value, key=''):
    providers = {'provider','vendor','tool','authoringtool','sourceprovider','sourcetool','sourceorigin','createdwith','generator'}
    origins = {'source','sourceuri','sourceurl','url','origin'}
    products = r'(adobe|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator)'
    if isinstance(value, dict):
        for name, item in value.items():
            no_excluded_providers(item, name.replace('-', '').replace('_', '').lower())
    elif isinstance(value, list):
        for item in value:
            no_excluded_providers(item, key)
    elif isinstance(value, str):
        product = key in providers and re.search(r'\b' + products + r'\b', value, re.I)
        declared = key in origins and re.fullmatch(r'\s*(?:adobe\s+)?' + products + r'\s*', value, re.I)
        host = urlparse(value).hostname if key in origins else None
        vendor = host and re.search(r'(^|\.)(adobe\.com|adobe\.io|mixamo\.com|substance3d\.com)$', host, re.I)
        if product or declared or vendor:
            raise ValueError('Excluded authoring/provider provenance')


def confined(root, value):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value or value.startswith('/'):
        raise ValueError('Expected a normalized repository-relative path')
    if any(part in ('', '.', '..') for part in value.split('/')):
        raise ValueError('Expected a normalized repository-relative path')
    candidate = root / value
    cursor = candidate
    while cursor != root:
        if cursor.exists() or cursor.is_symlink():
            attributes = getattr(cursor.lstat(), 'st_file_attributes', 0)
            if cursor.is_symlink() or attributes & 0x400:
                raise ValueError('Links and junctions are forbidden')
        cursor = cursor.parent
    candidate.resolve().relative_to(root)
    return candidate


def relative(root, value):
    return Path(value).relative_to(root).as_posix()


def save_json(path, value):
    if path.exists():
        raise ValueError('Immutable output already exists: ' + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def read_glb(path, maximum=512 * 1024 * 1024):
    size = path.stat().st_size
    if size < 20 or size > maximum:
        raise ValueError('Missing or oversized GLB')
    binary, document = None, None
    with path.open('rb') as stream:
        if struct.unpack('<III', stream.read(12)) != (0x46546C67, 2, size):
            raise ValueError('Invalid GLB container')
        while stream.tell() < size:
            header = stream.read(8)
            if len(header) != 8:
                raise ValueError('Truncated GLB chunk')
            count, kind = struct.unpack('<II', header)
            if count % 4 or stream.tell() + count > size:
                raise ValueError('Invalid GLB chunk length')
            data = stream.read(count)
            if kind == 0x4E4F534A:
                if document is not None or len(data) > 32 * 1024 * 1024:
                    raise ValueError('Ambiguous GLB document')
                document = json.loads(data.decode('utf-8').rstrip(' \0'))
            elif kind == 0x004E4942:
                if binary is not None:
                    raise ValueError('Ambiguous GLB binary')
                binary = data
    if not isinstance(document, dict) or document.get('asset', {}).get('version') != '2.0' or not document.get('meshes'):
        raise ValueError('GLB has no valid mesh document')
    for item in document.get('buffers', []) + document.get('images', []):
        if 'uri' in item and not str(item['uri']).startswith('data:'):
            raise ValueError('External GLB dependencies are unsupported')
    no_excluded_providers(document.get('asset', {}))
    return document, binary


def objects():
    import bpy
    return [obj for obj in bpy.context.scene.objects if obj.type not in ('CAMERA', 'LIGHT') and not obj.get('opencaw_cue_proxy')]


def meshes():
    return [obj for obj in objects() if obj.type == 'MESH']


def armatures():
    return [obj for obj in objects() if obj.type == 'ARMATURE']


def all_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            if strip.type != 'KEYFRAME':
                raise ValueError('Unsupported action strip')
            for bag in strip.channelbags:
                yield from bag.fcurves


def load_scene(source, fps):
    import bpy
    if source.suffix.lower() == '.blend':
        bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
        if bpy.context.scene.render.fps != fps:
            raise ValueError('Working blend FPS differs from action plan')
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=str(source), loglevel=0)
        helpers = {bone.custom_shape for obj in bpy.context.scene.objects if obj.type == 'ARMATURE' for bone in obj.pose.bones if bone.custom_shape}
        for obj in bpy.context.scene.objects:
            if obj.type == 'ARMATURE':
                for bone in obj.pose.bones:
                    bone.custom_shape = None
        for helper in helpers:
            bpy.data.objects.remove(helper, do_unlink=True)
    for obj in bpy.data.objects:
        if obj.library or obj.is_instancer or obj.animation_data and obj.animation_data.drivers:
            raise ValueError('Linked, instanced or executable source dependencies are unsupported')
        if obj.data and getattr(obj.data, 'shape_keys', None) and obj.data.shape_keys.animation_data:
            raise ValueError('Animated shape keys require an explicitly implemented action authoring path')
    for image in bpy.data.images:
        if image.source == 'FILE' and image.packed_file is None:
            raise ValueError('Unpacked external image dependency')
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.view_layer.update()


def inventory(profile):
    import bpy
    from mathutils import Vector
    triangles = sum(sum(len(poly.vertices) - 2 for poly in obj.data.polygons) for obj in meshes())
    points = [obj.matrix_world @ Vector(corner) for obj in meshes() for corner in obj.bound_box]
    if not points or triangles < 1:
        raise ValueError('No actual model geometry')
    for point in points:
        vector(list(point), 3, 'Model bounds')
    bones = sum(len(rig.data.bones) for rig in armatures())
    if profile == 'skinned':
        if len(armatures()) != 1 or not bones:
            raise ValueError('Skinned source requires exactly one actual rig')
        for obj in meshes():
            rigs = [mod.object for mod in obj.modifiers if mod.type == 'ARMATURE']
            if rigs != armatures():
                raise ValueError('Skinned source mesh has missing or competing rig ownership')
            names = {bone.name for bone in armatures()[0].data.bones if bone.use_deform}
            groups = {group.index: group.name for group in obj.vertex_groups}
            for vertex in obj.data.vertices:
                weights = [entry.weight for entry in vertex.groups if groups.get(entry.group) in names and entry.weight > 1e-8]
                if not weights or abs(sum(weights) - 1) > .001 or any(not math.isfinite(value) for value in weights):
                    raise ValueError('Invalid or missing source skin weights')
    elif bones:
        raise ValueError('Rigid/articulated source cannot silently carry an unrelated skin rig')
    return {'triangles': triangles, 'bones': bones, 'meshes': len(meshes()),
            'materials': len({mat.name for obj in meshes() for mat in obj.data.materials if mat}),
            'bounds': {'min': [min(point[axis] for point in points) for axis in range(3)], 'max': [max(point[axis] for point in points) for axis in range(3)]}}


def save_blend(root, output):
    import bpy
    path = output / 'asset.blend'
    if path.exists():
        raise ValueError('Immutable editable output already exists')
    for image in bpy.data.images:
        if image.type not in ('RENDER_RESULT', 'VIEWER') and image.packed_file is None:
            image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False)
    return relative(root, path)


def load_job():
    import bpy
    if bpy.app.version[:2] != (4, 5):
        raise ValueError('Existing Blender4.5 LTS required')
    parser = argparse.ArgumentParser()
    parser.add_argument('--job', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    path = Path(args.job).absolute()
    if not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('Missing or oversized fixed action job')
    job = json.loads(path.read_text(encoding='utf-8-sig'))
    allowed = {'schemaVersion','root','operation','input','outputDir','result','asset','version','profile','motionPackage','plan','review'}
    if set(job) - allowed or job.get('schemaVersion') != 1 or job.get('operation') not in ('inspect','compose','export','review'):
        raise ValueError('Unsupported native action job')
    safe_id(job.get('asset')); safe_id(job.get('version'))
    root = Path(text(job.get('root'), 'Project root')).absolute()
    if not root.is_dir() or root.is_symlink():
        raise ValueError('Project root is unavailable')
    prefix = '.art-staging/model-to-action/' + job['asset'] + '/' + job['version'] + '/'
    if not str(job.get('outputDir', '')).startswith(prefix + 'attempts/'):
        raise ValueError('Action output violates asset-local staging')
    output, result = confined(root, job['outputDir']), confined(root, job['result'])
    if result != output / 'result.json' or output == root:
        raise ValueError('Result must remain in its immutable attempt')
    bootstrap = {'scripts','job.json','process.log','blender-version.log','version.log','plan.json','compiled-plan.json','action-plan.json'}
    if output.exists() and any(item.name not in bootstrap for item in output.iterdir()):
        raise ValueError('Use a new immutable action attempt')
    if result.exists() or (output / 'report.json').exists():
        raise ValueError('Action output already exists')
    source = confined(root, job['input'])
    if not source.is_file() or source.suffix.lower() not in ('.glb', '.blend'):
        raise ValueError('Action source must be a real GLB or prior working blend')
    if source.suffix.lower() == '.blend' and not job['input'].startswith(prefix + 'attempts/'):
        raise ValueError('Only this asset\'s prior fixed working blend may be opened')
    if job['operation'] in ('inspect','compose','review') and source.suffix.lower() != '.glb':
        raise ValueError('This action stage requires an actual GLB')
    if job['operation'] == 'export' and source.suffix.lower() != '.blend':
        raise ValueError('Export requires a composed working blend')
    plan = job.get('plan'); motion = job.get('motionPackage')
    if not isinstance(plan, dict) or not isinstance(motion, dict) or motion.get('schemaVersion') != 'opencaw-motion-package/v1':
        raise ValueError('Missing compiled plan or reviewed motion metadata')
    if job.get('profile') not in ('skinned','articulated','rigid') or motion.get('profile') != job['profile']:
        raise ValueError('Action profile disagrees with source motion')
    no_excluded_providers(motion); no_excluded_providers(plan)
    finite(plan.get('fps'), 'Bake FPS', 1, 120, True)
    if not isinstance(plan.get('rig'), dict) or plan['rig'] != motion.get('rig'):
        raise ValueError('Compiled plan must retain reviewed source rig identity')
    budget = plan.get('budgets')
    limits = {'maxActions':64,'maxStepsPerAction':256,'maxExpandedSteps':2048,'maxActionSeconds':3600,'maxEffects':256,'maxParticles':65536,'maxFrames':1000000,'maxReviewFrames':10000,'maxRuntimeBytes':1073741824,'timeoutSeconds':86400,'maxLogBytes':1073741824,'maxAttempts':100}
    if not isinstance(budget, dict):
        raise ValueError('Missing action budgets')
    for key, maximum in limits.items():
        finite(budget.get(key), key, 1024 if key in ('maxRuntimeBytes','maxLogBytes') else 1, maximum, key != 'maxActionSeconds')
    finite(budget.get('maxVerificationBytes', 8 * 1024**3), 'maxVerificationBytes', 1024, 64 * 1024**3, True)
    actions = plan.get('actions')
    if not isinstance(actions, list) or not actions or len(actions) > budget['maxActions']:
        raise ValueError('Missing or excessive action set')
    ids = [safe_id(action.get('id')) for action in actions]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate action identity')
    frames = 0
    anchor_ids = {safe_id(anchor.get('id')) for anchor in plan.get('anchors', [])}
    targets = {safe_id(target.get('id')): target for target in plan.get('targets', [])}
    if len(anchor_ids) != len(plan.get('anchors', [])) or len(targets) != len(plan.get('targets', [])):
        raise ValueError('Duplicate anchor or target identity')
    for target in targets.values():
        if target.get('mode') != 'fixed-world-point':
            raise ValueError('Only explicit fixed-world targets are supported')
        finite(target.get('maxDistance'), 'Target maximum distance', .001, 1000000)
    expanded_total = 0
    for action in actions:
        particle_total = 0
        if action.get('clip') != action['id']:
            raise ValueError('Composite clip must retain action identity')
        duration = finite(action.get('duration'), 'Action duration', .001, budget['maxActionSeconds'])
        if abs(duration * plan['fps'] - round(duration * plan['fps'])) > 1e-5:
            raise ValueError('Action duration is not on the selected bake frame grid')
        frames += round(duration * plan['fps']) + 1
        if not isinstance(action.get('steps'), list) or not action['steps'] or len(action['steps']) > budget['maxExpandedSteps']:
            raise ValueError('Missing or excessive expanded steps')
        expanded_total += len(action['steps'])
        if len({safe_id(step.get('id')) for step in action['steps']}) > budget['maxStepsPerAction']:
            raise ValueError('Per-action source step count exceeds budget')
        if not isinstance(action.get('cues'), list) or len(action['cues']) > budget['maxEffects']:
            raise ValueError('Missing or excessive action cues')
        cue_ids = [safe_id(cue.get('id')) for cue in action['cues']]
        if len(cue_ids) != len(set(cue_ids)):
            raise ValueError('Duplicate action cue')
        for cue in action['cues']:
            if cue.get('type') not in ('orb','particles','projectile') or cue.get('anchor') not in anchor_ids:
                raise ValueError('Cue requires a supported type and actual anchor')
            begin = finite(cue.get('start'), 'Cue start', 0, duration)
            end = finite(cue.get('end'), 'Cue end', 0, duration)
            if begin >= end or not re.fullmatch(r'#[a-fA-F0-9]{6}', str(cue.get('color',''))):
                raise ValueError('Cue requires increasing times and explicit #RRGGBB colour')
            finite(cue.get('radius'), 'Cue radius', .001, 10)
            if cue['type'] == 'projectile' and cue.get('target') not in targets:
                raise ValueError('Projectile cue requires a declared fixed target')
            if cue['type'] == 'particles':
                particle_total += finite(cue.get('capacity'), 'Particle capacity', 1, budget['maxParticles'], True)
                finite(cue.get('rate'), 'Particle rate', 0, 1000)
                finite(cue.get('seed'), 'Particle seed', 0, 2147483647, True)
        for marker in action.get('markers',[]):
            finite(marker.get('at'), 'Action marker time', 0, duration)
            text(marker.get('name'), 'Action marker name')
        if particle_total > budget['maxParticles']:
            raise ValueError('Per-action aggregate particle capacity exceeds budget')
    if frames > budget['maxFrames']:
        raise ValueError('Baked action samples exceed maxFrames')
    if expanded_total > budget['maxExpandedSteps']:
        raise ValueError('Total expanded steps exceed budget')
    review = job.get('review')
    if not isinstance(review, dict):
        raise ValueError('Missing explicit technical review settings')
    finite(review.get('fps'), 'Review FPS', 1, 60, True)
    vector(review.get('resolution'), 2, 'Review resolution')
    for value in review['resolution']:
        finite(value, 'Review resolution', 32, 2048, True)
    if not isinstance(review.get('cameras'), list) or not review['cameras'] or len(review['cameras']) > 7 or len(set(review['cameras'])) != len(review['cameras']):
        raise ValueError('Review needs unique declared cameras')
    if any(view not in ('front','right','back','left','top','bottom','three-quarter') for view in review['cameras']):
        raise ValueError('Unknown technical review camera')
    if not isinstance(review.get('targets'), dict):
        raise ValueError('Review requires an explicit fixed-target map')
    output.mkdir(parents=True, exist_ok=True)
    if source.suffix.lower() == '.glb':
        read_glb(source, budget['maxRuntimeBytes'])
    return job, root, source, output, result, plan
