"""Fixed audited MODEL_TO_ACTION Blender4.5 entrypoint."""
import json
from pathlib import Path
import sys

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))

from core import digest, inventory, load_job, load_scene, relative, save_blend, save_json
from composition import compose, export, source_library, validate_source_glb, verification_preflight


def main():
    job,root,source,output,result,plan=load_job()
    before=digest(source)
    source_check=validate_source_glb(source,job['motionPackage'],plan) if job['operation'] in ('inspect','compose') else None
    load_scene(source,plan['fps'])
    operation=job['operation'];actions=[];findings=[]
    if operation=='inspect':
        source_library(job['motionPackage'],plan)
        measured=inventory(job['profile'])
        demand=verification_preflight(plan)
        measured['verificationPreflight']={'totalBytes':demand['totalBytes'],'framePayloadBytes':demand['framePayloadBytes'],'frameCount':demand['frameCount']}
        report=output/'inspection.json';save_json(report,{'actualSourceGlb':True,'inputSha256':before,'metrics':measured,'requiredClips':sorted({step['clip'] for action in plan['actions'] for step in action['steps']}),'humanApproval':'pending'})
        artifacts={'report':relative(root,report)}
    elif operation=='compose':
        actions=compose(job,plan);measured=inventory(job['profile'])
        artifacts={'blend':save_blend(root,output)}
    elif operation=='export':
        artifacts,actions,measured=export(job,root,source,output,plan)
    else:
        from review import review
        artifacts,data,measured=review(job,root,source,output,plan)
        findings.append({'severity':'information','code':'technical-cue-proxies','message':'Blender cue proxies do not certify selected-engine VFX or human runtime acceptance.'})
    if digest(source)!=before:raise ValueError('Fixed authoring changed its immutable input')
    if source_check is not None:measured['sourceRootChannelValidation']=source_check
    report=output/'report.json'
    save_json(report,{'schemaVersion':'opencaw-action-stage-summary/v1','operation':operation,'metrics':measured,'findings':findings,'humanApproval':'pending'})
    artifacts.setdefault('report',relative(root,report))
    save_json(result,{'schemaVersion':'opencaw-action-stage/v1','operation':operation,'inputSha256':before,'artifacts':artifacts,'actions':actions,'metrics':measured,'findings':findings})
    print(json.dumps({'operation':operation,'status':'produced','humanApproval':'pending','result':relative(root,result)}))


if __name__=='__main__':main()
