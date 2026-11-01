"""Actual Blender4.5 motion stages on original controlled geometry.

These tests do not certify production art, retarget quality or game behavior.
"""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import re

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
SCRIPTS=ROOT/'runtime/bubo/resources/model-to-animation/blender'
BLENDER=os.environ.get('BLENDER_EXE') or shutil.which('blender') or 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'


def glb_json(path):
    data=path.read_bytes();size,kind=struct.unpack_from('<II',data,12)
    assert kind==0x4e4f534a
    return json.loads(data[20:20+size])


class MotionProduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(BLENDER).is_file():raise unittest.SkipTest('BLOCKED: Blender4.5 unavailable; no installation attempted')
        evidence=ROOT/'.hephaera/.cache/tasks/model-to-animation-design/evidence';evidence.mkdir(parents=True,exist_ok=True)
        cls.work=Path(tempfile.mkdtemp(prefix='blender-motion-tests-',dir=evidence));cls.project=cls.work/'project';cls.project.mkdir()
        cls.calls=[]
        cls.run_blender(ROOT/'tests/fixtures/model-animation/create_assets.py',['--output',str(cls.project/'inputs')],'create-fixtures')
        cls.recipes={name:json.loads((cls.project/'inputs'/(name+'-recipe.json')).read_text()) for name in ('humanoid','ship','car')}
        cls.stages={}
        for name in ('humanoid','ship','car'):
            recipe=cls.recipes[name];current='inputs/'+name+'.glb';cls.stages[name]={}
            for operation in ('inspect','prepare','rig','author','bake','export','review'):
                output=cls.stage(name,operation,current,recipe)
                cls.stages[name][operation]=output
                if operation=='export':current=output['artifacts']['glb']
                elif 'blend' in output['artifacts']:current=output['artifacts']['blend']
        (cls.work/'fixture-outputs.json').write_text(json.dumps(cls.stages,indent=2),encoding='utf8')
        (evidence/'blender-motion-latest.txt').write_text(str(cls.work),encoding='utf8')

    @classmethod
    def tearDownClass(cls):
        (cls.work/'commands.json').write_text(json.dumps(cls.calls,indent=2),encoding='utf8')

    @classmethod
    def run_blender(cls,script,options,name,success=True):
        cmd=[BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(script),'--',*options]
        run=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
        log=cls.work/(name+'.log');log.write_text(run.stdout,encoding='utf8');cls.calls.append({'args':cmd,'exitCode':run.returncode,'log':str(log)})
        if success and run.returncode!=0:raise AssertionError(run.stdout[-6000:])
        if not success and run.returncode==0:raise AssertionError('Invalid native job unexpectedly passed')
        return run

    @classmethod
    def stage(cls,asset,operation,source,recipe,success=True,**extras):
        identifier=asset+'-'+operation+'-'+str(len(cls.calls));folder='.art-staging/model-to-animation/'+asset+'/v1/attempts/'+identifier
        job={'schemaVersion':1,'root':str(cls.project),'operation':operation,'input':source,'outputDir':folder,'result':folder+'/result.json','asset':asset,'version':'v1','profile':recipe['profile'],'recipe':copy.deepcopy(recipe),'motionSource':None,'mapping':None,**extras}
        path=cls.project/('job-'+identifier+'.json');path.write_text(json.dumps(job),encoding='utf8')
        process=cls.run_blender(SCRIPTS/'motion.py',['--job',str(path)],identifier,success)
        result=cls.project/job['result']
        if not success:
            if result.exists():raise AssertionError('Failed stage emitted a passing-looking result')
            return process
        value=json.loads(result.read_text());assert value['operation']==operation and value['schemaVersion']=='hephaera-motion-stage/v1'
        for artifact in value['artifacts'].values():assert (cls.project/artifact).is_file(),artifact
        return value

    def test_01_actual_skinned_motion_set_and_independent_export(self):
        stages=self.stages['humanoid'];export=stages['export'];package=json.loads((self.project/export['artifacts']['package']).read_text())
        self.assertEqual(len(package['clips']),9)
        self.assertEqual({item['id'] for item in package['clips']},set(self.recipes['humanoid']['requiredClips']))
        self.assertGreater(stages['rig']['metrics']['bones'],0)
        self.assertEqual(stages['rig']['metrics']['unweightedVertices'],0)
        self.assertGreater(stages['rig']['metrics']['maxInfluences'],1)
        doc=glb_json(self.project/export['artifacts']['glb']);self.assertTrue(doc['skins'][0]['joints']);self.assertEqual(len(doc['animations']),9)
        for clip in package['clips']:
            self.assertGreater(clip['exportedChannels'],0);self.assertEqual(clip['rootDisplacement'],[0,0,0]);self.assertEqual(clip['duration'],.5)
        self.assertEqual(package['verification']['status'],'pending')
        self.assertEqual(package['rig']['rootBone'],'root');self.assertEqual(package['rig']['rootNode'],'MotionRoot')

    def test_02_full_range_and_transition_proofs_have_real_frames(self):
        path=self.project/self.stages['humanoid']['review']['artifacts']['reviewReport'];report=json.loads(path.read_text())
        self.assertEqual(report['frameCount'],report['requestedFrameCount']);self.assertGreater(report['frameCount'],60)
        self.assertEqual(len([p for p in report['packets'] if p['type']=='clip']),9)
        self.assertEqual(len([p for p in report['packets'] if p['type']=='transition']),3)
        for packet in report['packets']:
            times=[item['time'] for item in packet['frames']];self.assertEqual(min(times),0);self.assertEqual(max(times),packet['duration'])
            for image in packet['frames']:self.assertEqual(hashlib.sha256((self.project/image['path']).read_bytes()).hexdigest(),image['sha256'])
        self.assertEqual(report['humanApproval'],'pending');self.assertEqual(report['runtimeVerification'],'not-run')
        page=(self.project/self.stages['humanoid']['review']['artifacts']['review']).read_text()
        source=re.findall(r'<script>(.*?)</script>',page,re.S)[0]
        script=self.work/'preview-player.js';script.write_text(source,encoding='utf8')
        parsed=subprocess.run(['node','--check',str(script)],capture_output=True,text=True)
        self.assertEqual(parsed.returncode,0,parsed.stderr)

    def test_03_rigid_ship_has_no_fake_skin_and_explicit_speed_effects(self):
        export=self.stages['ship']['export'];package=json.loads((self.project/export['artifacts']['package']).read_text());doc=glb_json(self.project/export['artifacts']['glb'])
        self.assertEqual(package['rig']['boneCount'],0);self.assertEqual(package['budgets']['maxBones'],0);self.assertFalse(doc.get('skins'))
        self.assertEqual(len(package['clips']),5);self.assertTrue(package['effects']);self.assertEqual(package['anchors'][0]['node'],'anchor.exhaust.primary')
        anchor=next(item for item in doc['nodes'] if item['name']=='anchor.exhaust.primary')
        self.assertEqual(anchor['translation'],[0,0,-1])
        self.assertEqual(package['coordinateSystem']['runtimeUp'],'+Y');self.assertEqual(package['coordinateSystem']['runtimeForward'],'+Z')

    def test_04_car_preserves_real_part_hierarchy_and_wheel_drivers(self):
        export=self.stages['car']['export'];package=json.loads((self.project/export['artifacts']['package']).read_text());doc=glb_json(self.project/export['artifacts']['glb'])
        self.assertEqual(package['profile'],'articulated');self.assertEqual(package['rig']['boneCount'],0)
        wheel_names={binding['node'] for binding in package['parameters'][0]['bindings']}
        self.assertEqual(len(wheel_names),4);self.assertTrue(wheel_names<={node['name'] for node in doc['nodes']})
        animated={binding['node'] for clip in package['clips'] for binding in clip['bindings']};self.assertFalse(wheel_names&animated)
        anchor=next(item for item in doc['nodes'] if item['name']=='anchor.wheel.front-left.contact')
        self.assertAlmostEqual(anchor['translation'][1],-.22,places=5)

    def test_05_actual_retarget_bake_and_export(self):
        recipe=copy.deepcopy(self.recipes['humanoid']);names=[bone['name'] for bone in recipe['rig']['bones']]
        mapping={'schemaVersion':1,'provider':'owned','rights':{'authorized':True,'license':'Original controlled fixture','source':'adobe-clay-building-study','notes':'No Adobe dependencies; the material represents ordinary substance.'},'rootTranslationScale':1,'bones':[{'source':name,'target':name,'rotationOffset':[0,0,0,1]} for name in names],'clips':[{'id':clip['id'],'sourceClip':clip['id']} for clip in recipe['clips']]}
        donor=self.stages['humanoid']['export']['artifacts']['glb'];rig=self.stages['humanoid']['rig']['artifacts']['blend']
        result=self.stage('humanoid','retarget',rig,recipe,motionSource=donor,mapping=mapping)
        self.assertEqual(len(result['clips']),9)
        baked=self.stage('humanoid','bake',result['artifacts']['blend'],recipe)
        exported=self.stage('humanoid','export',baked['artifacts']['blend'],recipe)
        self.assertEqual(len(glb_json(self.project/exported['artifacts']['glb'])['animations']),9)

    def test_06_unweighted_declared_rig_is_rejected(self):
        recipe=copy.deepcopy(self.recipes['humanoid'])
        for group in recipe['rig']['skinning']['groups']:group['weights']=[pair for pair in group['weights'] if pair[0]!=0]
        run=self.stage('humanoid','rig',self.stages['humanoid']['prepare']['artifacts']['blend'],recipe,False)
        self.assertIn('unweighted vertex',run.stdout)

    def test_07_missing_independent_part_is_rejected(self):
        recipe=copy.deepcopy(self.recipes['car']);recipe['parts'][1]['node']='MissingWheel'
        run=self.stage('car','prepare','inputs/car.glb',recipe,False);self.assertIn('missing',run.stdout)

    def test_08_constant_named_motion_and_bad_quaternion_are_rejected(self):
        recipe=copy.deepcopy(self.recipes['ship']);recipe['clips'][0]['channels'][0]['keyframes']=[[0,[0,0,0,1]],[3,[0,0,0,1]],[6,[0,0,0,1]]]
        run=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe,False);self.assertIn('no meaningful',run.stdout)
        recipe['clips'][0]['channels'][0]['keyframes'][1][1]=[0,0,0,0]
        run=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe,False);self.assertIn('normalized',run.stdout)

    def test_09_loop_and_root_motion_ownership_are_checked(self):
        recipe=copy.deepcopy(self.recipes['ship']);recipe['clips'][0]['channels'][0]['keyframes'][-1][1]=[0,.2,0,(1-.04)**.5]
        run=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe,False);self.assertIn('Loop seam',run.stdout)
        recipe=copy.deepcopy(self.recipes['ship']);recipe['clips'][0]['channels']=[{'target':{'node':'MotionRoot'},'property':'location','keyframes':[[0,[0,0,0]],[3,[0,1,0]],[6,[0,0,0]]]}]
        run=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe,False);self.assertIn('authoritative root',run.stdout)

    def test_10_review_cannot_silently_skip_frames_or_overwrite(self):
        recipe=copy.deepcopy(self.recipes['ship']);recipe['budgets']['maxPreviewFrames']=1
        run=self.stage('ship','review',self.stages['ship']['export']['artifacts']['glb'],recipe,False);self.assertIn('maxPreviewFrames',run.stdout)
        command=self.calls[-1]['args'];job=Path(command[-1]);value=json.loads(job.read_text());output=self.project/value['outputDir'];output.mkdir(parents=True,exist_ok=True);(output/'result.json').write_text('{}')
        run=self.run_blender(SCRIPTS/'motion.py',['--job',str(job)],'overwrite',False);self.assertIn('immutable attempt',run.stdout)

    def test_11_bad_contact_and_joint_limit_are_rejected(self):
        recipe=copy.deepcopy(self.recipes['humanoid']);recipe['clips'][1]['contacts']=[{'target':{'bone':'forearm.L'},'start':0,'end':.5,'maxTravel':.000001}]
        run=self.stage('humanoid','author',self.stages['humanoid']['rig']['artifacts']['blend'],recipe,False);self.assertIn('Contact travel',run.stdout)
        recipe=copy.deepcopy(self.recipes['humanoid']);next(item for item in recipe['rig']['bones'] if item['name']=='thigh.L')['maxAngle']=.1
        run=self.stage('humanoid','author',self.stages['humanoid']['rig']['artifacts']['blend'],recipe,False);self.assertIn('joint angle',run.stdout)

    def test_12_excluded_provider_and_incomplete_retarget_map_are_rejected(self):
        recipe=self.recipes['humanoid'];rig=self.stages['humanoid']['rig']['artifacts']['blend'];source=self.stages['humanoid']['export']['artifacts']['glb']
        mapping={'schemaVersion':1,'provider':'adobe','rights':{'authorized':True,'license':'test'},'rootTranslationScale':1,'bones':[],'clips':[]}
        run=self.stage('humanoid','retarget',rig,recipe,False,motionSource=source,mapping=mapping);self.assertIn('supported owned/licensed',run.stdout)
        mapping['provider']='owned';run=self.stage('humanoid','retarget',rig,recipe,False,motionSource=source,mapping=mapping);self.assertIn('complete bone/clip',run.stdout)

    def test_13_path_escape_and_unowned_blend_are_rejected(self):
        recipe=self.recipes['ship'];run=self.stage('ship','inspect','../outside.glb',recipe,False);self.assertIn('repository-relative',run.stdout)
        fake=self.project/'inputs/unowned.blend';fake.write_bytes(b'BLENDER')
        run=self.stage('ship','prepare','inputs/unowned.blend',recipe,False);self.assertIn('prior working blend',run.stdout)

    def test_14_actual_deformation_and_xyzw_quarter_turn(self):
        recipe=copy.deepcopy(self.recipes['ship'])
        recipe['clips'][0]['channels'][0]['keyframes'][1][1]=[0,2**-.5,0,2**-.5]
        authored=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe)
        script=self.work/'inspect-actual-pose.py'
        result=self.work/'actual-poses.json'
        script.write_text('''import bpy,json,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
from core import load_scene,meshes
from review import restore_imported_actions
from authoring import activate
root=Path('''+repr(str(self.project))+''')
recipe=json.loads((root/'inputs/humanoid-recipe.json').read_text())
load_scene(root/'''+repr(self.stages['humanoid']['export']['artifacts']['glb'])+''',12)
restore_imported_actions(recipe);clip=next(c for c in recipe['clips'] if c['id']=='run');activate(clip)
def vertices(frame):
 bpy.context.scene.frame_set(frame);bpy.context.view_layer.update();values=[]
 for obj in meshes():
  evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
  values.extend(evaluated.matrix_world@v.co for v in data.vertices);evaluated.to_mesh_clear()
 return values
a,b=vertices(0),vertices(3);movement=max((x-y).length for x,y in zip(a,b))
load_scene(root/'''+repr(authored['artifacts']['blend'])+''',12)
recipe=json.loads((root/'inputs/ship-recipe.json').read_text());clip=recipe['clips'][0];activate(clip)
bpy.context.scene.frame_set(3);bpy.context.view_layer.update()
direction=bpy.data.objects['Hull'].rotation_quaternion@Vector((1,0,0))
Path('''+repr(str(result))+''').write_text(json.dumps({'maxSkinnedMovement':movement,'quarterTurnDirection':list(direction)}))
''',encoding='utf8')
        self.run_blender(script,[],'actual-deformation')
        value=json.loads(result.read_text());self.assertGreater(value['maxSkinnedMovement'],.05)
        for actual,expected in zip(value['quarterTurnDirection'],(0,0,-1)):self.assertAlmostEqual(actual,expected,places=5)

    def test_15_targeted_revision_preserves_actual_retargeted_other_actions(self):
        recipe=copy.deepcopy(self.recipes['humanoid']);names=[bone['name'] for bone in recipe['rig']['bones']]
        mapping={'schemaVersion':1,'provider':'owned','rights':{'authorized':True,'license':'Original controlled fixture'},'rootTranslationScale':1,'bones':[{'source':name,'target':name,'rotationOffset':[0,0,.3,(1-.09)**.5] if name=='spine' else [0,0,0,1]} for name in names],'clips':[{'id':clip['id'],'sourceClip':clip['id']} for clip in recipe['clips']]}
        original=self.stage('humanoid','retarget',self.stages['humanoid']['rig']['artifacts']['blend'],recipe,motionSource=self.stages['humanoid']['export']['artifacts']['glb'],mapping=mapping)
        prior={clip['id']:clip['motionSha256'] for clip in original['clips']}
        # A nonidentity correction makes the retained idle pose differ from its original authoring recipe.
        original_authored={clip['id']:clip['motionSha256'] for clip in self.stages['humanoid']['author']['clips']}
        self.assertNotEqual(prior['idle'],original_authored['idle'])
        replacement=next(clip for clip in recipe['clips'] if clip['id']=='run')
        replacement['channels'][0]['keyframes'][1][1]=[.5,0,0,(1-.25)**.5]
        revised=self.stage('humanoid','author',original['artifacts']['blend'],recipe,revisionClip='run')
        current={clip['id']:clip['motionSha256'] for clip in revised['clips']}
        self.assertNotEqual(prior['run'],current['run'])
        self.assertEqual({key:value for key,value in prior.items() if key!='run'},{key:value for key,value in current.items() if key!='run'})

    def test_16_declared_vendor_url_is_excluded_without_material_false_positives(self):
        recipe=copy.deepcopy(self.recipes['ship']);recipe['provenance']={'provider':'owned','source':'https://www.mixamo.com/source','notes':'ordinary art'}
        run=self.stage('ship','inspect','inputs/ship.glb',recipe,False);self.assertIn('Excluded authoring/provider',run.stdout)
        recipe['provenance']={'provider':'owned','source':'adobe-clay-building','notes':'No Adobe integrations. Material substance is clay.'}
        result=self.stage('ship','inspect','inputs/ship.glb',recipe)
        self.assertGreater(result['metrics']['triangles'],0)
        recipe['provenance']['source']='Adobe';run=self.stage('ship','inspect','inputs/ship.glb',recipe,False);self.assertIn('Excluded authoring/provider',run.stdout)

    def test_17_extract_motion_has_runtime_displacement_and_checks_other_loop_tracks(self):
        recipe=copy.deepcopy(self.recipes['ship']);item=recipe['clips'][0]
        item['rootMotion']='extract';item['channels']=[{'target':{'node':'MotionRoot'},'property':'location','keyframes':[[0,[0,0,0]],[3,[0,-.5,0]],[6,[0,-1,0]]]}]
        authored=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe)
        displacement=next(clip for clip in authored['clips'] if clip['id']=='cruise')['rootDisplacement']
        self.assertEqual(displacement,[0,0,1])
        baked=self.stage('ship','bake',authored['artifacts']['blend'],recipe)
        exported=self.stage('ship','export',baked['artifacts']['blend'],recipe)
        package=json.loads((self.project/exported['artifacts']['package']).read_text());self.assertEqual(package['rig']['rootNode'],'MotionRoot')
        item['channels'].append({'target':{'node':'Hull'},'property':'location','keyframes':[[0,[0,0,.6]],[3,[0,0,.7]],[6,[0,0,.8]]]})
        run=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe,False);self.assertIn('Loop seam',run.stdout)

    def test_18_clip_name_cannot_collide_with_transition_frame_namespace(self):
        recipe=copy.deepcopy(self.recipes['ship']);recipe['clips'][0]['id']='transition-0';recipe['requiredClips'][0]='transition-0';recipe['states'][0]['clip']='transition-0'
        authored=self.stage('ship','author',self.stages['ship']['rig']['artifacts']['blend'],recipe)
        baked=self.stage('ship','bake',authored['artifacts']['blend'],recipe);exported=self.stage('ship','export',baked['artifacts']['blend'],recipe)
        reviewed=self.stage('ship','review',exported['artifacts']['glb'],recipe);data=json.loads((self.project/reviewed['artifacts']['reviewReport']).read_text())
        frames=[image for packet in data['packets'] for image in packet['frames']]
        self.assertEqual(len(frames),len({frame['path'] for frame in frames}));self.assertEqual(data['frameCount'],data['requestedFrameCount'])
        self.assertEqual(len(data['packets']),len({packet['key'] for packet in data['packets']}))
        for image in frames:self.assertEqual(hashlib.sha256((self.project/image['path']).read_bytes()).hexdigest(),image['sha256'])

    def test_19_existing_frame_is_never_overwritten(self):
        output=self.project/'.art-staging/model-to-animation/ship/v1/attempts/existing-frame'
        frame=output/'f/c000/v0/0000.png';frame.parent.mkdir(parents=True);frame.write_bytes(b'original-protected-bytes')
        script=self.work/'existing-frame-check.py';verdict=self.work/'existing-frame-verdict.json'
        script.write_text('''import bpy,json,sys
from pathlib import Path
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
from core import load_scene
from review import review
root=Path('''+repr(str(self.project))+''');source=root/'''+repr(self.stages['ship']['export']['artifacts']['glb'])+'''
recipe=json.loads((root/'inputs/ship-recipe.json').read_text());load_scene(source,recipe['fps'])
try:
 review({'asset':'ship'},root,source,Path('''+repr(str(output))+'''),recipe)
except ValueError as error:
 Path('''+repr(str(verdict))+''').write_text(json.dumps({'blocked':True,'reason':str(error)}))
else:
 raise RuntimeError('Existing immutable image was accepted')
''',encoding='utf8')
        self.run_blender(script,[],'existing-frame-protected')
        self.assertEqual(frame.read_bytes(),b'original-protected-bytes');self.assertIn('already exists',json.loads(verdict.read_text())['reason'])


if __name__=='__main__':unittest.main(verbosity=2)
