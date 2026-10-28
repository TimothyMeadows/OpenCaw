"""Actual Blender composition/export/re-import and full technical action proofs."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from array import array
import tracemalloc

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
TASK=Path(os.environ.get('OPENCAW_ACTION_TEST_EVIDENCE_ROOT', ROOT/'.opencaw/.cache/tasks/model-to-action')).resolve()
TASK.relative_to(ROOT)
SCRIPTS=ROOT/'.styles/.workflows/model-to-action/blender'
BLENDER=os.environ.get('BLENDER_EXE') or shutil.which('blender') or 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'
spec=importlib.util.spec_from_file_location('action_fixture',ROOT/'tests/fixtures/model-action/create_assets.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def native_peak_working_set(process):
    """Observed Windows process peak, not a Python-heap or GPU-memory claim."""
    if os.name!='nt':return None
    import ctypes
    from ctypes import wintypes
    class Counters(ctypes.Structure):
        _fields_=[('cb',wintypes.DWORD),('PageFaultCount',wintypes.DWORD),
                  *[(name,ctypes.c_size_t) for name in ('PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage',
                     'QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage')]]
    counters=Counters();counters.cb=ctypes.sizeof(counters)
    query=ctypes.WinDLL('psapi',use_last_error=True).GetProcessMemoryInfo
    query.argtypes=[wintypes.HANDLE,ctypes.POINTER(Counters),wintypes.DWORD];query.restype=wintypes.BOOL
    return int(counters.PeakWorkingSetSize) if query(int(process._handle),ctypes.byref(counters),counters.cb) else None


class VerificationStorage(unittest.TestCase):
    """Actual filesystem/integrity checks with explicitly synthetic pose data."""
    @classmethod
    def setUpClass(cls):
        TASK.mkdir(parents=True,exist_ok=True)
        cls.work=Path(tempfile.mkdtemp(prefix='storage-',dir=TASK))
        sys.path.insert(0,str(SCRIPTS))
        import verification
        cls.storage=verification

    def data(self,vertices=3,frames=3):
        plan={'fps':1,'actions':[{'id':'synthetic','duration':frames-1}],'anchors':[{'id':'anchor'}],'budgets':{}}
        def samples():
            for frame in range(frames):
                yield 'synthetic',frame,{'meshes':{'mesh':array('d',(float(index)/vertices for index in range(vertices*3)))},
                                          'anchors':{'anchor':array('d',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])}}
        return plan,samples

    def spool(self,name,vertices=3,frames=3):
        plan,samples=self.data(vertices,frames);directory=self.work/name
        metadata=self.storage.write_spool(self.work,directory,plan,'a'*64,samples())
        return plan,directory,metadata

    def consume(self,plan,directory):
        with self.storage.read_spool(self.work,directory,plan,'a'*64) as (_,samples):return list(samples)

    def test_01_exact_default_and_complete_frame_identity(self):
        plan,directory,metadata=self.spool('complete')
        self.assertEqual(self.storage.budget(plan),8*1024**3)
        self.assertEqual(metadata['totalBytes'],sum(path.stat().st_size for path in directory.iterdir()))
        frames=self.consume(plan,directory)
        self.assertEqual([(action,frame) for action,frame,_ in frames],[('synthetic',0),('synthetic',1),('synthetic',2)])
        self.assertEqual(frames[0][2]['meshes']['mesh'],frames[-1][2]['meshes']['mesh'])

    def test_02_byte_preflight_rejects_before_spool_creation(self):
        plan,samples=self.data(100,3);plan['budgets']['maxVerificationBytes']=1024
        directory=self.work/'over-budget'
        with self.assertRaisesRegex(ValueError,'exceeds maxVerificationBytes'):self.storage.write_spool(self.work,directory,plan,'a'*64,samples())
        self.assertFalse(directory.exists())

    def test_03_payload_corruption_cannot_pass(self):
        plan,directory,_=self.spool('corrupt')
        path=directory/'poses.bin';raw=bytearray(path.read_bytes());raw[len(self.storage.MAGIC)+4]^=1;path.write_bytes(raw)
        with self.assertRaisesRegex(ValueError,'checksum mismatch'):self.consume(plan,directory)

    def test_04_truncation_and_extension_cannot_pass(self):
        for name,edit in [('truncated',lambda raw:raw[:-8]),('extended',lambda raw:raw+b'extra')]:
            plan,directory,_=self.spool(name);path=directory/'poses.bin';path.write_bytes(edit(path.read_bytes()))
            with self.assertRaises(ValueError):self.consume(plan,directory)

    def test_05_reordered_rehashed_index_cannot_skip_frames(self):
        plan,directory,_=self.spool('reordered');path=directory/'frames.jsonl';lines=path.read_bytes().splitlines(keepends=True)
        path.write_bytes(lines[1]+lines[0]+lines[2]);index=directory/'index.json';metadata=json.loads(index.read_text())
        metadata['framesSha256']=sha(path);index.write_bytes(self.storage.compact(metadata))
        with self.assertRaisesRegex(ValueError,'sequence or offsets'):self.consume(plan,directory)

    def test_06_interrupted_writer_closes_and_retains_partial_evidence(self):
        plan,samples=self.data();directory=self.work/'interrupted'
        def interrupted():
            yield next(samples())
            raise InterruptedError('Explicit synthetic source interruption')
        with self.assertRaises(InterruptedError):self.storage.write_spool(self.work,directory,plan,'a'*64,interrupted())
        self.assertTrue((directory/'poses.bin').exists());self.assertFalse((directory/'index.json').exists())
        with (directory/'poses.bin').open('r+b') as stream:self.assertTrue(stream.read(1))
        with self.assertRaisesRegex(ValueError,'Incomplete'):self.consume(plan,directory)
        with self.assertRaisesRegex(ValueError,'already exists'):self.storage.write_spool(self.work,directory,plan,'a'*64,samples())

    def test_07_path_escape_and_changed_plan_fail(self):
        plan,samples=self.data()
        with self.assertRaises(ValueError):self.storage.write_spool(self.work,self.work/'../escape',plan,'a'*64,samples())
        plan,directory,_=self.spool('changed-plan')
        with self.assertRaisesRegex(ValueError,'current plan'):
            with self.storage.read_spool(self.work,directory,plan,'b'*64):pass

    def test_08_incomplete_comparison_cannot_claim_complete_coverage(self):
        plan,directory,_=self.spool('incomplete-reader')
        with self.assertRaisesRegex(ValueError,'every verification frame'):
            with self.storage.read_spool(self.work,directory,plan,'a'*64) as (_,samples):next(samples)

    def test_09_topology_changes_and_nonfinite_payloads_fail(self):
        for name,edit in [('changed-topology',lambda value:value['meshes'].__setitem__('mesh',array('d',[0,0,0]))),
                          ('nonfinite',lambda value:value['meshes']['mesh'].__setitem__(0,float('nan')))]:
            plan,samples=self.data()
            def changed():
                for identifier,frame,sample in samples():
                    if frame==1:edit(sample)
                    yield identifier,frame,sample
            with self.assertRaises(ValueError):self.storage.write_spool(self.work,self.work/name,plan,'a'*64,changed())
            self.assertFalse((self.work/name/'index.json').exists())

    def test_10_streamed_python_memory_does_not_grow_with_total_geometry(self):
        plan,samples=self.data(50000,48);directory=self.work/'memory'
        tracemalloc.start()
        metadata=self.storage.write_spool(self.work,directory,plan,'a'*64,samples())
        _,write_peak=tracemalloc.get_traced_memory();tracemalloc.reset_peak()
        count=0
        with self.storage.read_spool(self.work,directory,plan,'a'*64) as (_,frames):
            for identifier,frame,sample in frames:
                self.assertEqual(len(sample['meshes']['mesh']),150000);count+=1
        _,read_peak=tracemalloc.get_traced_memory();tracemalloc.stop()
        self.assertEqual(count,48)
        self.assertLess(max(write_peak,read_peak),metadata['framePayloadBytes']*8+8*1024**2)
        self.assertGreater(metadata['totalBytes'],40*1024**2)
        (self.work/'memory-measurement.json').write_text(json.dumps({'kind':'actual-filesystem-with-synthetic-pose-payloads','frames':count,
            'verticesPerFrame':50000,'spoolBytes':metadata['totalBytes'],'framePayloadBytes':metadata['framePayloadBytes'],
            'peakTracedPythonWriteBytes':write_peak,'peakTracedPythonReadBytes':read_peak,'rendererAcceptance':False},indent=2)+'\n',encoding='utf-8')


class ActionProduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(BLENDER).is_file():raise unittest.SkipTest('BLOCKED: existing Blender4.5 unavailable; no install attempted')
        TASK.mkdir(parents=True,exist_ok=True)
        cls.work=Path(tempfile.mkdtemp(prefix='b-',dir=TASK));cls.project=cls.work/'p';cls.calls=[]
        cls.run_blender(ROOT/'tests/fixtures/model-action/create_assets.py',['--output',str(cls.project)],'original-source')
        cls.motion=json.loads((cls.project/'source/motion-package.json').read_text());cls.recipe=json.loads((cls.project/'action-recipe.json').read_text())
        cls.plan=json.loads((cls.project/'compiled-plan.json').read_text());cls.source_hash=sha(cls.project/'source/asset.glb')
        cls.results={};current='source/asset.glb'
        for operation in ('inspect','compose','export','review'):
            report=cls.stage(operation,current);cls.results[operation]=report
            if operation=='compose':current=report['artifacts']['blend']
            elif operation=='export':current=report['artifacts']['glb']
        (cls.work/'fixture-outputs.json').write_text(json.dumps(cls.results,indent=2),encoding='utf-8')
        (TASK/'blender-action-latest.txt').write_text(str(cls.work)+'\n',encoding='utf-8')
        cls.inspect_poses()

    @classmethod
    def tearDownClass(cls):
        (cls.work/'commands.json').write_text(json.dumps(cls.calls,indent=2),encoding='utf-8')

    @classmethod
    def run_blender(cls,script,extra,name,success=True):
        args=[BLENDER,'--factory-startup','--background','--disable-autoexec','--python-exit-code','1','--python',str(script),'--',*extra]
        process=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        try:stdout,_=process.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            process.kill();stdout,_=process.communicate()
            (cls.work/(name+'.timeout.log')).write_bytes(stdout)
            raise
        peak=native_peak_working_set(process)
        run=subprocess.CompletedProcess(args,process.returncode,stdout)
        log=cls.work/(name+'.log');log.write_bytes(run.stdout)
        cls.calls.append({'args':args,'exitCode':run.returncode,'log':str(log.relative_to(ROOT)),'peakWorkingSetBytes':peak})
        (cls.work/'commands.json').write_text(json.dumps(cls.calls,indent=2),encoding='utf-8')
        if (run.returncode==0)!=success:raise AssertionError(log.read_text(errors='replace')[-6500:])
        return run

    @classmethod
    def stage(cls,operation,source,plan=None,motion=None,success=True,job_change=None):
        identifier=operation+'-'+str(len(cls.calls));folder='.art-staging/model-to-action/sequence-fixture/v1/attempts/'+identifier
        job={'schemaVersion':1,'root':str(cls.project),'operation':operation,'input':source,'outputDir':folder,'result':folder+'/result.json',
             'asset':'sequence-fixture','version':'v1','profile':(motion or cls.motion)['profile'],'motionPackage':motion or cls.motion,'plan':plan or cls.plan,'review':cls.recipe['review']}
        if job_change:job.update(job_change)
        path=cls.project/('job-'+identifier+'.json');path.write_text(json.dumps(job),encoding='utf-8')
        run=cls.run_blender(SCRIPTS/'action.py',['--job',str(path)],identifier,success)
        result=cls.project/job['result']
        if not success:
            if result.exists():raise AssertionError('Failed Blender operation emitted passing-looking result')
            return run
        report=json.loads(result.read_text());assert report['schemaVersion']=='opencaw-action-stage/v1' and report['operation']==operation
        for relative in report['artifacts'].values():assert (cls.project/relative).is_file(),relative
        return report

    @classmethod
    def inspect_poses(cls):
        script=cls.work/'inspect-poses.py';output=cls.work/'poses.json'
        script.write_text('''import bpy,json,math,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
from composition import activate_composite
bpy.ops.wm.open_mainfile(filepath='''+repr(str(cls.project/cls.results['compose']['artifacts']['blend']))+''',load_ui=False,use_scripts=False)
rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE')
poses={}
for identifier,times in {'dance-pattern':[.5,1.5,2.25],'chained-combo':[.5,.9375,1.375,2.25],'charge-cast':[.5,1.375,2.5]}.items():
 activate_composite(identifier)
 poses[identifier]=[]
 for time in times:
  frame=time*24;bpy.context.scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
  poses[identifier].append({'time':time,'hips':rig.pose.bones['hips'].matrix_basis.to_quaternion().angle,'left':rig.pose.bones['upperarm.L'].matrix_basis.to_quaternion().angle,'right':rig.pose.bones['upperarm.R'].matrix_basis.to_quaternion().angle,'thigh':rig.pose.bones['thigh.R'].matrix_basis.to_quaternion().angle,'hand':list(bpy.data.objects['anchor.hand.cast'].matrix_world.translation)})
tracks=[{'name':track.name,'muted':track.mute,'strips':[{'start':strip.frame_start,'end':strip.frame_end,'scale':strip.scale,'sourceStart':strip.action_frame_start,'sourceEnd':strip.action_frame_end} for strip in track.strips]} for obj in bpy.context.scene.objects if obj.animation_data for track in obj.animation_data.nla_tracks]
Path('''+repr(str(output))+''').write_text(json.dumps({'poses':poses,'tracks':tracks,'socketBone':bpy.data.objects['HandCastSocket'].parent_bone}))
''',encoding='utf-8')
        cls.run_blender(script,[],'pose-inspection');cls.poses=json.loads(output.read_text())

    def test_01_real_compound_export_and_independent_reimport(self):
        report=self.results['export'];package=json.loads((self.project/report['artifacts']['package']).read_text())
        self.assertEqual({action['id'] for action in package['actions']},{'dance-pattern','chained-combo','charge-cast'})
        self.assertEqual(package['rig'],self.motion['rig']);self.assertEqual(package['anchors'],self.motion['anchors'])
        self.assertEqual(package['verification']['status'],'pending')
        reimport=report['metrics']['independentReimport'];self.assertTrue(reimport['actualGlb']);self.assertGreater(reimport['skinCount'],0)
        self.assertLessEqual(reimport['maximumWorldVertexError'],.001);self.assertGreater(reimport['allBakedFramesCompared'],100)
        for action in package['actions']:
            self.assertEqual(action['clip'],action['id']);self.assertRegex(action['motionSha256'],'^[a-f0-9]{64}$')
        self.assertEqual(sha(self.project/package['model']['path']),package['model']['sha256'])

    def test_02_dance_repeats_and_order_have_actual_distinct_poses(self):
        poses=self.poses['poses']['dance-pattern']
        for pose in poses:self.assertAlmostEqual(pose['hips'],.25,delta=.01)
        self.assertAlmostEqual(poses[0]['left'],.4,delta=.02);self.assertAlmostEqual(poses[1]['left'],.4,delta=.02)
        self.assertAlmostEqual(poses[2]['right'],.4,delta=.02)

    def test_03_combo_overlap_blends_both_actual_arms(self):
        poses=self.poses['poses']['chained-combo'];self.assertGreater(poses[0]['left'],.7)
        self.assertGreater(poses[1]['left'],.02);self.assertLess(poses[1]['left'],.1)
        self.assertGreater(poses[1]['right'],.02);self.assertLess(poses[1]['right'],.1)
        self.assertGreater(poses[3]['thigh'],.9)

    def test_04_hand_anchor_has_real_bone_ownership_and_moves(self):
        self.assertEqual(self.poses['socketBone'],'forearm.L')
        points=[pose['hand'] for pose in self.poses['poses']['charge-cast']]
        self.assertGreater(sum((points[0][i]-points[1][i])**2 for i in range(3)),.005)

    def test_05_editable_source_strips_retain_time_scale_and_overlap(self):
        tracks=self.poses['tracks'];self.assertTrue(tracks);self.assertTrue(all(track['muted'] for track in tracks))
        self.assertTrue(all(track['name'].startswith('EDIT.') for track in tracks))
        self.assertTrue(any(abs(strip['start']-21)<1e-5 for track in tracks for strip in track['strips']))

    def test_06_review_covers_every_grid_boundary_marker_camera_and_hash(self):
        data=json.loads((self.project/self.results['review']['artifacts']['reviewReport']).read_text())
        self.assertEqual(data['frameCount'],data['requestedFrameCount']);self.assertEqual(data['humanApproval'],'pending')
        self.assertEqual(data['cueRendering'],'technical-proxies-only');paths=[]
        for action in self.plan['actions']:
            packet=next(packet for packet in data['packets'] if packet['id']==action['id'])
            required={0,action['duration']}|{step[key] for step in action['steps'] for key in ('start','end')}|{cue[key] for cue in action['cues'] for key in ('start','end')}|{marker['at'] for marker in action['markers']}
            for camera in self.recipe['review']['cameras']:
                frames=[frame for frame in packet['frames'] if frame['camera']==camera]
                for time in required:self.assertTrue(any(abs(frame['time']-time)<1e-6 for frame in frames))
                for frame in frames:self.assertEqual(sha(self.project/frame['path']),frame['sha256']);paths.append(frame['path'])
        self.assertEqual(len(paths),len(set(paths)))

    def test_07_actual_trim_rate_and_repeat(self):
        recipe=copy.deepcopy(self.recipe);recipe['actions']=[{'id':'trim-repeat','role':'dance','steps':[{'id':'pulse','clip':'dance-left','from':.25,'to':.75,'rate':2,'repeat':2,'blendIn':0}],'cues':[]}]
        plan=fixture.compile_fixture(recipe,self.motion);report=self.stage('compose','source/asset.glb',plan)
        script=self.work/'inspect-trim.py';result=self.work/'trim.json'
        script.write_text('''import bpy,json,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
from composition import activate_composite
bpy.ops.wm.open_mainfile(filepath='''+repr(str(self.project/report['artifacts']['blend']))+''',load_ui=False,use_scripts=False)
activate_composite('trim-repeat');rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE');values=[]
for frame in (0,3,6,9):
 bpy.context.scene.frame_set(frame);bpy.context.view_layer.update();values.append(rig.pose.bones['hips'].matrix_basis.to_quaternion().angle)
Path('''+repr(str(result))+''').write_text(json.dumps(values))
''',encoding='utf-8');self.run_blender(script,[],'trim-inspection')
        values=json.loads(result.read_text())
        for actual,wanted in zip(values,[.125,.25,.125,.25]):self.assertAlmostEqual(actual,wanted,delta=.01)

    def test_08_missing_clip_fails_without_result(self):
        plan=copy.deepcopy(self.plan);plan['actions'][0]['steps'][0]['clip']='not-present'
        self.stage('inspect','source/asset.glb',plan,success=False)

    def test_09_extracted_source_is_not_silently_reinterpreted(self):
        motion=copy.deepcopy(self.motion);motion['clips'][0]['rootMotion']='extract'
        self.stage('inspect','source/asset.glb',motion=motion,success=False)

    def test_10_missing_root_or_anchor_fails(self):
        motion=copy.deepcopy(self.motion);motion['rig']['rootBone']='MissingRoot'
        plan=copy.deepcopy(self.plan);plan['rig']=motion['rig'];self.stage('inspect','source/asset.glb',plan,motion,False)
        plan=copy.deepcopy(self.plan);plan['anchors'][0]['node']='MissingAnchor';self.stage('inspect','source/asset.glb',plan,success=False)

    def test_11_invalid_rate_overlap_and_stale_source_hash_fail(self):
        for key,value in [('rate',0),('start',.1),('motionSha256','0'*64)]:
            plan=copy.deepcopy(self.plan);plan['actions'][0]['steps'][0][key]=value;self.stage('compose','source/asset.glb',plan,success=False)

    def test_12_missing_target_or_invalid_cue_does_not_skip(self):
        for key,value in [('target','not-declared'),('type','placeholder'),('radius',-1)]:
            plan=copy.deepcopy(self.plan);plan['actions'][2]['cues'][1][key]=value;self.stage('review',self.results['export']['artifacts']['glb'],plan,success=False)

    def test_13_review_budget_cannot_drop_required_frames(self):
        plan=copy.deepcopy(self.plan);plan['budgets']['maxReviewFrames']=1
        self.stage('review',self.results['export']['artifacts']['glb'],plan,success=False)

    def test_14_immutable_attempt_and_source_remain_intact(self):
        folder=self.project/self.results['review']['artifacts']['reviewReport'];old=sha(folder)
        self.stage('inspect','source/asset.glb',success=False,job_change={'outputDir':'../escape','result':'../escape/result.json'})
        self.assertEqual(sha(folder),old);self.assertEqual(sha(self.project/'source/asset.glb'),self.source_hash)

    def test_15_review_html_player_javascript_is_valid(self):
        node=shutil.which('node') or shutil.which('node.exe')
        if not node:self.skipTest('Existing Node unavailable; not installed')
        page=(self.project/self.results['review']['artifacts']['review']).read_text()
        script=self.work/'review-player.js';script.write_text(page.split('<script>',1)[1].split('</script>',1)[0],encoding='utf-8')
        run=subprocess.run([node,'--check',str(script)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10)
        self.assertEqual(run.returncode,0,run.stdout.decode(errors='replace'))

    def test_16_actual_root_motion_cannot_hide_behind_in_place_metadata(self):
        raw=bytearray((self.project/'source/asset.glb').read_bytes());length=struct.unpack_from('<I',raw,12)[0]
        document=json.loads(raw[20:20+length]);binary_start=20+length+8
        root_index=next(index for index,node in enumerate(document['nodes']) if node.get('name')==self.motion['rig']['rootBone'])
        animation=next(value for value in document['animations'] if value['name']=='dance-left')
        channel=next(value for value in animation['channels'] if value['target']=={'node':root_index,'path':'translation'})
        accessor=document['accessors'][animation['samplers'][channel['sampler']]['output']]
        self.assertEqual((accessor['type'],accessor['componentType']),('VEC3',5126))
        view=document['bufferViews'][accessor['bufferView']];stride=view.get('byteStride',12)
        offset=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0)+(accessor['count']-1)*stride
        struct.pack_into('<f',raw,offset,struct.unpack_from('<f',raw,offset)[0]+.2)
        path=self.project/'source/root-motion-lie.glb';path.write_bytes(raw)
        run=self.stage('inspect','source/root-motion-lie.glb',success=False)
        self.assertIn('Actual source clip moves its root',run.stdout.decode(errors='replace'))

    def test_17_action_id_can_match_its_source_clip_without_collision(self):
        recipe=copy.deepcopy(self.recipe);recipe['actions']=[{'id':'kick','role':'combo','steps':[{'id':'kick','clip':'kick','from':0,'to':1,'rate':1,'repeat':1,'blendIn':0}],'cues':[]}]
        plan=fixture.compile_fixture(recipe,self.motion);composed=self.stage('compose','source/asset.glb',plan)
        exported=self.stage('export',composed['artifacts']['blend'],plan)
        self.assertEqual(exported['metrics']['independentReimport']['animationNames'],['kick'])

    def test_18_review_refuses_existing_frame_without_overwrite(self):
        identifier='review-'+str(len(self.calls));folder='.art-staging/model-to-action/sequence-fixture/v1/attempts/'+identifier
        sentinel=self.project/folder/'f/a000/v0/0000.png';sentinel.parent.mkdir(parents=True);sentinel.write_bytes(b'original-evidence')
        self.stage('review',self.results['export']['artifacts']['glb'],success=False)
        self.assertEqual(sentinel.read_bytes(),b'original-evidence')

    def test_19_rigid_and_articulated_vehicles_need_no_fake_skeleton(self):
        fixtures=json.loads((self.project/'fixtures.json').read_text())['mechanical']
        for name,profile in [('car','articulated'),('ship','rigid')]:
            fixture_data=fixtures[name];motion=json.loads((self.project/fixture_data['motionPackage']).read_text());plan=json.loads((self.project/fixture_data['compiledPlan']).read_text())
            inspected=self.stage('inspect',fixture_data['sourceModel'],plan,motion);self.assertEqual(inspected['metrics']['bones'],0)
            composed=self.stage('compose',fixture_data['sourceModel'],plan,motion)
            exported=self.stage('export',composed['artifacts']['blend'],plan,motion)
            self.assertEqual(exported['metrics']['independentReimport']['skinCount'],0)
            self.assertEqual(json.loads((self.project/exported['artifacts']['package']).read_text())['profile'],profile)

    def test_20_particle_capacity_is_per_action_but_expanded_steps_are_aggregate(self):
        recipe=copy.deepcopy(self.recipe);recipe['actions']=[]
        for identifier in ('particles-a','particles-b'):
            recipe['actions'].append({'id':identifier,'role':'presentation','steps':[{'id':'idle','clip':'idle','from':0,'to':1,'rate':1,'repeat':2,'blendIn':0}],
                'cues':[{'id':'bounded','type':'particles','anchor':'hand.cast','start':{'step':'idle','occurrence':0,'offset':0},'end':{'step':'idle','occurrence':0,'offset':.5},'color':'#FFD060','radius':.1,'capacity':1000,'rate':24,'seed':7}]})
        recipe['budgets'].update(maxParticles=1500,maxEffects=1,maxStepsPerAction=1,maxExpandedSteps=4)
        plan=fixture.compile_fixture(recipe,self.motion);self.stage('compose','source/asset.glb',plan)
        excessive=copy.deepcopy(plan);excessive['budgets']['maxExpandedSteps']=3
        run=self.stage('inspect','source/asset.glb',excessive,success=False);self.assertIn('Total expanded steps exceed budget',run.stdout.decode(errors='replace'))
        excessive=copy.deepcopy(plan);excessive['actions'][0]['steps'][1]['id']='second-definition'
        run=self.stage('inspect','source/asset.glb',excessive,success=False);self.assertIn('Per-action source step count exceeds budget',run.stdout.decode(errors='replace'))
        excessive=copy.deepcopy(plan);excessive['budgets']['maxEffects']=2;second=copy.deepcopy(excessive['actions'][0]['cues'][0]);second['id']='additional';excessive['actions'][0]['cues'].append(second)
        run=self.stage('inspect','source/asset.glb',excessive,success=False);self.assertIn('Per-action aggregate particle capacity exceeds budget',run.stdout.decode(errors='replace'))

    def test_21_subframe_root_and_ancestor_excursions_are_actually_rejected(self):
        original=(self.project/'source/asset.glb').read_bytes();length=struct.unpack_from('<I',original,12)[0]
        for name,cubic in [('root',False),('MotionRig',False),('MotionRoot',False),('root',True),('upperarm.L',True)]:
            document=json.loads(original[20:20+length]);binary=bytearray(original[20+length+8:])
            index=next(index for index,node in enumerate(document['nodes']) if node.get('name')==name)
            animation=next(value for value in document['animations'] if value['name']=='dance-left')
            channel=next((value for value in animation['channels'] if value['target']=={'node':index,'path':'translation'}),None)
            base=document['nodes'][index].get('translation',[0,0,0]);times=[0,.005,.015,.025,1]
            def accessor(values,kind):
                while len(binary)%4:binary.append(0)
                start=len(binary);values=list(values);binary.extend(struct.pack('<'+'f'*len(values),*values));view=len(document['bufferViews'])
                document['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(values)*4});identifier=len(document['accessors'])
                item={'bufferView':view,'componentType':5126,'count':len(values)//(3 if kind=='VEC3' else 1),'type':kind}
                if kind=='SCALAR':item.update(min=[min(values)],max=[max(values)])
                document['accessors'].append(item);return identifier
            positions=[]
            for key in range(len(times)):
                value=list(base)
                if not cubic and key==2:value[0]+=.2
                if cubic:
                    incoming=[-80,0,0] if key==2 else [0,0,0];outgoing=[80,0,0] if key==1 else [0,0,0]
                    positions.extend(incoming+value+outgoing)
                else:positions.extend(value)
            sampler={'input':accessor(times,'SCALAR'),'output':accessor(positions,'VEC3'),'interpolation':'CUBICSPLINE' if cubic else 'LINEAR'}
            if channel is None:
                channel={'sampler':len(animation['samplers']),'target':{'node':index,'path':'translation'}};animation['samplers'].append(sampler);animation['channels'].append(channel)
            else:animation['samplers'][channel['sampler']]=sampler
            document['buffers'][0]['byteLength']=len(binary);encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
            raw=struct.pack('<III',0x46546C67,2,12+8+len(encoded)+8+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(binary),0x004E4942)+binary
            relative='source/subframe-'+name+('-cubic' if cubic else '')+'.glb';(self.project/relative).write_bytes(raw)
            run=self.stage('inspect',relative,success=False)
            self.assertIn('requires a reviewed LINEAR/STEP bake' if name=='upperarm.L' else 'Actual source clip moves its root',run.stdout.decode(errors='replace'))

    def test_22_actual_geometry_preflight_fails_before_composition_or_export(self):
        plan=copy.deepcopy(self.plan);plan['budgets']['maxVerificationBytes']=1024
        for operation in ('inspect','compose'):
            run=self.stage(operation,'source/asset.glb',plan,success=False)
            self.assertIn('exceeds maxVerificationBytes before export',run.stdout.decode(errors='replace'))
            job=json.loads(Path(run.args[-1]).read_text());directory=self.project/job['outputDir']
            self.assertFalse((directory/'verification').exists());self.assertFalse((directory/'asset.glb').exists())
            self.assertFalse((directory/'source.blend').exists())

    def test_23_actual_dense_geometry_export_is_verified_incrementally(self):
        script=self.work/'dense-owned-derivative.py'
        relative='.art-staging/model-to-action/sequence-fixture/v1/attempts/dense-owned-derivative/source.blend'
        blend=self.project/relative;blend.parent.mkdir(parents=True)
        script.write_text('''import bpy,sys
sys.dont_write_bytecode=True
bpy.ops.wm.open_mainfile(filepath='''+repr(str(self.project/self.results['compose']['artifacts']['blend']))+''',load_ui=False,use_scripts=False)
bpy.ops.mesh.primitive_grid_add(x_subdivisions=201,y_subdivisions=201,size=.25,location=(.6,0,.8))
mesh=bpy.context.object;mesh.name='OwnedDenseVerificationPanel';mesh.data['opencaw_action_mesh']='dense-owned-panel'
matrix=mesh.matrix_world.copy();rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE');mesh.parent=rig;mesh.matrix_world=matrix
group=mesh.vertex_groups.new(name='root');group.add(list(range(len(mesh.data.vertices))),1,'REPLACE')
modifier=mesh.modifiers.new('OwnedFixtureRig','ARMATURE');modifier.object=rig
mesh.data.materials.append(next(value for value in bpy.data.materials if value.name!='Dots Stroke'))
bpy.ops.wm.save_as_mainfile(filepath='''+repr(str(blend))+''',check_existing=False)
''',encoding='utf-8')
        self.run_blender(script,[],'dense-owned-derivative')
        exported=self.stage('export',relative)
        measured=exported['metrics']['independentReimport'];storage=measured['verificationStorage']
        self.assertEqual(measured['allBakedFramesCompared'],219)
        self.assertTrue(storage['framesComparedIncrementally']);self.assertGreater(storage['spoolBytes'],150*1024**2)
        self.assertLess(storage['framePayloadBytes'],2*1024**2)
        self.assertLessEqual(measured['maximumWorldVertexError'],.001)
        self.assertTrue(measured['materialBindingsVerified'] and measured['rootOwnershipVerified'])
        (self.work/'dense-verification-measurement.json').write_text(json.dumps({'kind':'actual-Blender-export-and-independent-reimport',
            'geometry':exported['metrics']['before'],'comparison':measured,'peakWorkingSetBytes':self.calls[-1]['peakWorkingSetBytes'],
            'scope':'Original controlled dense static attachment plus real rigged composite clips; no production owl or hardware GPU qualification'},indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':unittest.main(verbosity=2)
