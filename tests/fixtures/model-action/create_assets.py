"""Original action fixtures using OpenCaw's existing controlled humanoid rig.

Run inside existing Blender4.5: --output REPOSITORY_LOCAL_DIRECTORY.
No third-party artwork, clip vendor, model provider or runtime acceptance.
"""
import argparse
import copy
import json
import math
from pathlib import Path
import runpy
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]


def compile_fixture(recipe,motion):
    """Independent fixture oracle; production compilation belongs to native CLI."""
    clips={clip['id']:clip for clip in motion['clips']}
    actions=[]
    for declared in recipe['actions']:
        steps=[];markers=[];duration=0
        for step in declared['steps']:
            for occurrence in range(step['repeat']):
                start=duration-step['blendIn'];end=start+(step['to']-step['from'])/step['rate']
                expanded={'id':step['id'],'clip':step['clip'],'occurrence':occurrence,'start':start,'end':end,
                          'sourceStart':step['from'],'sourceEnd':step['to'],'rate':step['rate'],'blendIn':step['blendIn'],
                          'motionSha256':clips[step['clip']]['motionSha256']}
                steps.append(expanded);duration=end
                markers.extend([{'id':step['id']+'.'+str(occurrence)+'.start','at':start,'name':'step-enter','step':step['id'],'occurrence':occurrence},
                                {'id':step['id']+'.'+str(occurrence)+'.end','at':end,'name':'step-exit','step':step['id'],'occurrence':occurrence}])
                for index,marker in enumerate(clips[step['clip']]['markers']):
                    if step['from']<=marker['time']<=step['to']:
                        markers.append({'id':step['id']+'.'+str(occurrence)+'.marker'+str(index),'at':start+(marker['time']-step['from'])/step['rate'],
                                        'name':marker['event'],'step':step['id'],'occurrence':occurrence})
        def resolve(address):
            step=next(item for item in steps if item['id']==address['step'] and item['occurrence']==address['occurrence'])
            if 'offset' in address:return step['start']+address['offset']
            matches=[marker for marker in clips[step['clip']]['markers'] if marker['event']==address['marker'] and step['sourceStart']<=marker['time']<=step['sourceEnd']]
            if len(matches)!=1:raise ValueError('Fixture marker must be unique')
            return step['start']+(matches[0]['time']-step['sourceStart'])/step['rate']
        cues=[]
        for cue in declared['cues']:
            result=copy.deepcopy(cue);result['start']=resolve(cue['start']);result['end']=resolve(cue['end']);cues.append(result)
        actions.append({'id':declared['id'],'role':declared['role'],'clip':declared['id'],'duration':duration,'steps':steps,'cues':cues,
                        'markers':sorted(markers,key=lambda value:(value['at'],value['id']))})
    return {'schemaVersion':'opencaw-action-package/v1','asset':'sequence-fixture','version':'v1','profile':motion['profile'],'fps':recipe['fps'],
            'coordinateSystem':{'runtimeUp':'+Y','runtimeForward':'+Z'},'rig':motion['rig'],'anchors':motion['anchors'],'targets':recipe['targets'],
            'budgets':recipe['budgets'],'actions':actions,'sourceMotion':{'packageSha256':'0'*64,'modelSha256':motion['model']['sha256'],
                'rigId':motion['rig']['id'],'clips':[{'id':clip['id'],'motionSha256':clip['motionSha256']} for clip in motion['clips']]},
            'engine':{'effectiveEngine':'THREEJS'},'verification':{'status':'pending'}}


def action_recipe():
    def step(identifier,clip,blend=0,repeat=1,rate=1,low=0,high=1):
        return {'id':identifier,'clip':clip,'from':low,'to':high,'rate':rate,'repeat':repeat,'blendIn':blend}
    def address(step,offset=0,marker=None):
        return {'step':step,'occurrence':0,**({'marker':marker} if marker is not None else {'offset':offset})}
    return {'schemaVersion':1,'fps':24,'actions':[
        {'id':'dance-pattern','role':'dance','steps':[step('left','dance-left',repeat=2),step('right','dance-right',blend=.25,repeat=2)],'cues':[]},
        {'id':'chained-combo','role':'combo','steps':[step('jab-left','punch-left'),step('jab-right','punch-right',blend=.125),step('finishing-kick','kick',blend=.125)],
         'cues':[{'id':'contact-sparks','type':'particles','anchor':'hand.cast','start':address('jab-left',marker='contact'),'end':address('jab-left',.75),
                  'color':'#FFD060','radius':.12,'capacity':32,'rate':24,'seed':7}]},
        {'id':'charge-cast','role':'cast','steps':[step('charge','charge'),step('cast','cast',blend=.125),step('recover','idle',blend=.125)],
         'cues':[{'id':'charge-orb','type':'orb','anchor':'hand.cast','start':address('charge'),'end':address('cast',marker='release'),'color':'#FF6010','radius':.2},
                 {'id':'fireball','type':'projectile','anchor':'hand.cast','start':address('cast',marker='release'),'end':address('recover',.75),
                  'color':'#FF8020','radius':.16,'target':'fixed-target'}]}],
        'targets':[{'id':'fixed-target','mode':'fixed-world-point','maxDistance':100}],
        'budgets':{'maxActions':16,'maxStepsPerAction':64,'maxExpandedSteps':256,'maxActionSeconds':120,'maxEffects':64,'maxParticles':2048,
                   'maxFrames':20000,'maxReviewFrames':1200,'maxRuntimeBytes':33554432,'timeoutSeconds':180,'maxLogBytes':16777216,'maxAttempts':16},
        'review':{'fps':4,'resolution':[128,128],'cameras':['front','three-quarter'],'targets':{'fixed-target':[2,1.3,2]}},
        'provenance':{'provider':'native-blender','rights':'Original controlled engineering fixture; no external artwork or animation'}}


def mechanical_sources(output,authoring,load_scene,digest,relative):
    """Real articulated/rigid owned clips; no actor rig or combat assumptions."""
    fixtures={}
    for name in ('car','ship'):
        recipe=json.loads((output/('raw/'+name+'-recipe.json')).read_text())
        load_scene(output/('raw/'+name+'.glb'),recipe['fps'])
        authoring.prepare(recipe);authoring.build_rig(recipe);authoring.author(recipe);authoring.bake(recipe)
        folder=output/(name+'-source');folder.mkdir()
        artifacts,_=authoring.export_package({'asset':'original-'+name+'-motion-fixture','version':'v1'},output,output/('raw/'+name+'.glb'),folder,recipe)
        package_path=output/artifacts['package'];motion=json.loads(package_path.read_text())
        motion['engine']={'effectiveEngine':'THREEJS','note':'Original controlled fixture, no runtime acceptance'}
        package_path.write_text(json.dumps(motion,indent=2)+'\n',encoding='utf-8')
        selected=['drive'] if name=='car' else ['cruise','boost','warp-enter','warp-sustain','warp-exit']
        clips={clip['id']:clip for clip in motion['clips']}
        action=action_recipe();action['targets']=[];action['review']['targets']={}
        action['actions']=[{'id':name+'-sequence','role':'vehicle-presentation','steps':[
            {'id':identifier,'clip':identifier,'from':0,'to':clips[identifier]['duration'],'rate':1,'repeat':1,'blendIn':0 if index==0 else .25}
            for index,identifier in enumerate(selected)],'cues':[]}]
        plan=compile_fixture(action,motion);plan['sourceMotion']['packageSha256']=digest(package_path)
        plan['motion']={'path':relative(output,package_path),'sha256':digest(package_path)}
        for suffix,value in [('action-recipe',action),('compiled-plan',plan)]:
            (output/(name+'-'+suffix+'.json')).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
        fixtures[name]={'sourceModel':artifacts['glb'],'motionPackage':artifacts['package'],'compiledPlan':name+'-compiled-plan.json','actionRecipe':name+'-action-recipe.json'}
    return fixtures


def main():
    import bpy
    from mathutils import Matrix
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);output=Path(args.output).resolve()
    output.relative_to(ROOT)
    if output.exists() and any(output.iterdir()):raise ValueError('Use a new fixture directory')
    output.mkdir(parents=True,exist_ok=True)
    original=ROOT/'tests/fixtures/model-animation/create_assets.py'
    old_argv=sys.argv;sys.argv=[str(original),'--','--output',str(output/'raw')]
    runpy.run_path(str(original),run_name='__main__');sys.argv=old_argv
    sys.path.insert(0,str(ROOT/'.styles/.workflows/model-to-animation/blender'))
    from core import digest,load_scene,relative
    import authoring
    recipe=json.loads((output/'raw/humanoid-recipe.json').read_text())
    recipe['fps']=12;recipe['anchors']=[]
    def q(axis,angle):
        result=[0,0,0,math.cos(angle/2)];result[axis]=math.sin(angle/2);return result
    zero=[0,0,0,1]
    def channel(bone,axis,values):
        return {'target':{'bone':bone},'property':'rotation_quaternion','keyframes':[[0,q(axis,values[0])],[6,q(axis,values[1])],[12,q(axis,values[2])]]}
    def clip(identifier,channels,markers=None):
        return {'id':identifier,'role':identifier,'loop':False,'rootMotion':'in-place','startFrame':0,'endFrame':12,'channels':channels,'markers':markers or []}
    recipe['clips']=[
        clip('idle',[channel('spine',0,[0,.04,0])]),
        clip('dance-left',[channel('hips',2,[0,.25,0]),channel('upperarm.L',0,[0,.4,0])]),
        clip('dance-right',[channel('hips',2,[0,-.25,0]),channel('upperarm.R',0,[0,-.4,0])]),
        clip('punch-left',[channel('upperarm.L',2,[0,-.8,0]),channel('forearm.L',0,[0,.25,0])],[{'time':.5,'event':'contact'}]),
        clip('punch-right',[channel('upperarm.R',2,[0,.8,0]),channel('forearm.R',0,[0,-.25,0])],[{'time':.5,'event':'contact'}]),
        clip('kick',[channel('thigh.R',0,[0,1.1,0]),channel('shin.R',0,[0,-.2,0])],[{'time':.5,'event':'contact'}]),
        clip('charge',[channel('upperarm.L',2,[0,-.5,-.5]),channel('forearm.L',0,[0,.6,.6])]),
        clip('cast',[channel('upperarm.L',2,[-.5,-1.2,0]),channel('forearm.L',0,[.6,.1,0])],[{'time':.5,'event':'release'}])]
    recipe['requiredClips']=[clip['id'] for clip in recipe['clips']]
    recipe['states']=[{'id':clip['id'],'clip':clip['id']} for clip in recipe['clips']];recipe['transitions']=[];recipe['effects']=[];recipe['parameters']=[]
    load_scene(output/'raw/humanoid.glb',recipe['fps']);authoring.prepare(recipe);authoring.build_rig(recipe)
    rig=bpy.data.objects['MotionRig'];socket=bpy.data.objects.new('HandCastSocket',None);bpy.context.scene.collection.objects.link(socket)
    socket.parent=rig;socket.parent_type='BONE';socket.parent_bone='forearm.L';socket.matrix_parent_inverse=Matrix.Identity(4);socket.location=(0,0,0)
    recipe['anchors']=[{'id':'hand.cast','node':'HandCastSocket','position':[0,0,0]},{'id':'body.center','node':'Humanoid','position':[0,0,1]}]
    authoring.prepare(recipe);authoring.author(recipe);authoring.bake(recipe)
    source_dir=output/'source';source_dir.mkdir()
    source_job={'asset':'original-action-motion-fixture','version':'v1'}
    artifacts,clips=authoring.export_package(source_job,output,output/'raw/humanoid.glb',source_dir,recipe)
    package_path=output/artifacts['package'];motion=json.loads(package_path.read_text())
    motion['engine']={'effectiveEngine':'THREEJS','note':'Original test asset declares selected-engine intent; actual host resolution and runtime acceptance are separate'}
    package_path.write_text(json.dumps(motion,indent=2)+'\n',encoding='utf-8')
    action=action_recipe();plan=compile_fixture(action,motion);plan['sourceMotion']['packageSha256']=digest(package_path)
    plan['motion']={'path':relative(output,package_path),'sha256':digest(package_path)}
    for name,value in [('motion-recipe.json',recipe),('action-recipe.json',action),('compiled-plan.json',plan)]:
        (output/name).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    fixture={'sourceModel':artifacts['glb'],'motionPackage':artifacts['package'],'motionRecipe':relative(output,output/'motion-recipe.json'),
             'actionRecipe':relative(output,output/'action-recipe.json'),'compiledPlan':relative(output,output/'compiled-plan.json'),
             'note':'Original actual Blender-produced fixture; no mocked geometry or authenticated human/runtime acceptance'}
    fixture['mechanical']=mechanical_sources(output,authoring,load_scene,digest,relative)
    (output/'fixtures.json').write_text(json.dumps(fixture,indent=2)+'\n',encoding='utf-8')
    print('ORIGINAL_ACTION_FIXTURE',str(output/'fixtures.json'))


if __name__=='__main__':main()
