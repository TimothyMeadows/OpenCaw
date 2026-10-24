"""Audited MODEL_TO_ANIMATION Blender4.5 native batch entrypoint."""
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from core import confined, digest, inventory, load_job, load_scene, relative, rig_identity, save_blend, save_json
import authoring


def main():
    job,root,source,output,result,recipe=load_job()
    before=digest(source)
    load_scene(source,recipe["fps"])
    import bpy
    bpy.context.scene.render.fps=recipe["fps"]
    operation=job["operation"]
    artifacts={}
    findings=[]
    clips=[]
    if operation=="inspect":
        findings.append({"severity":"review","code":"animation-readiness","message":"Inspect fused geometry, hidden parts, topology, pose, materials and intended joints. Structural inventory does not certify animatability."})
        if recipe["profile"]=="articulated":
            for part in recipe["parts"]:authoring.node(part.get("node"))
    elif operation=="prepare":
        authoring.prepare(recipe)
    elif operation=="rig":
        rig=authoring.build_rig(recipe)
        findings.append({"severity":"review","code":"rig-review","message":"Review actual hierarchy, declared fit and extreme deformation before authoring or retargeting.","rigId":rig["id"]})
    elif operation=="author":
        clips=authoring.author(recipe,job.get("revisionClip"))
    elif operation=="retarget":
        motion_source=confined(root,job.get("motionSource"))
        if motion_source.suffix.lower()!=".glb" or not motion_source.is_file():raise ValueError("Retarget requires an immutable actual source GLB")
        clips=authoring.retarget(recipe,root,motion_source,job.get("mapping"))
    elif operation=="bake":
        clips=authoring.bake(recipe)
    elif operation=="export":
        artifacts,clips=authoring.export_package(job,root,source,output,recipe)
    elif operation=="review":
        from review import review
        artifacts,clips,measured=review(job,root,source,output,recipe)
    else:raise ValueError("Unknown operation")
    if operation in ("prepare","rig","author","retarget","bake"):
        artifacts["blend"]=save_blend(root,output)
    measured=inventory(recipe,recipe["profile"]=="skinned" and operation not in ("inspect","prepare"))
    if operation=="review":
        # Review helper cameras/lights are evidence, not runtime mesh/rig changes.
        measured["reviewFrames"]=len([key for key in artifacts if key.startswith("frame-")])
    if digest(source)!=before:raise ValueError("Native stage modified its immutable input")
    report={"schemaVersion":"opencaw-motion-stage/v1","operation":operation,"profile":recipe["profile"],"inputSha256":before,"artifacts":artifacts,"metrics":measured,"findings":findings,"clips":clips,"blenderVersion":bpy.app.version_string,"rig":rig_identity(),"verification":{"human":"pending","independent":"pending","runtime":"not-run"}}
    report_path=output/"report.json"
    save_json(report_path,report)
    report["artifacts"]["report"]=relative(root,report_path)
    save_json(result,report)
    print("MOTION_STAGE_COMPLETE",operation,len(artifacts),"artifacts; human/runtime acceptance remains pending")


if __name__=="__main__":main()
