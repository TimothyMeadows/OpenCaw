"""Native declarative rig, motion, retarget and export implementations."""
import json
import math

from core import all_curves, armatures, digest, finite, identity, inventory, meshes, no_excluded_providers, objects, owned_curves, read_glb, relative, rig_identity, safe_id, save_blend, save_json, text, vector


def node(name):
    import bpy
    value = bpy.context.scene.objects.get(text(name, "Node identity"))
    if value is None:
        raise ValueError("Required independent node is missing: " + str(name))
    return value


def remember_rest():
    for obj in objects():
        if "opencaw_rest_matrix" not in obj:
            obj["opencaw_rest_matrix"] = json.dumps([list(row) for row in obj.matrix_basis])


def reset_pose():
    import bpy
    from mathutils import Matrix
    for obj in objects():
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
        if "opencaw_rest_matrix" in obj:
            obj.matrix_basis = Matrix(json.loads(obj["opencaw_rest_matrix"]))
        if obj.type == "ARMATURE":
            for bone in obj.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def clear_motion():
    import bpy
    reset_pose()
    for obj in objects():
        obj.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def prepare(recipe):
    import bpy
    from mathutils import Matrix, Vector
    existing = {obj.name: obj for obj in objects()}
    root_name = recipe["rig"].get("rootNode", "MotionRoot")
    root = existing.get(root_name)
    if root is None:
        root = bpy.data.objects.new(root_name, None)
        bpy.context.scene.collection.objects.link(root)
        for obj in list(existing.values()):
            if obj.parent is None:
                world = obj.matrix_world.copy()
                obj.parent = root
                obj.matrix_world = world
    if root.type != "EMPTY":
        raise ValueError("Motion root must be an explicit empty hierarchy node")
    declared = {}
    for part in recipe["parts"]:
        name = text(part.get("node"), "Part node")
        if name in declared:
            raise ValueError("A part has multiple owners")
        declared[name] = part
        value = node(name)
        if part.get("independent", False) and value.type != "MESH":
            raise ValueError("Independent moving part requires real mesh geometry")
    for name, part in declared.items():
        seen = {name}
        parent_name = part.get("parent", root_name)
        cursor = parent_name
        while cursor in declared:
            if cursor in seen:
                raise ValueError("Part parenting contains a cycle")
            seen.add(cursor)
            cursor = declared[cursor].get("parent", root_name)
        value, parent = node(name), node(parent_name)
        if value == root or parent == value:
            raise ValueError("Invalid root/part parent ownership")
        world = value.matrix_world.copy()
        value.parent = parent
        value.matrix_world = world
        if "pivot" in part:
            if value.type != "MESH":
                raise ValueError("Explicit pivot requires a mesh part")
            location = Vector(vector(part["pivot"], 3, "World pivot"))
            offset = value.matrix_world.inverted() @ location
            children = {child: child.matrix_world.copy() for child in value.children}
            value.data = value.data.copy()
            value.data.transform(Matrix.Translation(-offset))
            value.matrix_world.translation = location
            for child, matrix in children.items():
                child.matrix_world = matrix
    for anchor in recipe["anchors"]:
        identifier = safe_id(anchor.get("id"))
        parent = node(anchor.get("node"))
        name = "anchor." + identifier
        if name in bpy.data.objects:
            existing=bpy.data.objects[name]
            position=vector(anchor.get("position",[0,0,0]),3,"Anchor position")
            if existing.type!="EMPTY" or existing.parent!=parent or max(abs(existing.location[index]-position[index]) for index in range(3))>1e-5:
                raise ValueError("Anchor identity collides with incompatible input objects")
            continue
        empty = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(empty)
        empty.parent = parent
        empty.location = vector(anchor.get("position", [0, 0, 0]), 3, "Anchor position")
    bpy.context.view_layer.update()
    remember_rest()


def normalize_weights(recipe, rig):
    names = {bone.name for bone in rig.data.bones if bone.use_deform}
    cap = recipe["budgets"]["maxInfluences"]
    for mesh in meshes():
        groups = {group.index: group for group in mesh.vertex_groups if group.name in names}
        for vertex in mesh.data.vertices:
            weights = sorted([(groups[item.group], item.weight) for item in vertex.groups if item.group in groups and item.weight > 1e-8], key=lambda pair: pair[1], reverse=True)
            if not weights:
                raise ValueError("Native skinning left an unweighted vertex")
            keep = weights[:cap]
            total = sum(weight for _, weight in keep)
            for group, _ in weights:
                group.remove([vertex.index])
            for group, weight in keep:
                group.add([vertex.index], weight / total, "REPLACE")


def build_rig(recipe):
    import bpy
    rig_spec = recipe["rig"]
    profile = recipe["profile"]
    if profile != "skinned":
        if armatures():
            raise ValueError("Rigid/articulated profile cannot silently carry an unrelated skin rig")
        if rig_spec.get("mode") != "preserve":
            raise ValueError("Mechanical profiles preserve and validate actual prepared hierarchy")
        node(rig_spec.get("rootNode", "MotionRoot"))
        if profile == "articulated" and not recipe["parts"]:
            raise ValueError("Articulated profile needs declared real moving parts")
        return {"id": identity([(obj.name, obj.parent.name if obj.parent else None, [list(row) for row in obj.matrix_basis]) for obj in objects()]), "kind": profile, "boneCount": 0}
    if rig_spec.get("mode") == "preserve":
        if len(armatures()) != 1:
            raise ValueError("Preserve requires exactly one existing armature")
        rig = armatures()[0]
        if rig_spec.get("rootBone") not in rig.data.bones:
            raise ValueError("Declared root bone does not exist")
        inventory(recipe, True)
        return rig_identity()
    if rig_spec.get("mode") != "declared" or armatures():
        raise ValueError("Declare a new rig explicitly, or preserve the actual input rig")
    bones = rig_spec.get("bones")
    if not isinstance(bones, list) or not bones or len(bones) > recipe["budgets"]["maxBones"]:
        raise ValueError("Declared rig needs bounded bones")
    names = [safe_id(bone.get("name")) for bone in bones]
    if len(names) != len(set(names)) or rig_spec.get("rootBone") not in names:
        raise ValueError("Duplicate bones or missing declared root")
    parents = {bone["name"]: bone.get("parent") for bone in bones}
    for name in names:
        visited = set()
        cursor = name
        while cursor is not None:
            if cursor not in parents or cursor in visited:
                raise ValueError("Invalid or cyclic declared skeleton")
            visited.add(cursor)
            cursor = parents[cursor]
    data = bpy.data.armatures.new("MotionSkeleton")
    rig = bpy.data.objects.new(rig_spec.get("node", "MotionRig"), data)
    bpy.context.scene.collection.objects.link(rig)
    rig.parent = node(rig_spec.get("rootNode", "MotionRoot"))
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for spec in bones:
        bone = data.edit_bones.new(spec["name"])
        bone.head = vector(spec.get("head"), 3, "Bone head")
        bone.tail = vector(spec.get("tail"), 3, "Bone tail")
        if (bone.tail - bone.head).length < 1e-5:
            raise ValueError("A declared bone has no length")
        bone.use_deform = spec.get("deform", True)
    for spec in bones:
        if spec.get("parent") is not None:
            data.edit_bones[spec["name"]].parent = data.edit_bones[spec["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    method = rig_spec.get("skinning", {}).get("method")
    if method == "automatic-heat":
        bpy.ops.object.select_all(action="DESELECT")
        for mesh in meshes():
            mesh.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    elif method == "declared-groups":
        groups = rig_spec["skinning"].get("groups")
        if not isinstance(groups, list) or not groups:
            raise ValueError("Declared-groups skinning requires actual assignments")
        for mesh in meshes():
            if mesh.vertex_groups:
                mesh.vertex_groups.clear()
            modifier = mesh.modifiers.new("MotionSkin", "ARMATURE")
            modifier.object = rig
        for spec in groups:
            mesh = node(spec.get("node"))
            bone_name = spec.get("bone")
            if mesh.type != "MESH" or bone_name not in data.bones or not data.bones[bone_name].use_deform:
                raise ValueError("Weight assignment references a missing deform bone or mesh")
            group = mesh.vertex_groups.get(bone_name) or mesh.vertex_groups.new(name=bone_name)
            entries = spec.get("weights")
            if not isinstance(entries, list) or not entries:
                raise ValueError("Weight group is empty")
            seen = set()
            for pair in entries:
                if not isinstance(pair, list) or len(pair) != 2:
                    raise ValueError("Vertex weight must contain index and weight")
                index = finite(pair[0], "Vertex index", 0, len(mesh.data.vertices) - 1, True)
                if index in seen:
                    raise ValueError("Duplicate vertex in one declared group")
                seen.add(index)
                weight = finite(pair[1], "Skin weight", 0, 1)
                if weight > 0:
                    group.add([index], weight, "REPLACE")
    else:
        raise ValueError("Choose automatic-heat or declared-groups; no implicit skinning fallback")
    normalize_weights(recipe, rig)
    remember_rest()
    inventory(recipe, True)
    return rig_identity()


def quaternion_xyzw(values):
    from mathutils import Quaternion
    x, y, z, w = vector(values, 4, "Quaternion")
    length = math.sqrt(x*x + y*y + z*z + w*w)
    if abs(length - 1) > .001:
        raise ValueError("Quaternion must be normalized")
    return Quaternion((w, x, y, z))


def target_for(channel):
    target = channel.get("target")
    if not isinstance(target, dict) or len(target) != 1:
        raise ValueError("Channel target must declare exactly one node or bone")
    if "bone" in target:
        if len(armatures()) != 1 or target["bone"] not in armatures()[0].pose.bones:
            raise ValueError("Channel references a missing target bone")
        return armatures()[0], armatures()[0].pose.bones[target["bone"]]
    if "node" in target:
        return node(target["node"]), node(target["node"])
    raise ValueError("Channel target type is unsupported")


def new_action(identifier):
    import bpy
    action = bpy.data.actions.new(identifier)
    action["opencaw_clip_id"] = identifier
    return action


def assign_action(owner, action):
    owner.animation_data_create()
    owner.animation_data.use_nla = False
    owner.animation_data.action = action
    for slot in action.slots:
        if slot.identifier == "OB" + owner.name:
            owner.animation_data.action_slot = slot
            break


def finalize_action(action, owners):
    for curve in all_curves(action):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    action.use_fake_user = True
    action["opencaw_owners"] = json.dumps(sorted(owner.name for owner in owners))


def author(recipe,only_clip=None):
    import bpy
    if only_clip is None:
        clear_motion()
    else:
        if only_clip not in {clip["id"] for clip in recipe["clips"]}:
            raise ValueError("Targeted revision references a missing clip")
        for clip in recipe["clips"]:
            find_action(clip["id"])
        reset_pose()
        previous=find_action(only_clip)
        for obj in objects():
            if obj.animation_data:
                for track in list(obj.animation_data.nla_tracks):
                    if any(strip.action==previous for strip in track.strips):
                        obj.animation_data.nla_tracks.remove(track)
        bpy.data.actions.remove(previous)
    for clip in (item for item in recipe["clips"] if only_clip is None or item["id"]==only_clip):
        reset_pose()
        action = new_action(clip["id"])
        owners = set()
        seen = set()
        if not clip["channels"]:
            raise ValueError("Authoring requires real motion channels")
        for channel in clip["channels"]:
            owner, target = target_for(channel)
            prop = channel.get("property")
            if prop not in ("location", "rotation_quaternion", "scale"):
                raise ValueError("Only declared transform channels may be authored")
            identity_key = (owner.name, getattr(target, "name", ""), prop)
            if identity_key in seen:
                raise ValueError("A clip channel has multiple competing owners")
            seen.add(identity_key)
            assign_action(owner, action)
            owners.add(owner)
            keys = channel.get("keyframes")
            if not isinstance(keys, list) or len(keys) < 2:
                raise ValueError("Motion channels require at least two explicit keys")
            previous = None
            previous_rotation = None
            for pair in keys:
                if not isinstance(pair, list) or len(pair) != 2:
                    raise ValueError("Keyframe must be frame/value pair")
                frame = finite(pair[0], "Key frame", clip["startFrame"], clip["endFrame"])
                if previous is not None and frame <= previous:
                    raise ValueError("Channel keys must increase")
                previous = frame
                if prop == "rotation_quaternion":
                    target.rotation_mode = "QUATERNION"
                    rotation = quaternion_xyzw(pair[1])
                    if previous_rotation is not None and previous_rotation.dot(rotation) < 0:
                        rotation.negate()
                    setattr(target, prop, rotation)
                    previous_rotation = rotation.copy()
                else:
                    value = vector(pair[1], 3, prop)
                    if prop == "scale" and any(item <= 0 for item in value):
                        raise ValueError("Animated scale must stay positive")
                    setattr(target, prop, value)
                target.keyframe_insert(prop, frame=frame)
            if keys[0][0] != clip["startFrame"] or keys[-1][0] != clip["endFrame"]:
                raise ValueError("Every channel must define both declared clip endpoints")
        finalize_action(action, owners)
    return analyze_clips(recipe)


def find_action(identifier):
    import bpy
    values = [action for action in bpy.data.actions if action.get("opencaw_clip_id") == identifier]
    if len(values) != 1:
        raise ValueError("Expected exactly one authored action for " + identifier)
    return values[0]


def activate(clip):
    reset_pose()
    action = find_action(clip["id"])
    for name in json.loads(action["opencaw_owners"]):
        assign_action(node(name), action)
    return action


def root_transform(recipe):
    from mathutils import Matrix
    if recipe["profile"] == "skinned":
        if len(armatures()) != 1:
            raise ValueError("A skinned clip requires exactly one target rig")
        rig = armatures()[0]
        name = recipe["rig"].get("rootBone")
        if name not in rig.pose.bones:
            raise ValueError("A clip requires its actual declared root bone")
        return rig.matrix_world @ rig.pose.bones[name].matrix
    return node(recipe["rig"].get("rootNode", "MotionRoot")).matrix_world.copy()


def analyze_clips(recipe):
    import bpy
    from mathutils import Quaternion, Vector
    results = []
    for clip in recipe["clips"]:
        action = activate(clip)
        curves = list(all_curves(action))
        if not curves or not any(max(key.co.y for key in curve.keyframe_points) - min(key.co.y for key in curve.keyframe_points) > 1e-7 for curve in curves if curve.keyframe_points):
            raise ValueError("Named clip has no meaningful animated channels: " + clip["id"])
        if any(not math.isfinite(value) for curve in curves for key in curve.keyframe_points for value in key.co):
            raise ValueError("Clip contains non-finite animation")
        bpy.context.scene.frame_set(clip["startFrame"])
        bpy.context.view_layer.update()
        first = root_transform(recipe)
        max_root = 0.0
        joint_angles = {}
        sampled_hash=__import__('hashlib').sha256()
        sampled_hash.update(json.dumps({"role":clip["role"],"fps":recipe["fps"],"durationFrames":clip["endFrame"]-clip["startFrame"],"loop":clip["loop"],"rootMotion":clip["rootMotion"],"markers":clip["markers"]},sort_keys=True,separators=(",",":")).encode())
        owner_names=json.loads(action["opencaw_owners"])
        for frame in range(clip["startFrame"], clip["endFrame"] + 1):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            current = root_transform(recipe)
            pose={}
            def matrix_values(matrix):
                values=[float(item) for row in matrix for item in row]
                if not all(math.isfinite(item) for item in values):raise ValueError("Non-finite evaluated pose")
                return [round(item,6) for item in values]
            for name in sorted(owner_names):
                owner=node(name)
                pose[name]={"node":matrix_values(owner.matrix_basis),"bones":{bone.name:matrix_values(bone.matrix_basis) for bone in sorted(owner.pose.bones,key=lambda item:item.name)} if owner.type=="ARMATURE" else {}}
            sampled_hash.update(json.dumps({"sample":frame-clip["startFrame"],"pose":pose},sort_keys=True,separators=(",",":")).encode())
            max_root = max(max_root, (current.translation - first.translation).length)
            angle = first.to_quaternion().rotation_difference(current.to_quaternion()).angle
            if clip["rootMotion"] == "in-place" and (max_root > 1e-4 or min(angle, 2*math.pi-angle) > 1e-4):
                raise ValueError("In-place clip moves its authoritative root")
            for rig in armatures():
                for bone in rig.pose.bones:
                    angle = bone.matrix_basis.to_quaternion().angle
                    joint_angles[bone.name] = max(joint_angles.get(bone.name, 0), min(angle, 2*math.pi-angle))
            for spec in recipe["rig"].get("bones", []):
                if "maxAngle" in spec and joint_angles.get(spec["name"], 0) > finite(spec["maxAngle"], "Joint maximum angle", .001, math.pi):
                    raise ValueError("Clip exceeds declared joint angle: " + spec["name"])
        last = root_transform(recipe)
        displacement = last.translation - first.translation
        seam = 0.0
        if clip["loop"]:
            for owner_name,curve in owned_curves(action):
                if "rotation_quaternion" in curve.data_path:
                    continue
                root_translation=(recipe["profile"]=="skinned" and owner_name==armatures()[0].name and curve.data_path=='pose.bones["'+recipe["rig"].get("rootBone","")+'"].location') or (recipe["profile"]!="skinned" and owner_name==recipe["rig"].get("rootNode","MotionRoot") and curve.data_path=="location")
                if clip["rootMotion"] == "extract" and root_translation:
                    continue
                seam = max(seam, abs(curve.evaluate(clip["startFrame"]) - curve.evaluate(clip["endFrame"])))
            for layer in action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        paths = {curve.data_path for curve in bag.fcurves if "rotation_quaternion" in curve.data_path}
                        for path in paths:
                            values = {curve.array_index: curve for curve in bag.fcurves if curve.data_path == path}
                            if set(values) != {0,1,2,3}:
                                raise ValueError("Quaternion channel is incomplete")
                            start_q = Quaternion([values[index].evaluate(clip["startFrame"]) for index in range(4)]).normalized()
                            end_q = Quaternion([values[index].evaluate(clip["endFrame"]) for index in range(4)]).normalized()
                            angle = start_q.rotation_difference(end_q).angle
                            seam = max(seam, min(angle, 2*math.pi-angle))
            if seam > finite(clip.get("loopTolerance", .001), "Loop tolerance", 0, .1):
                raise ValueError("Loop seam exceeds declared tolerance: " + clip["id"])
        contacts=[]
        for contact in clip.get("contacts",[]):
            owner,target=target_for({"target":contact.get("target")})
            duration=(clip["endFrame"]-clip["startFrame"])/recipe["fps"]
            begin=finite(contact.get("start"),"Contact start",0,duration)
            end=finite(contact.get("end"),"Contact end",begin,duration)
            maximum=finite(contact.get("maxTravel"),"Contact travel limit",0,100)
            velocity=Vector(vector(contact.get("referenceVelocity",[0,0,0]),3,"Contact reference velocity"))
            locations=[]
            for frame in range(math.floor(clip["startFrame"]+begin*recipe["fps"]),math.ceil(clip["startFrame"]+end*recipe["fps"])+1):
                bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
                matrix=owner.matrix_world if owner==target else owner.matrix_world@target.matrix
                time=(frame-clip["startFrame"])/recipe["fps"]
                locations.append((matrix.translation.copy(),matrix.translation+velocity*time))
            drift=max((point[1]-locations[0][1]).length for point in locations)
            if drift>maximum+1e-6:raise ValueError("Contact travel exceeds declared limit")
            penetration=None
            if "groundZ" in contact:
                ground=finite(contact["groundZ"],"Contact ground height")
                penetration=max(0,ground-min(point[0].z for point in locations))
                if penetration>finite(contact.get("maxPenetration",.001),"Contact penetration limit",0,100)+1e-6:raise ValueError("Contact penetrates declared ground")
            contacts.append({"target":contact["target"],"start":begin,"end":end,"maxTravel":drift,"penetration":penetration,"referenceVelocity":list(velocity)})
        bindings = [{"node": owner, "paths": sorted({curve.data_path for curve in curves})} for owner in json.loads(action["opencaw_owners"])]
        results.append({"id": clip["id"], "role": clip["role"], "action": action.name, "startFrame": clip["startFrame"], "endFrame": clip["endFrame"], "fps": recipe["fps"], "duration": (clip["endFrame"] - clip["startFrame"]) / recipe["fps"], "loop": clip["loop"], "rootMotion": clip["rootMotion"], "sourceRootDisplacement": list(displacement), "rootDisplacement": [displacement.x,displacement.z,-displacement.y], "maxRootTranslation": max_root, "loopSeam": seam, "bindings": bindings, "markers": clip["markers"], "samples": clip["endFrame"] - clip["startFrame"] + 1,"jointMaxAngles":joint_angles,"contacts":contacts,"motionSha256":sampled_hash.hexdigest()})
    reset_pose()
    return results


def retarget(recipe, root, source, mapping):
    import bpy
    from mathutils import Quaternion, Vector
    if recipe["profile"] != "skinned" or len(armatures()) != 1:
        raise ValueError("Native FK retargeting requires a single skinned target rig")
    if not isinstance(mapping, dict) or mapping.get("schemaVersion") != 1 or mapping.get("provider") not in ("owned", "licensed-library"):
        raise ValueError("Retarget source requires an explicitly supported owned/licensed origin")
    if mapping.get("rights", {}).get("authorized") is not True or not isinstance(mapping["rights"].get("license"), str) or not mapping["rights"]["license"].strip():
        raise ValueError("Retarget source license/rights are required")
    no_excluded_providers(mapping)
    scale = finite(mapping.get("rootTranslationScale"), "Root translation scale", .0001, 10000)
    pairs = mapping.get("bones")
    clips = mapping.get("clips")
    if not isinstance(pairs, list) or not pairs or not isinstance(clips, list) or len(clips) != len(recipe["clips"]):
        raise ValueError("Explicit complete bone/clip mapping required")
    target = armatures()[0]
    target_objects = set(objects())
    clear_motion()
    read_glb(source)
    bpy.ops.import_scene.gltf(filepath=str(source), loglevel=0)
    imported = set(objects()) - target_objects
    rigs = [obj for obj in imported if obj.type == "ARMATURE"]
    source_actions = list(bpy.data.actions)
    if len(rigs) != 1:
        raise ValueError("Source motion requires exactly one actual rig")
    donor = rigs[0]
    source_by_name = {action.name: action for action in source_actions}
    target_names = set()
    for pair in pairs:
        if pair.get("source") not in donor.pose.bones or pair.get("target") not in target.pose.bones or pair["target"] in target_names:
            raise ValueError("Invalid or duplicate target bone mapping")
        target_names.add(pair["target"])
        if "rotationOffset" in pair:
            quaternion_xyzw(pair["rotationOffset"])
        if "translationScale" in pair:
            finite(pair["translationScale"], "Bone translation scale", 0, 10000)
    if not {bone.name for bone in target.data.bones if bone.use_deform} <= target_names or recipe["rig"].get("rootBone") not in target_names:
        raise ValueError("Retarget map omits target deform bones or root")
    clip_map = {item.get("id"): item.get("sourceClip") for item in clips}
    if len(clip_map) != len(clips) or set(clip_map) != {clip["id"] for clip in recipe["clips"]}:
        raise ValueError("Retarget clip coverage is incomplete or duplicated")
    bpy.context.scene.render.fps = recipe["fps"]
    for clip in recipe["clips"]:
        original = source_by_name.get(clip_map[clip["id"]])
        if original is None or not list(all_curves(original)):
            raise ValueError("Requested source action does not exist")
        donor.animation_data_create()
        donor.animation_data.use_nla = False
        donor.animation_data.action = original
        # glTF imports create an armature slot matching the imported owner.
        slots = [slot for slot in original.slots if slot.target_id_type == "OBJECT"]
        if len(slots) != 1:
            raise ValueError("Source retarget action must have one unambiguous armature slot")
        donor.animation_data.action_slot = slots[0]
        source_start, source_end = original.frame_range
        if source_end <= source_start:
            raise ValueError("Source clip has no measurable duration")
        action = new_action(clip["id"])
        assign_action(target, action)
        for frame in range(clip["startFrame"], clip["endFrame"] + 1):
            fraction = (frame - clip["startFrame"]) / (clip["endFrame"] - clip["startFrame"])
            point = source_start + fraction * (source_end - source_start)
            bpy.context.scene.frame_set(math.floor(point), subframe=point - math.floor(point))
            bpy.context.view_layer.update()
            for pair in pairs:
                from_bone = donor.pose.bones[pair["source"]]
                to_bone = target.pose.bones[pair["target"]]
                correction = quaternion_xyzw(pair.get("rotationOffset", [0,0,0,1]))
                to_bone.rotation_mode = "QUATERNION"
                to_bone.rotation_quaternion = correction @ from_bone.matrix_basis.to_quaternion() @ correction.inverted()
                factor = scale if pair["target"] == recipe["rig"]["rootBone"] else pair.get("translationScale", 1)
                to_bone.location = correction @ (from_bone.location * factor)
                to_bone.scale = from_bone.scale
                for prop in ("rotation_quaternion", "location", "scale"):
                    to_bone.keyframe_insert(prop, frame=frame)
        finalize_action(action, {target})
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in source_actions:
        bpy.data.actions.remove(action)
    return analyze_clips(recipe)


def bake(recipe):
    """Sample evaluated local transforms into independent, linearly baked actions."""
    import bpy
    staged = []
    for clip in recipe["clips"]:
        action = activate(clip)
        owners = [node(name) for name in json.loads(action["opencaw_owners"])]
        samples = []
        for frame in range(clip["startFrame"], clip["endFrame"] + 1):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            current = []
            for owner in owners:
                value = {"node": owner.name, "matrix": owner.matrix_basis.copy(), "bones": {}}
                if owner.type == "ARMATURE":
                    for bone in owner.pose.bones:
                        value["bones"][bone.name] = bone.matrix_basis.copy()
                current.append(value)
            samples.append((frame, current))
        staged.append((clip, owners, samples))
    clear_motion()
    for clip, owners, samples in staged:
        action = new_action(clip["id"])
        for owner in owners:
            assign_action(owner, action)
            owner.rotation_mode = "QUATERNION"
        previous_objects = {}
        previous_bones = {}
        for frame, values in samples:
            for value in values:
                owner = node(value["node"])
                owner.matrix_basis = value["matrix"]
                rotation = owner.rotation_quaternion.copy()
                previous = previous_objects.get(owner.name)
                if previous is not None and previous.dot(rotation) < 0:
                    rotation.negate()
                owner.rotation_quaternion = rotation
                previous_objects[owner.name] = rotation.copy()
                for prop in ("location", "rotation_quaternion", "scale"):
                    owner.keyframe_insert(prop, frame=frame)
                for name, matrix in value["bones"].items():
                    bone = owner.pose.bones[name]
                    bone.rotation_mode = "QUATERNION"
                    bone.matrix_basis = matrix
                    rotation = bone.rotation_quaternion.copy()
                    previous = previous_bones.get((owner.name, name))
                    if previous is not None and previous.dot(rotation) < 0:
                        rotation.negate()
                    bone.rotation_quaternion = rotation
                    previous_bones[(owner.name, name)] = rotation.copy()
                    for prop in ("location", "rotation_quaternion", "scale"):
                        bone.keyframe_insert(prop, frame=frame)
        finalize_action(action, owners)
    for obj in objects():
        for constraint in list(obj.constraints):
            obj.constraints.remove(constraint)
        if obj.type == "ARMATURE":
            for bone in obj.pose.bones:
                for constraint in list(bone.constraints):
                    bone.constraints.remove(constraint)
    return analyze_clips(recipe)


def export_package(job, root, source, output, recipe):
    import bpy
    clips = analyze_clips(recipe)
    for obj in objects():
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = True
            for track in list(obj.animation_data.nla_tracks):
                obj.animation_data.nla_tracks.remove(track)
    for clip in recipe["clips"]:
        action = find_action(clip["id"])
        for name in json.loads(action["opencaw_owners"]):
            owner = node(name)
            owner.animation_data_create()
            track = owner.animation_data.nla_tracks.new()
            track.name = clip["id"]
            strip = track.strips.new(clip["id"], clip["startFrame"], action)
            strip.action_slot = next(slot for slot in action.slots if slot.identifier == "OB" + owner.name)
    bpy.context.scene["opencaw_clips"] = json.dumps(clips)
    blend = save_blend(root, output)
    glb = output / "asset.glb"
    if glb.exists():
        raise ValueError("Immutable runtime export already exists")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True, export_animations=True,
                             export_animation_mode="ACTIONS", export_frame_range=False, export_force_sampling=True,
                             export_def_bones=False, export_skins=True, export_apply=False, export_yup=True)
    document = read_glb(glb, recipe["budgets"]["maxRuntimeBytes"])
    animations = document.get("animations", [])
    names = [value.get("name") for value in animations]
    if len(names) != len(set(names)) or not {clip["id"] for clip in clips} <= set(names):
        raise ValueError("Actual GLB export lost or duplicated required clips")
    for clip in clips:
        exported = animations[names.index(clip["id"])]
        if not exported.get("channels") or not exported.get("samplers"):
            raise ValueError("Exported clip has no actual channels")
        clip["exportedChannels"] = len(exported["channels"])
        runtime_names = [item.get("name") for item in document.get("nodes", [])]
        if len(runtime_names) != len(set(runtime_names)):
            raise ValueError("Runtime node names are ambiguous; rename before export")
        clip["sourceBindings"] = clip["bindings"]
        properties = {"translation": "position", "rotation": "quaternion", "scale": "scale", "weights": "weights"}
        pairs = {(runtime_names[channel["target"]["node"]], properties[channel["target"]["path"]]) for channel in exported["channels"]}
        clip["bindings"] = [{"node": name, "property": prop} for name, prop in sorted(pairs)]
    if recipe["profile"] == "skinned" and not any(skin.get("joints") for skin in document.get("skins", [])):
        raise ValueError("Actual GLB export lost the required skin")
    runtime_rig=rig_identity() if recipe["profile"]=="skinned" else {"id":identity([(obj.name,obj.parent.name if obj.parent else None) for obj in objects()]),"kind":recipe["profile"],"boneCount":0}
    runtime_rig["rootNode"]=recipe["rig"].get("rootNode","MotionRoot")
    if recipe["profile"]=="skinned":
        runtime_rig["rootBone"]=recipe["rig"]["rootBone"]
        runtime_rig["node"]=armatures()[0].name
    package = {"schemaVersion": "opencaw-motion-package/v1", "asset": job["asset"], "version": job["version"], "profile": recipe["profile"],
               "model": {"path": relative(root, glb), "sha256": digest(glb)}, "source": {"path": blend, "sha256": digest(root / blend)},
               "sourceInput": {"path": relative(root, source), "sha256": digest(source)},
               "coordinateSystem": {"units": "metres", "sourceUp": "+Z", "sourceForward": "-Y", "runtimeUp": "+Y", "runtimeForward": "+Z", "exportTransform": [[1,0,0],[0,0,1],[0,-1,0]]},
               "rig": runtime_rig,
               "clips": clips, "anchors": [{"id": item["id"], "node": "anchor." + item["id"], "parent": item["node"], "position": item.get("position", [0,0,0])} for item in recipe["anchors"]],
               "parameters": recipe["parameters"], "states": recipe["states"], "transitions": recipe["transitions"], "effects": recipe["effects"],
               "provenance": recipe.get("provenance", {"provider": "native-blender", "rights": "Caller must supply separate model/clip rights evidence; no rights inferred"}),
               "budgets": recipe["budgets"], "verification": {"status": "pending", "runtime": "not-run", "human": "pending", "independent": "pending"}}
    destination = output / "motion-package.json"
    save_json(destination, package)
    return {"blend": blend, "glb": relative(root, glb), "package": relative(root, destination)}, clips
