"""Actual object/bone world-pose regression for multiple-turn quaternion baking.

Run with Python and an existing Blender4.5; --output selects fresh evidence.
No installation, rendering, source asset, service or production approval is used.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def native_case(output, scripts, action_scripts):
    import bpy
    from mathutils import Matrix, Quaternion, Vector
    sys.path.insert(0, str(scripts))
    import authoring
    report = {'status':'pass','actualBlender':True,'blenderVersion':bpy.app.version_string,
              'sampleToleranceMetres':1e-5,'profiles':[],'rendered':False,'productionAcceptance':False}

    def cube(name, origin, world_vertices=False):
        vertices=[(.05+x*.06,y*.02,z*.02) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
        if world_vertices:vertices=[tuple(a+b for a,b in zip(value,origin)) for value in vertices]
        mesh=bpy.data.meshes.new(name+'Mesh')
        mesh.from_pydata(vertices,[],[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)])
        mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
        if not world_vertices:obj.location=origin
        return obj

    for profile in ['articulated','skinned']:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        root=bpy.data.objects.new('Machine',None);bpy.context.scene.collection.objects.link(root)
        pivots={'GearPositive':(-.25,0,.45),'GearNegative':(.25,0,.45),'Ordinary':(0,0,.2),'Static':(.6,0,.45)}
        made={name:cube(name,pivot,profile=='skinned') for name,pivot in pivots.items()}
        if profile=='skinned':
            for name,obj in made.items():obj.name='Geo.'+name
        for obj in made.values():obj.parent=root
        clips=[]
        for identifier,end,offset,loop in [('loop',120,0,True),('a',60,0,False),('b',60,2.5,False)]:
            channels=[];kind='bone' if profile=='skinned' else 'node'
            for name,speed in [('GearPositive',1),('GearNegative',-.8)]:
                channels.append({'target':{kind:name},'property':'rotation_quaternion','keyframes':[
                    [frame,[0,math.sin(math.pi*speed*(offset+frame/24)),0,math.cos(math.pi*speed*(offset+frame/24))]] for frame in range(end+1)]})
            triangle=lambda frame:.02*(1-abs((offset+frame/24-2.5)/2.5))
            channels.extend([
                {'target':{kind:'Ordinary'},'property':'location','keyframes':[[frame,[triangle(frame),0,0 if profile=='skinned' else .2]] for frame in range(end+1)]},
                {'target':{kind:'Ordinary'},'property':'rotation_quaternion','keyframes':[[frame,[math.sin(.1),0,0,math.cos(.1)]] for frame in range(end+1)]},
                {'target':{kind:'Ordinary'},'property':'scale','keyframes':[[frame,[1+triangle(frame),1,1]] for frame in range(end+1)]}])
            clips.append({'id':identifier,'role':'winding-regression','loop':loop,'rootMotion':'in-place','startFrame':0,'endFrame':end,'channels':channels,'markers':[]})
        recipe={'profile':profile,'fps':24,'rig':{'mode':'preserve','rootNode':'Machine'},
          'parts':[{'node':name,'parent':'Machine'} for name in pivots] if profile=='articulated' else [],'anchors':[],'clips':clips,
          'parameters':[],'states':[],'transitions':[],'effects':[],
          'budgets':{'maxTriangles':100,'maxBones':4 if profile=='skinned' else 0,'maxInfluences':1 if profile=='skinned' else 0,
          'maxMaterials':1,'maxTextureBytes':1024,'maxRuntimeBytes':1048576,'maxSamples':10000,'maxClipSeconds':5,'maxClips':3}}
        if profile=='skinned':
            bones=[{'name':'root','head':[0,0,0],'tail':[0,.1,0]}]+[
                {'name':name,'head':list(pivot),'tail':[pivot[0],.2,pivot[2]],'parent':'root'} for name,pivot in pivots.items() if name!='Static']
            recipe['rig']={'mode':'declared','node':'MotionRig','rootNode':'Machine','rootBone':'root','bones':bones,
              'skinning':{'method':'declared-groups','groups':[{'node':obj.name,'bone':'root' if name=='Static' else name,'weights':[[index,1] for index in range(8)]} for name,obj in made.items()]}}
        bpy.context.view_layer.update()
        authoring.prepare(recipe);authoring.build_rig(recipe);authoring.author(recipe)
        case={'profile':profile,'stages':[]}
        for stage in ['author','bake']:
            if stage=='bake':authoring.bake(recipe)
            stage_result={'stage':stage,'status':'pass','clips':[],'witnessSamples':0}
            for clip,offset in zip(clips,[0,0,2.5]):
                authoring.activate(clip)
                maximum={name:{'full':0.0,'half':0.0} for name in pivots}
                failures=[]
                for index in range(2*clip['endFrame']+1):
                    frame=index/2;time=offset+frame/24
                    bpy.context.scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
                    for name,pivot in pivots.items():
                        if profile=='skinned':
                            rig=bpy.data.objects['MotionRig']
                            matrix=rig.matrix_world@rig.pose.bones['root' if name=='Static' else name].matrix
                            point=Vector((.7,0,.45) if name=='Static' else (.1,0,0))
                        else:matrix=made[name].matrix_world;point=Vector((.1,0,0))
                        actual=matrix@point
                        if name in ('GearPositive','GearNegative'):
                            theta=2*math.pi*(1 if name=='GearPositive' else -.8)*time
                            expected=Vector((pivot[0]+.1*math.cos(theta),0,pivot[2]-.1*math.sin(theta)))
                        elif name=='Ordinary':
                            shift=.02*(1-abs((time-2.5)/2.5))
                            expected=Matrix.Translation(Vector((shift,0,.2)))@Quaternion((1,0,0),.2).to_matrix().to_4x4()@Matrix.Diagonal((1+shift,1,1,1))@point
                        else:expected=Vector((.7,0,.45))
                        error=(actual-expected).length;partition='full' if index%2==0 else 'half'
                        maximum[name][partition]=max(maximum[name][partition],error)
                        stage_result['witnessSamples']+=1
                        if error>1e-5:
                            failures.append({'target':name,'frame':frame,'errorMetres':error,'actual':list(actual),'expected':list(expected)})
                stage_result['clips'].append({'id':clip['id'],'maximumErrorsMetres':maximum,'failedSamples':failures})
                if failures:stage_result['status']='failed';report['status']='failed'
            case['stages'].append(stage_result)
            assert stage_result['witnessSamples']==1932, 'Empty/incomplete world-pose discovery'
        report['profiles'].append(case)
        if any(stage['status']!='pass' for stage in case['stages']):continue

        # Real export/import and composition exercise both object and pose-bone paths.
        folder=output/profile;folder.mkdir()
        source=folder/'input.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source),check_existing=False)
        motion_out=folder/'motion';motion_out.mkdir()
        artifacts,_=authoring.export_package({'asset':profile,'version':'1'},output,source,motion_out,recipe)
        motion=json.loads((output/artifacts['package']).read_bytes())
        if Path(sys.modules['core'].__file__).parent!=action_scripts:
            del sys.modules['core']
        sys.path.insert(0,str(action_scripts))
        import composition
        from core import load_scene
        expanded=[]
        for identifier,names in [('whole',['loop']),('joined',['a','b'])]:
            cursor=0;steps=[]
            for index,name in enumerate(names):
                clip=next(value for value in motion['clips'] if value['id']==name)
                steps.append({'id':'step'+str(index),'clip':name,'occurrence':0,'start':cursor,'end':cursor+clip['duration'],
                  'sourceStart':0,'sourceEnd':clip['duration'],'rate':1,'blendIn':0,'motionSha256':clip['motionSha256']})
                cursor+=clip['duration']
            expanded.append({'id':identifier,'clip':identifier,'role':'winding-regression','duration':cursor,'steps':steps,'cues':[],'markers':[]})
        plan={'fps':24,'rig':motion['rig'],'anchors':[],'targets':[],'actions':expanded,
          'budgets':{'maxActions':2,'maxExpandedSteps':3,'maxFrames':10000,'maxRuntimeBytes':1048576,'maxVerificationBytes':16777216}}
        glb=output/artifacts['glb'];load_scene(glb,24)
        composition.validate_source_glb(glb,motion,plan)
        library,rest=composition.source_library(motion,plan)

        geometry_ids={}
        def geometry_check(stage,schedule,activate):
            measured={'stage':stage,'status':'pass','timeSamples':0,'maximumFullFrameErrorMetres':0,'maximumHalfFrameErrorMetres':0}
            base=[Vector((.05+x*.06,y*.02,z*.02)) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
            for name,end,offset in schedule:
                for index in range(2*end+1):
                    local=index/48;time=offset+local;activate(name,local)
                    deps=bpy.context.evaluated_depsgraph_get()
                    for part,pivot in pivots.items():
                        obj=bpy.data.objects[('Geo.' if profile=='skinned' else '')+part]
                        identity=geometry_ids.get(part)
                        candidates=[obj] if obj.type=='MESH' else [child for child in bpy.context.scene.objects if child.type=='MESH' and identity is not None and
                          (child.get('opencaw_action_mesh')==identity or child.data.get('opencaw_action_mesh')==identity)]
                        assert len(candidates)==1, 'Semantic mesh owner must have exactly one real geometry child'
                        obj=candidates[0]
                        if obj.get('opencaw_action_mesh'):geometry_ids[part]=obj['opencaw_action_mesh']
                        evaluated=obj.evaluated_get(deps);mesh=evaluated.to_mesh()
                        try:actual=[evaluated.matrix_world@vertex.co for vertex in mesh.vertices]
                        finally:evaluated.to_mesh_clear()
                        if part in ('GearPositive','GearNegative'):
                            theta=2*math.pi*(1 if part=='GearPositive' else -.8)*time
                            matrix=Matrix.Translation(Vector(pivot))@Quaternion((0,1,0),theta).to_matrix().to_4x4()
                        elif part=='Ordinary':
                            shift=.02*(1-abs((time-2.5)/2.5))
                            matrix=Matrix.Translation(Vector((shift,0,.2)))@Quaternion((1,0,0),.2).to_matrix().to_4x4()@Matrix.Diagonal((1+shift,1,1,1))
                        else:matrix=Matrix.Translation(Vector(pivot))
                        expected=[matrix@point for point in base]
                        error=max(max(min((a-b).length for b in expected) for a in actual),max(min((a-b).length for b in actual) for a in expected))
                        key='maximumFullFrameErrorMetres' if index%2==0 else 'maximumHalfFrameErrorMetres'
                        measured[key]=max(measured[key],error)
                        if error>1e-5:measured['status']='failed';report['status']='failed'
                    measured['timeSamples']+=1
            assert measured['timeSamples']>0
            case['stages'].append(measured)

        geometry_check('motion-reimport',[('loop',120,0),('a',60,0),('b',60,2.5)],
          lambda name,time:composition.sample_source(library[name],time,rest,24))
        composition.compose({'motionPackage':motion},plan)
        def activate_composed(name,time):
            composition.activate_composite(name)
            frame=time*24;bpy.context.scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
        geometry_check('compose',[('whole',120,0),('joined',120,0)],activate_composed)
        if case['stages'][-1]['status']!='pass':continue
        action_out=folder/'action';action_out.mkdir()
        action_artifacts,_,metrics=composition.export({'asset':profile,'version':'1','profile':profile},output,glb,action_out,plan)
        geometry_check('action-reimport',[('whole',120,0),('joined',120,0)],activate_composed)
        case['actionExport']={'artifacts':action_artifacts,'independentReimport':metrics['independentReimport']}
        case['motionExport']=artifacts
        case['geometryIds']=geometry_ids
    with (output/'cases.json').open('x',encoding='utf-8') as stream:stream.write(json.dumps(report,indent=2)+'\n')
    print('ACTUAL_QUATERNION_CASES',report['status'],'2 profiles; 7728 witness samples')
    if report['status']!='pass':raise AssertionError('Actual production quaternion baking corrupts sampled world poses')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--scripts-dir',type=Path,default=ROOT/'.styles/.workflows/model-to-animation/blender')
    parser.add_argument('--action-scripts-dir',type=Path,default=ROOT/'.styles/.workflows/model-to-action/blender')
    parser.add_argument('--blender-case',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else None)
    if args.blender_case:
        assert args.output and args.output.is_dir()
        native_case(args.output,args.scripts_dir.resolve(),args.action_scripts_dir.resolve())
        return
    blender=Path(os.environ.get('BLENDER_EXE') or shutil.which('blender') or 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe')
    if not blender.is_file():raise SystemExit('BLOCKED: existing Blender4.5 required; no installation attempted')
    parent=args.output or ROOT/'.opencaw/.cache/tasks/model-to-animation-design/evidence'
    parent=parent.resolve();parent.relative_to(ROOT);parent.mkdir(parents=True,exist_ok=True)
    output=Path(tempfile.mkdtemp(prefix='q-',dir=parent))
    temp=output/'temp';temp.mkdir()
    env=dict(os.environ);env.update({'TEMP':str(temp),'TMP':str(temp),'TMPDIR':str(temp),'PYTHONDONTWRITEBYTECODE':'1','OMP_NUM_THREADS':'2'})
    command=[str(blender),'--background','--factory-startup','--disable-autoexec','--threads','2','--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--blender-case','--output',str(output),'--scripts-dir',str(args.scripts_dir.resolve()),'--action-scripts-dir',str(args.action_scripts_dir.resolve())]
    process=subprocess.run(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    (output/'process.log').write_bytes(process.stdout)
    report=json.loads((output/'cases.json').read_bytes()) if (output/'cases.json').is_file() else None
    valid=process.returncode==0 and report is not None and report['status']=='pass' and len(report['profiles'])==2
    metadata={'status':'pass' if valid else 'failed','exitCode':process.returncode,'command':command,'actualBlender':True,
      'sourceSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'productionAuthoringSha256':hashlib.sha256((args.scripts_dir/'authoring.py').read_bytes()).hexdigest(),
      'productionCompositionSha256':hashlib.sha256((args.action_scripts_dir/'composition.py').read_bytes()).hexdigest(),
      'logSha256':hashlib.sha256(process.stdout).hexdigest(),'casesSha256':hashlib.sha256((output/'cases.json').read_bytes()).hexdigest() if report else None,
      'productionAcceptance':False,'rendered':False}
    (output/'process.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    print('Evidence:',output)
    print(process.stdout.decode(errors='replace')[-3000:])
    if not valid:raise SystemExit(1)


if __name__=='__main__':main()
