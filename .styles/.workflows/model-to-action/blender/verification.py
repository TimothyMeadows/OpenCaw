"""Bounded, immutable pose evidence for independent action re-import checks.

Expected and actual frames are compared incrementally; resident payload memory
is independent of total animation duration. The
little-endian float64 spool retains every sampled world-space vertex/anchor;
frame records and complete files are hashed. Interrupted writes are retained
without a completion index and cannot be consumed as passing evidence.
"""
from array import array
from contextlib import contextmanager
import hashlib
import json
import math
from pathlib import Path
import sys

from core import confined, digest, finite, relative

DEFAULT_MAX_BYTES = 8 * 1024**3
MAX_BYTES = 64 * 1024**3
MAX_FRAME_BYTES = 256 * 1024**2
MAGIC = b'OPENCAW-POSE-V1\x00\x00'
NAMES = ('poses.bin', 'frames.jsonl', 'index.json')


def budget(plan):
    return finite(plan['budgets'].get('maxVerificationBytes', DEFAULT_MAX_BYTES),
                  'maxVerificationBytes', 1024, MAX_BYTES, True)


def schedule(plan):
    return [{'id': action['id'], 'frames': round(action['duration'] * plan['fps']) + 1}
            for action in plan['actions']]


def compact(value):
    return (json.dumps(value, separators=(',', ':'), allow_nan=False) + '\n').encode('utf-8')


def frame_record(identifier, frame, offset, size, sha256):
    return {'action': identifier, 'frame': frame, 'offset': offset, 'bytes': size, 'sha256': sha256}


def paths(root, directory):
    directory = confined(root, relative(root, directory))
    return directory, [confined(root, relative(root, directory / name)) for name in NAMES]


def geometry_spec(sample):
    if not sample['meshes']:
        raise ValueError('Verification requires real mesh vertices')
    result = []
    for name, values in sorted(sample['meshes'].items()):
        if not isinstance(values, array) or values.typecode != 'd' or not values or len(values) % 3:
            raise ValueError('Verification requires packed float64 XYZ mesh samples')
        result.append({'id': name, 'vertices': len(values) // 3})
    return result


def anchors_spec(sample):
    result = sorted(sample['anchors'])
    for name in result:
        values = sample['anchors'][name]
        if not isinstance(values, array) or values.typecode != 'd' or len(values) != 16:
            raise ValueError('Verification requires packed float64 anchor matrices')
    return result


def preflight(plan, plan_hash, first):
    """Exact byte demand is known before creating any spool files."""
    meshes, anchors, actions = geometry_spec(first), anchors_spec(first), schedule(plan)
    count = sum(item['frames'] for item in actions)
    payload = sum(item['vertices'] * 24 for item in meshes) + len(anchors) * 128
    if payload > MAX_FRAME_BYTES:
        raise ValueError('One verification frame exceeds the fixed 256MiB memory payload limit')
    offset, index_bytes = len(MAGIC), 0
    for action in actions:
        for frame in range(action['frames']):
            index_bytes += len(compact(frame_record(action['id'], frame, offset, payload, '0' * 64)))
            offset += payload
    metadata = {'schemaVersion': 'opencaw-action-pose-spool/v1', 'planSha256': plan_hash,
                'format': 'float64-le', 'dataFile': NAMES[0], 'framesFile': NAMES[1],
                'meshes': meshes, 'anchors': anchors, 'actions': actions,
                'frameCount': count, 'framePayloadBytes': payload, 'dataBytes': offset,
                'frameIndexBytes': index_bytes, 'dataSha256': '0' * 64, 'framesSha256': '0' * 64,
                'totalBytes': 0}
    while True:
        total = offset + index_bytes + len(compact(metadata))
        if total == metadata['totalBytes']:
            break
        metadata['totalBytes'] = total
    if len(compact(metadata)) > 1024 * 1024:
        raise ValueError('Verification completion index exceeds its fixed metadata budget')
    if total > budget(plan):
        raise ValueError('Complete action verification spool exceeds maxVerificationBytes before export')
    return metadata


def _chunks(sample, metadata):
    if set(sample['meshes']) != {item['id'] for item in metadata['meshes']} or set(sample['anchors']) != set(metadata['anchors']):
        raise ValueError('Verification sample changed mesh or anchor ownership')
    for item in metadata['meshes']:
        values = sample['meshes'][item['id']]
        if not isinstance(values, array) or values.typecode != 'd' or len(values) != item['vertices'] * 3:
            raise ValueError('Animated topology changed expected verification vertex count')
        yield values
    for name in metadata['anchors']:
        values = sample['anchors'][name]
        if not isinstance(values, array) or values.typecode != 'd' or len(values) != 16:
            raise ValueError('Verification sample lost an anchor matrix')
        yield values


def write_spool(root, directory, plan, plan_hash, samples):
    iterator = iter(samples)
    try:
        first_action, first_frame, first = next(iterator)
    except StopIteration:
        raise ValueError('Complete action verification requires every baked sample') from None
    metadata = preflight(plan, plan_hash, first)
    directory, files = paths(root, directory)
    if directory.exists():
        raise ValueError('Immutable verification spool already exists')
    directory.mkdir()
    binary_hash, frames_hash = hashlib.sha256(), hashlib.sha256()
    pending = (first_action, first_frame, first)
    with files[0].open('xb') as binary, files[1].open('xb') as records:
        binary.write(MAGIC); binary_hash.update(MAGIC)
        for action in metadata['actions']:
            for frame in range(action['frames']):
                if pending is None:
                    try:
                        pending = next(iterator)
                    except StopIteration:
                        raise ValueError('Incomplete expected verification sample coverage') from None
                identifier, index, sample = pending
                pending = None
                if identifier != action['id'] or index != frame:
                    raise ValueError('Expected verification samples are out of order or incomplete')
                offset, frame_hash = binary.tell(), hashlib.sha256()
                for values in _chunks(sample, metadata):
                    if not all(math.isfinite(value) for value in values):
                        raise ValueError('Non-finite expected verification vertex/anchor')
                    if sys.byteorder != 'little':
                        values = array('d', values); values.byteswap()
                    raw = memoryview(values).cast('B')
                    binary.write(raw); frame_hash.update(raw); binary_hash.update(raw)
                line = compact(frame_record(identifier, index, offset, metadata['framePayloadBytes'], frame_hash.hexdigest()))
                records.write(line); frames_hash.update(line)
        try:
            next(iterator)
        except StopIteration:
            pass
        else:
            raise ValueError('Unexpected extra expected verification samples')
        if binary.tell() != metadata['dataBytes'] or records.tell() != metadata['frameIndexBytes']:
            raise ValueError('Verification byte preflight differs from actual evidence')
    metadata['dataSha256'], metadata['framesSha256'] = binary_hash.hexdigest(), frames_hash.hexdigest()
    encoded = compact(metadata)
    if sum(path.stat().st_size for path in files[:2]) + len(encoded) != metadata['totalBytes']:
        raise ValueError('Verification spool final size differs from preflight')
    # The completion index is written last. Partial files remain durable failure
    # evidence when cancellation, a timeout or an exception interrupts sampling.
    with files[2].open('xb') as stream:
        stream.write(encoded)
    return metadata


@contextmanager
def read_spool(root, directory, plan, plan_hash):
    directory, files = paths(root, directory)
    if not all(path.is_file() for path in files) or files[2].stat().st_size > 1024 * 1024:
        raise ValueError('Incomplete or oversized verification completion index')
    metadata = json.loads(files[2].read_text(encoding='utf-8'))
    if (metadata.get('schemaVersion') != 'opencaw-action-pose-spool/v1' or metadata.get('planSha256') != plan_hash
            or metadata.get('format') != 'float64-le' or metadata.get('dataFile') != NAMES[0]
            or metadata.get('framesFile') != NAMES[1] or metadata.get('actions') != schedule(plan)):
        raise ValueError('Verification completion index disagrees with the current plan')
    expected_count = sum(item['frames'] for item in schedule(plan))
    if metadata.get('frameCount') != expected_count or sum(path.stat().st_size for path in files) != metadata.get('totalBytes') or metadata['totalBytes'] > budget(plan):
        raise ValueError('Verification spool size or sample coverage exceeds its exact budget')
    for name, key in ((files[0], 'dataBytes'), (files[1], 'frameIndexBytes')):
        if name.stat().st_size != metadata.get(key):
            raise ValueError('Truncated or extended verification evidence')
    if digest(files[1]) != metadata.get('framesSha256'):
        raise ValueError('Verification frame index checksum mismatch')
    if not isinstance(metadata.get('meshes'), list) or not metadata['meshes'] or len(metadata['meshes']) > 10000:
        raise ValueError('Invalid verification mesh ownership')
    ids = [item.get('id') for item in metadata['meshes']]
    if len(ids) != len(set(ids)) or any(not isinstance(name, str) or not name for name in ids):
        raise ValueError('Ambiguous verification mesh identity')
    payload = sum(finite(item.get('vertices'), 'Verification vertex count', 1, 10000000, True) * 24 for item in metadata['meshes'])
    if metadata.get('anchors') != sorted(anchor['id'] for anchor in plan.get('anchors', [])):
        raise ValueError('Verification anchor identities differ from the current plan')
    payload += len(metadata['anchors']) * 128
    if payload > MAX_FRAME_BYTES or payload != metadata.get('framePayloadBytes') or len(MAGIC) + payload * expected_count != metadata['dataBytes']:
        raise ValueError('Verification payload layout disagrees with exact sample demand')
    complete = False
    with files[0].open('rb') as binary, files[1].open('rb') as records:
        if binary.read(len(MAGIC)) != MAGIC:
            raise ValueError('Invalid verification binary header')
        total_hash = hashlib.sha256(MAGIC)

        def samples():
            nonlocal complete
            for action in metadata['actions']:
                for frame in range(action['frames']):
                    line = records.readline(2049)
                    if not line or len(line) > 2048 or not line.endswith(b'\n'):
                        raise ValueError('Incomplete or oversized verification frame record')
                    record = json.loads(line)
                    wanted = frame_record(action['id'], frame, binary.tell(), payload, record.get('sha256'))
                    if record != wanted or not isinstance(record.get('sha256'), str) or len(record['sha256']) != 64:
                        raise ValueError('Verification frame sequence or offsets changed')
                    sample, frame_hash = {'meshes': {}, 'anchors': {}}, hashlib.sha256()
                    for group, specs in (('meshes', [(item['id'], item['vertices'] * 3) for item in metadata['meshes']]),
                                         ('anchors', [(name, 16) for name in metadata['anchors']])):
                        for name, count in specs:
                            values = array('d')
                            try:
                                values.fromfile(binary, count)
                            except EOFError:
                                raise ValueError('Truncated verification vertex/anchor payload') from None
                            raw = memoryview(values).cast('B'); frame_hash.update(raw); total_hash.update(raw)
                            if sys.byteorder != 'little':
                                values.byteswap()
                            if not all(math.isfinite(value) for value in values):
                                raise ValueError('Non-finite verification vertex/anchor payload')
                            sample[group][name] = values
                    if frame_hash.hexdigest() != record['sha256']:
                        raise ValueError('Verification frame payload checksum mismatch')
                    yield action['id'], frame, sample
            if records.read(1) or binary.read(1) or total_hash.hexdigest() != metadata.get('dataSha256'):
                raise ValueError('Extended or corrupt verification evidence')
            complete = True

        yield metadata, samples()
        if not complete:
            raise ValueError('Independent re-import did not consume every verification frame')
