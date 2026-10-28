"""Whole-range sampled motion proofs and independent runtime re-import review."""
import html
import json
import math

from core import all_curves, digest, identity, inventory, meshes, objects, read_glb, relative, save_json
from authoring import activate, analyze_clips, reset_pose


def restore_imported_actions(recipe):
    import bpy
    from authoring import remember_rest
    for clip in recipe["clips"]:
        action = bpy.data.actions.get(clip["id"])
        if action is None:
            raise ValueError("Independent re-import lost an expected action")
        owners = []
        for obj in objects():
            if not obj.animation_data:
                continue
            if obj.animation_data.action == action or any(strip.action == action for track in obj.animation_data.nla_tracks for strip in track.strips):
                owners.append(obj.name)
        if not owners or not list(all_curves(action)):
            raise ValueError("Re-imported action has no real bindings")
        action["opencaw_clip_id"] = clip["id"]
        action["opencaw_owners"] = json.dumps(owners)
        begin,end=action.frame_range
        actual=(end-begin)/recipe["fps"]
        expected=(clip["endFrame"]-clip["startFrame"])/recipe["fps"]
        if abs(actual-expected)>1e-4 or abs(round(begin)-begin)>1e-3 or abs(round(end)-end)>1e-3:
            raise ValueError("Independent re-import changed the declared clip duration")
        clip["authoredStartFrame"]=clip["startFrame"]
        clip["authoredEndFrame"]=clip["endFrame"]
        clip["startFrame"],clip["endFrame"]=round(begin),round(end)
    remember_rest()


def snapshot(frame, clip):
    import bpy
    activate(clip)
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame - math.floor(frame))
    bpy.context.view_layer.update()
    return {obj.name: (obj.matrix_basis.copy(), {bone.name: bone.matrix_basis.copy() for bone in obj.pose.bones} if obj.type == "ARMATURE" else {}) for obj in objects() if obj.type not in ("CAMERA", "LIGHT")}


def apply_blend(first, second, fraction):
    import bpy
    for name in first:
        obj = bpy.context.scene.objects[name]
        obj.matrix_basis = first[name][0].lerp(second[name][0], fraction)
        for bone in first[name][1]:
            obj.pose.bones[bone].matrix_basis = first[name][1][bone].lerp(second[name][1][bone], fraction)
    bpy.context.view_layer.update()


def proof_times(clip, fps):
    duration = (clip["endFrame"] - clip["startFrame"]) / clip["fps"]
    values = [index / fps for index in range(math.ceil(duration * fps) + 1)]
    return sorted(set(min(value, duration) for value in values))


def review(job, root, source, output, recipe):
    import bpy
    from mathutils import Vector
    if source.suffix.lower() != ".glb":
        raise ValueError("Review requires independent import of the actual runtime GLB")
    document = read_glb(source, recipe["budgets"]["maxRuntimeBytes"])
    restore_imported_actions(recipe)
    clips = analyze_clips(recipe)
    measured = inventory(recipe, recipe["profile"] == "skinned")
    review_spec = recipe["review"]
    cameras = review_spec["cameras"]
    requested = 0
    schedules = []
    for declared, report in zip(recipe["clips"], clips):
        times = proof_times(report, review_spec["fps"])
        requested += len(times) * len(cameras)
        schedules.append((declared, times))
    states = {state["id"]: state for state in recipe["states"]}
    transition_jobs = []
    by_id = {clip["id"]: clip for clip in recipe["clips"]}
    for index, transition in enumerate(recipe["transitions"]):
        left = states[transition["from"]].get("clip")
        right = states[transition["to"]].get("clip")
        if left and right and transition["duration"] > 0:
            count = max(2, math.ceil(transition["duration"] * review_spec["fps"]) + 1)
            requested += count * len(cameras)
            transition_jobs.append((index, transition, by_id[left], by_id[right], count))
    if requested > recipe["budgets"]["maxPreviewFrames"]:
        raise ValueError("Full clip/transition preview exceeds maxPreviewFrames; no undocumented frame skipping")
    scene = bpy.context.scene
    scene.render.engine = review_spec["renderer"]
    scene.render.resolution_x, scene.render.resolution_y = review_spec["resolution"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    if scene.render.engine == "BLENDER_WORKBENCH":
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.display.shading.show_shadows = True
        scene.display.shading.show_cavity = True
        scene.display.shading.background_type = "WORLD"
    elif scene.render.engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = 8
    scene.world = bpy.data.worlds.new("MotionReviewWorld")
    scene.world.color = (.15, .15, .15)
    light_data = bpy.data.lights.new("MotionReviewKey", "AREA")
    light = bpy.data.objects.new("MotionReviewKey", light_data)
    scene.collection.objects.link(light)
    light.location = (4,-6,8)
    light_data.energy = 1000
    light_data.shape = "DISK"
    light_data.size = 6
    # One camera fit covers all sampled clips and transitions; no per-pose refit.
    points = []
    for clip, times in schedules:
        activate(clip)
        for time in times:
            frame = clip["startFrame"] + time * recipe["fps"]
            scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
            graph = bpy.context.evaluated_depsgraph_get()
            for obj in meshes():
                evaluated = obj.evaluated_get(graph)
                points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    minimum = Vector([min(point[axis] for point in points) for axis in range(3)])
    maximum = Vector([max(point[axis] for point in points) for axis in range(3)])
    center = (minimum + maximum) / 2
    radius = max((maximum - minimum).length / 2, .05)
    camera_data = bpy.data.cameras.new("MotionReviewCamera")
    camera = bpy.data.objects.new("MotionReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = radius * 2.4 * max(1,review_spec["resolution"][1]/review_spec["resolution"][0])
    camera_data.clip_start = .001
    camera_data.clip_end = max(100, radius * 100)
    directions = {"front":(0,-1,0),"right":(-1,0,0),"back":(0,1,0),"left":(1,0,0),"top":(0,0,1),"bottom":(0,0,-1),"three-quarter":(1,-2,1)}
    artifacts = {}
    packets = []

    def render_frame(folder, index, view):
        direction = Vector(directions[view]).normalized()
        camera.location = center + direction * radius * 4
        camera.rotation_euler = (-direction).to_track_quat("-Z", "Y" if view not in ("top","bottom") else "X").to_euler()
        path=folder/("v"+str(cameras.index(view)))/(str(index).zfill(4)+".png")
        path.resolve().relative_to(output.resolve())
        if path.exists() or path.is_symlink():
            raise ValueError("Review image already exists; immutable frames cannot be overwritten")
        scene.render.filepath = str(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.render.render(write_still=True)
        artifacts["frame-" + str(len(artifacts))] = relative(root, path)
        return {"path":relative(root,path),"sha256":digest(path),"view":view}

    for clip_index,(clip, times) in enumerate(schedules):
        packet = {"id":clip["id"],"key":"clip/"+clip["id"],"type":"clip","duration":(clip["endFrame"]-clip["startFrame"])/recipe["fps"],"frames":[]}
        activate(clip)
        for index, time in enumerate(times):
            frame=clip["startFrame"] + time*recipe["fps"]
            scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
            for view in cameras:
                image=render_frame(output/"f"/("c"+str(clip_index).zfill(3)),index,view)
                packet["frames"].append({**image,"time":time,"sourceFrame":frame})
        packets.append(packet)
    for index, transition, left, right, count in transition_jobs:
        packet = {"id":"transition-"+str(index),"key":"transition/"+str(index),"type":"transition","from":transition["from"],"to":transition["to"],"duration":transition["duration"],"method":"declared-pose interpolation; actual engine blend acceptance remains separate","frames":[]}
        for sample in range(count):
            fraction=sample/(count-1)
            left_frame=max(left["startFrame"],left["endFrame"]-transition["duration"]*recipe["fps"]*(1-fraction))
            right_frame=min(right["endFrame"],right["startFrame"]+transition["duration"]*recipe["fps"]*fraction)
            pose_left=snapshot(left_frame,left);pose_right=snapshot(right_frame,right)
            reset_pose();apply_blend(pose_left,pose_right,fraction)
            for view in cameras:
                packet["frames"].append({**render_frame(output/"f"/("t"+str(index).zfill(3)),sample,view),"time":fraction*transition["duration"]})
        packets.append(packet)
    data = {"schemaVersion":"opencaw-motion-review/v1","asset":job["asset"],"profile":recipe["profile"],"inputSha256":digest(source),"frameCount":len(artifacts),"requestedFrameCount":requested,"renderer":review_spec["renderer"],"previewFps":review_spec["fps"],"resolution":review_spec["resolution"],"cameras":cameras,"fit":{"kind":"one shared full-motion bounds fit","min":list(minimum),"max":list(maximum),"center":list(center),"orthoScale":camera_data.ortho_scale},"clips":clips,"packets":packets,"metrics":measured,"independentReimport":{"actualGlb":True,"skinCount":len(document.get("skins",[])),"animationCount":len(document.get("animations",[]))},"limits":["Sampled playback covers the complete declared duration; it is not a native engine transition/collision/feel verdict.","Workbench previews assess form/deformation; final materials and target rendering require actual engine evidence."],"humanApproval":"pending","independentReview":"pending","runtimeVerification":"not-run"}
    path=output/"motion-review.json";save_json(path,data);artifacts["reviewReport"]=relative(root,path)
    # Scripts consume only JSON we author and relative local images; content is escaped.
    html_packets=[]
    for packet in packets:
        for view in cameras:
            frames=[frame for frame in packet["frames"] if frame["view"]==view]
            html_packets.append({"id":packet["type"]+": "+packet["id"]+" / "+view,"duration":packet["duration"],"frames":[{"path":__import__('os').path.relpath(root/frame["path"],output).replace('\\','/'),"time":frame["time"]} for frame in frames]})
    payload=json.dumps(html_packets).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')
    page=output/"review.html"
    page.write_text('''<!doctype html><meta charset="utf-8"><title>Motion proof review</title><style>body{font-family:sans-serif;background:#222;color:#eee}section{display:inline-block;margin:12px;vertical-align:top}img{display:block;max-width:420px;background:#555}input{width:100%}</style><h1>Complete sampled motion proofs</h1><p>Human and independent review pending. Inspect source likeness, joints, contacts, loops and transitions. These previews do not certify engine behavior.</p><p><a href="motion-review.json">Exact review data, frame hashes and limitations</a></p><main></main><script>const packets='''+payload+''';for(const p of packets){const s=document.createElement('section'),h=document.createElement('h2'),img=document.createElement('img'),range=document.createElement('input'),label=document.createElement('p');h.textContent=p.id;range.type='range';range.min=0;range.max=p.frames.length-1;range.step=1;const show=i=>{img.src=p.frames[i].path;label.textContent=p.frames[i].time.toFixed(3)+' / '+p.duration.toFixed(3)+' seconds';range.value=i};range.oninput=()=>show(+range.value);s.append(h,img,range,label);document.querySelector('main').append(s);show(0);let index=0;setInterval(()=>{index=(index+1)%p.frames.length;show(index)},1000/'''+str(review_spec["fps"])+''')};</script>''',encoding="utf-8")
    artifacts["review"]=relative(root,page)
    return artifacts,clips,measured
