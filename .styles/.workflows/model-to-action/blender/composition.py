"""Actual sampled compound motions plus editable source NLA ancestry."""
import copy
import json
import math
import re
import struct
from array import array

from core import all_curves, armatures, digest, finite, identity, inventory, meshes, objects, read_glb, relative, safe_id, save_blend, save_json, text
from verification import MAX_FRAME_BYTES, preflight, read_spool, write_spool


def glb_float_rows(document,binary,index,kind):
    """Read bounded real sampler data before Blender can alter interpolation."""
    accessor=document['accessors'][index]
    width={'SCALAR':1,'VEC3':3,'VEC4':4}[kind]
    if accessor.get('type')!=kind or accessor.get('componentType')!=5126 or accessor.get('normalized') or 'sparse' in accessor or 'bufferView' not in accessor:
        raise ValueError('Source animation requires actual dense floating-point sampler data')
    count=finite(accessor.get('count'),'Source sampler count',1,1000000,True)
    view=document['bufferViews'][accessor['bufferView']]
    stride=finite(view.get('byteStride',width*4),'Source sampler stride',width*4,252,True)
    begin=finite(view.get('byteOffset',0),'Source sampler offset',0,integer=True)+finite(accessor.get('byteOffset',0),'Source accessor offset',0,integer=True)
    length=finite(view.get('byteLength'),'Source sampler bytes',1,integer=True)
    if not isinstance(binary,bytes) or view.get('buffer',0)!=0 or begin+(count-1)*stride+width*4 > min(len(binary),view.get('byteOffset',0)+length):
        raise ValueError('Source animation sampler escapes its actual binary storage')
    return [tuple(finite(value,'Source sampler value') for value in struct.unpack_from('<'+'f'*width,binary,begin+index*stride)) for index in range(count)]


def validate_source_glb(source,motion,plan):
    """Root ownership is checked against original GLB channels before import.

    The shared compositor requires constant root-affecting transform channels.
    This prevents subframe motion or importer interpolation loss from silently
    suppressing movement. Counter-moving ancestors require a reviewed in-place
    bake or an explicit engine movement adapter rather than implicit extraction.
    """
    document,binary=read_glb(source,plan['budgets']['maxRuntimeBytes'])
    nodes=document.get('nodes',[]);parents={}
    for parent,item in enumerate(nodes):
        for child in item.get('children',[]):
            if type(child) is not int or child<0 or child>=len(nodes) or child in parents:
                raise ValueError('Ambiguous actual source node hierarchy')
            parents[child]=parent
    selector=motion['rig'].get('rootBone') if motion['profile']=='skinned' else motion['rig'].get('rootNode')
    matches=[index for index,item in enumerate(nodes) if item.get('name')==selector]
    if len(matches)!=1:raise ValueError('Actual source root identity is missing or ambiguous')
    affecting=set();cursor=matches[0]
    while cursor is not None:
        if cursor in affecting:raise ValueError('Cyclic actual source root ancestry')
        affecting.add(cursor);cursor=parents.get(cursor)
    clips={clip['id']:clip for clip in motion.get('clips',[])}
    used={step['clip'] for action in plan['actions'] for step in action['steps']}
    checked=0;source_names=[]
    for identifier in sorted(used):
        if identifier not in clips:raise ValueError('Missing source clip: '+identifier)
        name=clips[identifier].get('action',identifier)
        matches=[item for item in document.get('animations',[]) if item.get('name')==name]
        if len(matches)!=1:raise ValueError('Actual source clip binding is missing or ambiguous')
        animation=matches[0];source_names.append(name)
        for channel in animation.get('channels',[]):
            target=channel.get('target',{})
            if type(target.get('node')) is not int or target['node']<0 or target['node']>=len(nodes) or target.get('path') not in ('translation','rotation','scale'):
                raise ValueError('Source actions support actual node translation, rotation and scale channels; other channel classes require explicit authoring support')
            if target.get('node') not in affecting:continue
            path=target.get('path')
            if path not in ('translation','rotation','scale'):raise ValueError('Unsupported actual root-affecting source channel')
            sampler=animation['samplers'][channel['sampler']];mode=sampler.get('interpolation','LINEAR')
            rows=glb_float_rows(document,binary,sampler['output'],'VEC4' if path=='rotation' else 'VEC3')
            times=glb_float_rows(document,binary,sampler['input'],'SCALAR')
            if any(right[0]<=left[0] for left,right in zip(times,times[1:])):raise ValueError('Actual source sampler time is not strictly increasing')
            if mode=='CUBICSPLINE':
                if len(rows)!=len(times)*3:raise ValueError('Invalid actual cubic source sampler count')
                tangents=[row for index,row in enumerate(rows) if index%3!=1];values=rows[1::3]
            elif mode in ('LINEAR','STEP'):
                if len(rows)!=len(times):raise ValueError('Invalid actual source sampler count')
                tangents=[];values=rows
            else:raise ValueError('Unsupported actual source interpolation')
            if any(abs(value)>1e-6 for row in tangents for value in row) or any(abs(value-first)>1e-5 for row in values for value,first in zip(row,values[0])):
                raise ValueError('Actual source clip moves its root through a nonconstant original root/ancestor sampler; author a reviewed in-place counterpart or select an engine-specific movement adapter')
            checked+=1
        # Blender 4.5 can omit imported cubic tangent behavior. A reviewed linear
        # or stepped source bake is required instead of silently approximating it.
        if any(animation['samplers'][channel['sampler']].get('interpolation','LINEAR') not in ('LINEAR','STEP') for channel in animation.get('channels',[])):
            raise ValueError('CUBICSPLINE source animation requires a reviewed LINEAR/STEP bake; this Blender import path cannot certify source tangents')
    return {'originalGlb':True,'clips':source_names,'rootAndAncestorChannels':checked,'policy':'constant-root-affecting-channels; reviewed LINEAR/STEP source clips'}


def node(name):
    import bpy
    value = bpy.context.scene.objects.get(text(name, 'Node identity'))
    if value is None:
        raise ValueError('Required model node is missing: ' + name)
    return value


def rest_state():
    result = {}
    for obj in objects():
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
        if obj.type == 'ARMATURE':
            from mathutils import Matrix
            for bone in obj.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
        result[obj.name] = (obj.matrix_basis.copy(), {bone.name: bone.matrix_basis.copy() for bone in obj.pose.bones} if obj.type == 'ARMATURE' else {})
    return result


def reset(rest):
    import bpy
    for name, (matrix, bones) in rest.items():
        obj = node(name)
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
        obj.matrix_basis = matrix
        for name, value in bones.items():
            obj.pose.bones[name].matrix_basis = value
    bpy.context.view_layer.update()


def assign(owner, action):
    owner.animation_data_create()
    owner.animation_data.use_nla = False
    owner.animation_data.action = action
    selected = [slot for slot in action.slots if slot.identifier == 'OB' + owner.name]
    if len(selected) == 1:
        owner.animation_data.action_slot = selected[0]
    elif action.get('opencaw_action_id'):
        owner.animation_data.action_slot = action.slots.new(id_type='OBJECT', name=owner.name)
    elif len(action.slots) == 1:
        owner.animation_data.action_slot = action.slots[0]
    else:
        raise ValueError('Ambiguous source action slot ownership for ' + owner.name)


def source_library(motion, plan):
    import bpy
    clips = {item['id']: item for item in motion.get('clips', [])}
    if len(clips) != len(motion.get('clips', [])):
        raise ValueError('Duplicate source clip identity')
    used = {step['clip'] for action in plan['actions'] for step in action['steps']}
    library = {}
    for identifier in sorted(used):
        clip = clips.get(identifier)
        if clip is None or clip.get('rootMotion') != 'in-place':
            raise ValueError('Action composition requires a reviewed in-place clip: ' + identifier)
        if not re.fullmatch('[a-f0-9]{64}', str(clip.get('motionSha256', ''))):
            raise ValueError('Source clip lacks actual motion identity')
        action = bpy.data.actions.get(clip.get('action', identifier))
        if action is None or not list(all_curves(action)):
            raise ValueError('Actual source GLB lost animation channels: ' + identifier)
        owners = []
        for obj in objects():
            data = obj.animation_data
            if data and (data.action == action or any(strip.action == action for track in data.nla_tracks for strip in track.strips)):
                owners.append(obj.name)
        if not owners:
            raise ValueError('Actual source animation has no model owners: ' + identifier)
        for curve in all_curves(action):
            if not re.fullmatch(r'(?:pose\.bones\["[^"\\]+"\]\.)?(?:location|rotation_quaternion|rotation_euler|scale)', curve.data_path):
                raise ValueError('Unsupported source channel requires explicit action authoring support: ' + curve.data_path)
        begin, end = action.frame_range
        duration = (end - begin) / plan['fps']
        if abs(duration - finite(clip.get('duration'),'Source clip duration',.001,3600)) > 1e-4:
            raise ValueError('Actual source clip duration disagrees with reviewed metadata')
        action['opencaw_source_clip'] = identifier
        action['opencaw_owners'] = json.dumps(sorted(owners))
        action.use_fake_user = True
        library[identifier] = {'action': action, 'owners': sorted(owners), 'start': float(begin), 'duration': duration, 'metadata': clip}
    rest = rest_state()
    rig = motion.get('rig', {})
    if motion['profile'] == 'skinned':
        if len(armatures()) != 1 or rig.get('rootBone') not in armatures()[0].pose.bones:
            raise ValueError('Source root bone is missing')
        if rig.get('node') and armatures()[0].name != rig['node']:
            raise ValueError('Actual source rig node differs from reviewed metadata')
    elif rig.get('rootNode') not in rest:
        raise ValueError('Source rigid/articulated root is missing')
    for anchor in plan.get('anchors', []):
        node(anchor['node'])
    expanded = 0
    for action in plan['actions']:
        previous = None
        for step_index,step in enumerate(action['steps']):
            safe_id(step['id']); safe_id(step['clip'])
            value = library.get(step['clip'])
            if value is None or step.get('motionSha256') != value['metadata']['motionSha256']:
                raise ValueError('Expanded step source ancestry is stale')
            start, end = finite(step.get('start'), 'Step start', 0), finite(step.get('end'), 'Step end', 0, action['duration'])
            low = finite(step.get('sourceStart'), 'Source trim start', 0)
            high = finite(step.get('sourceEnd'), 'Source trim end', low, value['duration'])
            rate = finite(step.get('rate'), 'Step rate', .1, 4)
            blend = finite(step.get('blendIn'), 'Step blend', 0)
            if high <= low or end <= start or abs((high-low)/rate - (end-start)) > 1e-5:
                raise ValueError('Expanded trim/rate/time correspondence is invalid')
            if abs(start*plan['fps']-round(start*plan['fps'])) > 1e-5 or abs(end*plan['fps']-round(end*plan['fps'])) > 1e-5:
                raise ValueError('Expanded step is not on the selected bake grid')
            if previous is None:
                if abs(start) > 1e-7 or blend != 0:
                    raise ValueError('First action step must begin at zero without an incoming blend')
            elif abs(start - (previous['end'] - blend)) > 1e-6 or blend > min(end-start, previous['end']-previous['start']) or start < previous['start']:
                raise ValueError('Expanded steps have a gap or invalid overlap')
            if step_index>=2 and start < action['steps'][step_index-2]['end']-1e-7:
                raise ValueError('Expanded steps have a triple overlap')
            previous = step
            expanded += 1
        if abs(previous['end'] - action['duration']) > 1e-6:
            raise ValueError('Action duration does not match its expanded steps')
    if expanded > plan['budgets']['maxExpandedSteps']:
        raise ValueError('Total expanded steps exceed budget')
    # Validate actual evaluated root ownership, not merely source metadata labels.
    schedules={identifier:source_inspection_times(value,plan['fps']) for identifier,value in library.items()}
    samples = sum(len(times) for times in schedules.values())
    if samples > plan['budgets']['maxFrames']:
        raise ValueError('Required source inspection exceeds frame budget')
    for identifier,value in library.items():
        initial = None
        for time in schedules[identifier]:
            sample_source(value, time, rest, plan['fps'])
            current = root_transform(motion)
            if not all(math.isfinite(value) for row in current for value in row):
                raise ValueError('Non-finite source root transform')
            if initial is None:
                initial = current
            delta = initial.inverted_safe() @ current
            if delta.translation.length > 1e-4 or min(delta.to_quaternion().angle, 2*math.pi-delta.to_quaternion().angle) > 1e-4 or max(abs(v-1) for v in delta.to_scale()) > 1e-4:
                raise ValueError('Actual source clip moves its root; author an in-place counterpart or select an engine-specific movement adapter')
    reset(rest)
    return library, rest


def source_inspection_times(value,fps):
    """Inspect actual imported source keys, not only the output bake grid.

    All source channel keys are included so root-bone, armature and animated
    ancestor ownership share the same check. Interior thirds also expose cubic
    excursions whose endpoints are constant. Additional observations consume
    the explicit inspection frame budget rather than being silently dropped.
    """
    times={0.0,value['duration']}
    for index in range(round(value['duration']*fps)+1):
        times.add(min(index/fps,value['duration']))
    keys=set()
    for curve in all_curves(value['action']):
        for point in curve.keyframe_points:
            time=(finite(float(point.co.x),'Source key frame')-value['start'])/fps
            if time < -1e-6 or time > value['duration']+1e-6:
                raise ValueError('Actual source key time escapes its clip')
            keys.add(max(0,min(time,value['duration'])))
    ordered=sorted(keys)
    times.update(ordered)
    for begin,end in zip(ordered,ordered[1:]):
        times.update((begin+(end-begin)/3,begin+2*(end-begin)/3))
    return sorted(times)


def root_transform(motion):
    if motion['profile'] == 'skinned':
        rig = armatures()[0]
        return rig.matrix_world @ rig.pose.bones[motion['rig']['rootBone']].matrix
    return node(motion['rig']['rootNode']).matrix_world.copy()


def sample_source(value, time, rest, fps):
    import bpy
    reset(rest)
    for owner in value['owners']:
        assign(node(owner), value['action'])
    frame = value['start'] + time * fps
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
    bpy.context.view_layer.update()
    return {obj.name: (obj.matrix_basis.copy(), {bone.name: bone.matrix_basis.copy() for bone in obj.pose.bones} if obj.type == 'ARMATURE' else {}) for obj in objects()}


def apply_pose(pose):
    import bpy
    for name, (matrix, bones) in pose.items():
        obj = node(name)
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
        obj.matrix_basis = matrix
        for name, value in bones.items():
            obj.pose.bones[name].matrix_basis = value
    bpy.context.view_layer.update()


def sample_plan(action, time, library, rest, fps):
    steps = action['steps']
    # Half-open spans keep a zero-weight completed clip out of an adjacent
    # cross-fade's exact shared boundary; the final endpoint remains explicit.
    active = [step for step in steps if step['start']-1e-8 <= time < step['end']-1e-8]
    if abs(time-action['duration'])<1e-8:
        active=[steps[-1]]
    if not active or len(active) > 2:
        raise ValueError('Action has a gap or triple overlap')
    if len(active) == 2 and active[-1]['blendIn'] == 0:
        active = [active[-1]]
    poses = []
    for step in active:
        local = step['sourceStart'] + max(0, min(time-step['start'], step['end']-step['start'])) * step['rate']
        poses.append(sample_source(library[step['clip']], local, rest, fps))
    if len(poses) == 1:
        return poses[0]
    fraction = max(0, min(1, (time-active[-1]['start'])/active[-1]['blendIn']))
    return {name: (poses[0][name][0].lerp(poses[1][name][0], fraction),
                   {bone: poses[0][name][1][bone].lerp(poses[1][name][1][bone], fraction) for bone in poses[0][name][1]}) for name in rest}


def plan_signature(plan):
    return identity({key: plan[key] for key in ('fps','rig','anchors','targets','budgets')} | {'actions': [{key: action[key] for key in ('id','role','clip','duration','steps','cues','markers')} for action in plan['actions']]})


def pose_identity(pose):
    def values(matrix):
        result = [float(value) for row in matrix for value in row]
        if not all(math.isfinite(value) for value in result):
            raise ValueError('Non-finite evaluated compound pose')
        return [round(value, 6) for value in result]
    return {name: {'node': values(matrix), 'bones': {bone: values(value) for bone, value in sorted(bones.items())}} for name, (matrix, bones) in sorted(pose.items())}


def compose(job, plan):
    import bpy
    motion = job['motionPackage']
    library, rest = source_library(motion, plan)
    verification_preflight(plan)
    for index,obj in enumerate(sorted(meshes(),key=lambda obj:obj.name)):
        obj['opencaw_action_mesh']='mesh-'+str(index)
        # glTF's Blender importer splits skinned nodes into sibling objects.
        # Carry a mesh-datablock identity as well as the node identity so the
        # independent comparison follows geometry without trusting new names.
        if obj.data.users > 1:
            obj.data=obj.data.copy()
        obj.data['opencaw_action_mesh']='mesh-'+str(index)
    # Namespace retained source actions so an action may share a source clip ID.
    for identifier, value in library.items():
        value['action'].name = 'source.' + identifier
    for obj in objects():
        if obj.animation_data:
            for track in list(obj.animation_data.nla_tracks):
                obj.animation_data.nla_tracks.remove(track)
    measured = []
    for declared in plan['actions']:
        composite = bpy.data.actions.new(declared['id'])
        composite['opencaw_action_id'] = declared['id']
        composite.use_fake_user = True
        owners = sorted(rest)
        hasher = __import__('hashlib').sha256()
        count = round(declared['duration']*plan['fps'])+1
        first_root = None
        previous_objects = {}
        previous_bones = {}
        for index in range(count):
            pose = sample_plan(declared, index/plan['fps'], library, rest, plan['fps'])
            apply_pose(pose)
            current = root_transform(motion)
            if first_root is None:
                first_root = current
            if (current.translation-first_root.translation).length > 1e-4 or first_root.to_quaternion().rotation_difference(current.to_quaternion()).angle > 1e-4:
                raise ValueError('Composed action acquired root motion')
            hasher.update(json.dumps({'sample':index,'pose':pose_identity(pose)}, sort_keys=True, separators=(',', ':')).encode())
            for name in owners:
                owner = node(name)
                assign(owner, composite)
                owner.rotation_mode = 'QUATERNION'
                owner.matrix_basis = pose[name][0]
                rotation = owner.rotation_quaternion.copy()
                previous = previous_objects.get(name)
                if previous is not None and previous.dot(rotation) < 0:
                    rotation.negate()
                owner.rotation_quaternion = rotation
                previous_objects[name] = rotation.copy()
                for prop in ('location','rotation_quaternion','scale'):
                    owner.keyframe_insert(prop, frame=index)
                for bone_name, matrix in pose[name][1].items():
                    bone = owner.pose.bones[bone_name]
                    bone.rotation_mode = 'QUATERNION'
                    bone.matrix_basis = matrix
                    rotation = bone.rotation_quaternion.copy()
                    previous = previous_bones.get((name, bone_name))
                    if previous is not None and previous.dot(rotation) < 0:
                        rotation.negate()
                    bone.rotation_quaternion = rotation
                    previous_bones[(name, bone_name)] = rotation.copy()
                    for prop in ('location','rotation_quaternion','scale'):
                        bone.keyframe_insert(prop, frame=index)
        for curve in all_curves(composite):
            for key in curve.keyframe_points:
                key.interpolation = 'LINEAR'
        composite['opencaw_owners'] = json.dumps(owners)
        report = copy.deepcopy(declared)
        report['motionSha256'] = hasher.hexdigest()
        measured.append(report)
    reset(rest)
    # Editable source strips retain real original actions, trims, rates and
    # incoming/outgoing overlaps. They are muted; fixed recomposition owns bake.
    editable = 0
    for declared in plan['actions']:
        for index, step in enumerate(declared['steps']):
            value = library[step['clip']]
            for name in value['owners']:
                owner = node(name); owner.animation_data_create()
                track = owner.animation_data.nla_tracks.new()
                track.name = 'EDIT.' + declared['id'] + '.' + str(index)
                track.mute = True
                strip = track.strips.new(step['clip'], round(step['start']*plan['fps']), value['action'])
                strip.action_slot = next(slot for slot in value['action'].slots if slot.identifier == 'OB'+name) if len(value['action'].slots)>1 else value['action'].slots[0]
                strip.action_frame_start = value['start'] + step['sourceStart']*plan['fps']
                strip.action_frame_end = value['start'] + step['sourceEnd']*plan['fps']
                strip.scale = 1/step['rate']
                strip.repeat = 1
                strip.frame_start = step['start']*plan['fps']
                strip.frame_end = step['end']*plan['fps']
                strip.blend_type = 'REPLACE'
                strip.extrapolation = 'NOTHING'
                strip.blend_in = step['blendIn']*plan['fps']
                if index+1 < len(declared['steps']):
                    strip.blend_out = declared['steps'][index+1]['blendIn']*plan['fps']
                editable += 1
    bpy.context.scene['opencaw_action_plan'] = plan_signature(plan)
    bpy.context.scene['opencaw_compiled_actions'] = json.dumps(measured)
    bpy.context.scene['opencaw_editable_sources'] = editable
    activate_composite(plan['actions'][0]['id'])
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = max(round(action['duration']*plan['fps']) for action in plan['actions'])
    return measured


def composite_action(identifier):
    import bpy
    found = [action for action in bpy.data.actions if action.get('opencaw_action_id') == identifier]
    if len(found) != 1:
        raise ValueError('Expected exactly one real compound action: ' + identifier)
    return found[0]


def activate_composite(identifier):
    action = composite_action(identifier)
    for obj in objects():
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
    for name in json.loads(action['opencaw_owners']):
        assign(node(name), action)
    return action


def restore_composites(plan):
    import bpy
    for declared in plan['actions']:
        action = bpy.data.actions.get(declared['clip'])
        if action is None or not list(all_curves(action)):
            raise ValueError('Independent runtime re-import lost compound clip channels')
        owners = []
        for obj in objects():
            data = obj.animation_data
            if data and (data.action == action or any(strip.action == action for track in data.nla_tracks for strip in track.strips)):
                owners.append(obj.name)
        if not owners:
            raise ValueError('Re-imported compound has no real owners')
        start,end = action.frame_range
        if abs(start) > 1e-4 or abs((end-start)/plan['fps']-declared['duration']) > 1e-4:
            raise ValueError('Independent re-import changed compound duration')
        action['opencaw_action_id'] = declared['id']
        action['opencaw_owners'] = json.dumps(sorted(owners))


def pose_vertices():
    import bpy
    graph = bpy.context.evaluated_depsgraph_get()
    result = {}
    payload_bytes = 0
    for obj in meshes():
        owner=obj
        while owner is not None and not owner.get('opencaw_action_mesh'):
            owner=owner.parent
        identifier=obj.data.get('opencaw_action_mesh') or (owner.get('opencaw_action_mesh') if owner is not None else obj.name)
        if identifier in result:
            raise ValueError('Ambiguous independently re-imported mesh ownership')
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        try:
            payload_bytes += len(mesh.vertices) * 24
            if payload_bytes > MAX_FRAME_BYTES:
                raise ValueError('One verification frame exceeds the fixed 256MiB memory payload limit')
            result[identifier] = array('d', (value for vertex in mesh.vertices for value in evaluated.matrix_world @ vertex.co))
        finally:
            evaluated.to_mesh_clear()
    return result


def mesh_materials():
    """Keep actual mesh/material-slot correspondence across independent import."""
    result={}
    for obj in meshes():
        identifier=obj.data.get('opencaw_action_mesh') or obj.get('opencaw_action_mesh') or obj.name
        if identifier in result:
            raise ValueError('Ambiguous material ownership')
        # glTF represents only used material slots; unused Blender slots are not
        # runtime bindings and are deliberately excluded from this comparison.
        result[identifier]=sorted({obj.data.materials[poly.material_index].name if poly.material_index<len(obj.data.materials) and obj.data.materials[poly.material_index] else None for poly in obj.data.polygons},key=lambda value:value or '')
    return result


def current_geometry_sample(plan):
    return {'meshes': pose_vertices(), 'anchors': {
        anchor['id']: array('d', (float(value) for row in node(anchor['node']).matrix_world for value in row))
        for anchor in plan['anchors']}}


def verification_preflight(plan):
    return preflight(plan, plan_signature(plan), current_geometry_sample(plan))


def sampled_compounds(plan):
    """Yield one evaluated frame; never retain the complete animation geometry."""
    import bpy
    for action in plan['actions']:
        activate_composite(action['id'])
        for index in range(round(action['duration']*plan['fps'])+1):
            bpy.context.scene.frame_set(index)
            bpy.context.view_layer.update()
            yield action['id'], index, current_geometry_sample(plan)


def exported_animation_hash(document, binary, animation):
    data = {'animation': animation, 'samples': []}
    for sampler in animation['samplers']:
        for field in ('input','output'):
            accessor = document['accessors'][sampler[field]]
            if 'sparse' in accessor or 'bufferView' not in accessor:
                raise ValueError('Sparse animation storage requires explicit validation')
            view = document['bufferViews'][accessor['bufferView']]
            begin = view.get('byteOffset',0)
            data['samples'].append({'accessor':accessor,'view':view,'bytes':binary[begin:begin+view['byteLength']].hex()})
    return identity(data)


def export(job, root, source, output, plan):
    import bpy
    from core import load_scene
    from mathutils import Vector, kdtree
    if bpy.context.scene.get('opencaw_action_plan') != plan_signature(plan):
        raise ValueError('Working compound source does not match current immutable action plan')
    actions = json.loads(bpy.context.scene['opencaw_compiled_actions'])
    spool_dir = output / 'verification'
    spool = write_spool(root, spool_dir, plan, plan_signature(plan), sampled_compounds(plan))
    material_bindings=mesh_materials()
    before = inventory(job['profile'])
    blend = save_blend(root, output)
    # Keep original source actions/strips in editable .blend only. The GLB ships
    # exactly the requested compound clips, with no hidden source-clip library.
    for obj in objects():
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = True
            for track in list(obj.animation_data.nla_tracks):
                obj.animation_data.nla_tracks.remove(track)
    wanted = {action['id'] for action in plan['actions']}
    for action in list(bpy.data.actions):
        if action.get('opencaw_action_id') not in wanted:
            bpy.data.actions.remove(action)
    for declared in plan['actions']:
        action = composite_action(declared['id'])
        for name in json.loads(action['opencaw_owners']):
            owner = node(name); owner.animation_data_create()
            track = owner.animation_data.nla_tracks.new(); track.name = declared['id']
            strip = track.strips.new(declared['id'], 0, action)
            strip.action_slot = next(slot for slot in action.slots if slot.identifier == 'OB'+name) if len(action.slots)>1 else action.slots[0]
    glb = output / 'asset.glb'
    if glb.exists():
        raise ValueError('Immutable action export already exists')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True, export_animations=True,
                             export_animation_mode='ACTIONS', export_frame_range=False, export_force_sampling=True,
                             export_def_bones=False, export_skins=True, export_apply=False, export_yup=True,export_extras=True)
    document,binary = read_glb(glb,plan['budgets']['maxRuntimeBytes'])
    names = [animation.get('name') for animation in document.get('animations',[])]
    if set(names) != wanted or len(names) != len(wanted):
        raise ValueError('Actual GLB lost, duplicated or included extra compound clips: '+str(names))
    runtime_nodes = [item.get('name') for item in document.get('nodes',[])]
    if len(runtime_nodes) != len(set(runtime_nodes)):
        raise ValueError('Exported node identities are ambiguous')
    for anchor in plan['anchors']:
        if anchor['node'] not in runtime_nodes:
            raise ValueError('Actual export lost declared effect anchor')
    for report in actions:
        animation = document['animations'][names.index(report['id'])]
        if not animation.get('channels') or not animation.get('samplers'):
            raise ValueError('Exported compound has no actual channels')
        report['motionSha256'] = exported_animation_hash(document,binary,animation)
    if job['profile']=='skinned' and not any(skin.get('joints') for skin in document.get('skins',[])):
        raise ValueError('Actual export lost required skin')
    load_scene(glb,plan['fps'])
    restore_composites(plan)
    after = inventory(job['profile'])
    if mesh_materials()!=material_bindings:
        raise ValueError('Independent re-import changed mesh material correspondence')
    if job['profile']=='skinned':
        if len(armatures())!=1 or plan['rig'].get('rootBone') not in armatures()[0].pose.bones or plan['rig'].get('node',armatures()[0].name)!=armatures()[0].name:
            raise ValueError('Independent re-import changed reviewed source rig ownership')
    elif plan['rig'].get('rootNode') not in {obj.name for obj in objects()}:
        raise ValueError('Independent re-import lost reviewed mechanical root')
    maximum = 0.0
    anchor_error=0.0
    compared = 0
    actual = iter(sampled_compounds(plan))
    with read_spool(root, spool_dir, plan, plan_signature(plan)) as (_, expected):
        for identifier,frame,first in expected:
            try:
                actual_id, actual_frame, second = next(actual)
            except StopIteration:
                raise ValueError('Independent re-import lost compound sample coverage') from None
            if actual_id != identifier or actual_frame != frame:
                raise ValueError('Independent re-import changed compound sample order')
            for anchor in plan['anchors']:
                left=first['anchors'][anchor['id']];right=second['anchors'][anchor['id']]
                anchor_error=max(anchor_error,max(abs(a-b) for a,b in zip(left,right)))
            first,second=first['meshes'],second['meshes']
            if set(first)!=set(second):
                raise ValueError('Independent re-import changed actual mesh ownership: '+str(sorted(first))+' -> '+str(sorted(second)))
            for name in first:
                if not first[name] or not second[name]:
                    raise ValueError('Independent re-import lost real geometry')
                for left,right in ((first[name],second[name]),(second[name],first[name])):
                    tree=kdtree.KDTree(len(right)//3)
                    for index in range(0,len(right),3):tree.insert(Vector(right[index:index+3]),index//3)
                    tree.balance()
                    for index in range(0,len(left),3):
                        distance=tree.find(Vector(left[index:index+3]))[2]
                        if not math.isfinite(distance):raise ValueError('Non-finite independent motion comparison')
                        maximum=max(maximum,distance)
            compared += 1
    try:
        next(actual)
    except StopIteration:
        pass
    else:
        raise ValueError('Independent re-import produced unexpected extra compound frames')
    if maximum>.001:
        raise ValueError('Independent re-import changed compound deformation by more than .001 metres')
    if anchor_error>.001:
        raise ValueError('Independent re-import changed effect-anchor world transforms')
    package=copy.deepcopy(plan)
    package.update(schemaVersion='opencaw-action-package/v1',asset=job['asset'],version=job['version'],profile=job['profile'],
                   model={'path':relative(root,glb),'sha256':digest(glb)},source={'path':blend,'sha256':digest(root/blend)},actions=actions,
                   verification={'status':'pending','runtime':'not-run','human':'pending','independent':'pending'})
    package_path=output/'action-package.json';save_json(package_path,package)
    measured={'before':before,'after':after,'independentReimport':{'actualGlb':True,'animationNames':names,'skinCount':len(document.get('skins',[])),
              'allBakedFramesCompared':compared,'maximumWorldVertexError':maximum,'toleranceMetres':.001,
              'maximumAnchorMatrixError':anchor_error,'materialBindingsVerified':True,'rootOwnershipVerified':True,
              'verificationStorage':{'mode':'disk-backed-float64','spoolBytes':spool['totalBytes'],
                  'framePayloadBytes':spool['framePayloadBytes'],'framesComparedIncrementally':True,'fixedFramePayloadLimit':MAX_FRAME_BYTES,
                  'frameChecksumsVerified':True,'completeDataChecksumVerified':True}}}
    return {'blend':blend,'glb':relative(root,glb),'package':relative(root,package_path),
            'verificationIndex':relative(root,spool_dir/'index.json'),
            'verificationData':relative(root,spool_dir/'poses.bin'),
            'verificationFrames':relative(root,spool_dir/'frames.jsonl')},actions,measured
