"""Complete compound GLB review with explicitly labeled technical cue proxies."""
import html
import json
import math

from core import digest, finite, inventory, meshes, objects, read_glb, relative, save_json, vector
from composition import activate_composite, node, restore_composites


def review_times(action, fps):
    duration = action['duration']
    times = [min(index/fps,duration) for index in range(math.ceil(duration*fps)+1)] + [0,duration]
    times += [step[key] for step in action['steps'] for key in ('start','end')]
    times += [cue[key] for cue in action['cues'] for key in ('start','end')]
    times += [marker['at'] for marker in action.get('markers',[])]
    return sorted({round(finite(value,'Review sample',0,duration),9) for value in times})


def runtime_to_blender(value):
    x,y,z=vector(value,3,'Fixed preview target')
    return [x,-z,y]


def review(job, root, source, output, plan):
    import bpy
    from mathutils import Vector
    document,_=read_glb(source,plan['budgets']['maxRuntimeBytes'])
    restore_composites(plan)
    measured=inventory(job['profile'])
    settings=job['review']; cameras=settings['cameras']
    schedules=[(action,review_times(action,settings['fps'])) for action in plan['actions']]
    requested=sum(len(times)*len(cameras) for _,times in schedules)
    if requested>plan['budgets']['maxReviewFrames']:
        raise ValueError('Complete action/step/cue/marker review exceeds maxReviewFrames; no frames skipped')
    if requested*settings['resolution'][0]*settings['resolution'][1]>1073741824:
        raise ValueError('Complete technical review pixel budget exceeded')
    scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.render.resolution_x,scene.render.resolution_y=settings['resolution']
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=True
    scene.view_settings.view_transform='Standard'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL'
    scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
    scene.display.shading.background_type='WORLD'
    scene.world=bpy.data.worlds.new('ActionTechnicalReviewWorld');scene.world.color=(.12,.12,.12)
    anchors={anchor['id']:anchor for anchor in plan['anchors']}
    targets={target['id']:target for target in plan['targets']}
    releases={}
    points=[]
    for action,times in schedules:
        activate_composite(action['id'])
        for cue in action['cues']:
            if cue['anchor'] not in anchors:
                raise ValueError('Cue lacks real source anchor')
            frame=cue['start']*plan['fps'];scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
            position=node(anchors[cue['anchor']]['node']).matrix_world.translation.copy()
            if cue['type']=='projectile':
                if cue.get('target') not in targets or cue['target'] not in settings['targets']:
                    raise ValueError('Projectile technical review needs its explicit fixed target')
                target=Vector(runtime_to_blender(settings['targets'][cue['target']]))
                if (target-position).length>targets[cue['target']]['maxDistance']:
                    raise ValueError('Fixed technical target exceeds declared maximum distance')
                releases[(action['id'],cue['id'])]=(position,target)
                points.extend([position,target])
        for time in times:
            frame=time*plan['fps'];scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
            graph=bpy.context.evaluated_depsgraph_get()
            for obj in meshes():
                evaluated=obj.evaluated_get(graph)
                points.extend(evaluated.matrix_world@Vector(corner) for corner in evaluated.bound_box)
    if not points:raise ValueError('Technical action review has no measured bounds')
    minimum=Vector([min(point[axis] for point in points) for axis in range(3)])
    maximum=Vector([max(point[axis] for point in points) for axis in range(3)])
    center=(minimum+maximum)/2;radius=max((maximum-minimum).length/2,.05)
    camera_data=bpy.data.cameras.new('ActionTechnicalCamera');camera=bpy.data.objects.new('ActionTechnicalCamera',camera_data)
    scene.collection.objects.link(camera);scene.camera=camera;camera_data.type='ORTHO'
    camera_data.ortho_scale=radius*2.5*max(1,settings['resolution'][1]/settings['resolution'][0])
    camera_data.clip_start=.001;camera_data.clip_end=max(100,radius*100)
    directions={'front':(0,-1,0),'right':(-1,0,0),'back':(0,1,0),'left':(1,0,0),'top':(0,0,1),'bottom':(0,0,-1),'three-quarter':(1,-2,1)}
    proxy_data={};proxy_objects=[]
    for action in plan['actions']:
        for cue in action['cues']:
            count=min(cue.get('capacity',1),8) if cue['type']=='particles' else 1
            values=[]
            for index in range(count):
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=1)
                obj=bpy.context.object;obj.name='cue-proxy.'+action['id']+'.'+cue['id']+'.'+str(index)
                obj['opencaw_cue_proxy']=True;obj.hide_render=True
                mat=bpy.data.materials.new(obj.name);color=cue['color'].lstrip('#');rgb=tuple(int(color[i:i+2],16)/255 for i in (0,2,4));mat.diffuse_color=(*rgb,1)
                obj.data.materials.append(mat);values.append(obj);proxy_objects.append(obj)
            proxy_data[(action['id'],cue['id'])]=values
    artifacts={};packets=[]
    for action_index,(action,times) in enumerate(schedules):
        activate_composite(action['id'])
        packet={'id':action['id'],'duration':action['duration'],'frames':[],
                'method':'Actual independently re-imported baked GLB poses with technical cue proxies; actual engine effects are separate evidence'}
        for sample,time in enumerate(times):
            frame=time*plan['fps'];scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
            for obj in proxy_objects:obj.hide_render=True
            active=[];positions=[]
            for cue in action['cues']:
                if not cue['start']<=time<cue['end']:continue
                active.append(cue['id']);fraction=(time-cue['start'])/(cue['end']-cue['start'])
                anchor=node(anchors[cue['anchor']]['node']).matrix_world.translation.copy()
                for index,obj in enumerate(proxy_data[(action['id'],cue['id'])]):
                    obj.hide_render=False
                    if cue['type']=='projectile':
                        begin,end=releases[(action['id'],cue['id'])];obj.location=begin.lerp(end,fraction);scale=cue['radius']
                    elif cue['type']=='orb':
                        obj.location=anchor;scale=cue['radius']*(.2+.8*fraction)
                    else:
                        phase=index+time*3+(cue.get('seed',0)%17);obj.location=anchor+Vector((math.cos(phase),math.sin(phase),math.sin(phase*.7)))*cue['radius']*2;scale=cue['radius']*.15
                    obj.scale=(scale,)*3
                    positions.append({'cue':cue['id'],'positionBlender':list(obj.location),'proxy':True})
            for view in cameras:
                direction=Vector(directions[view]).normalized();camera.location=center+direction*radius*4
                camera.rotation_euler=(-direction).to_track_quat('-Z','Y' if view not in ('top','bottom') else 'X').to_euler()
                path=output/'f'/('a'+str(action_index).zfill(3))/('v'+str(cameras.index(view)))/(str(sample).zfill(4)+'.png')
                if path.exists() or path.is_symlink():raise ValueError('Technical action frame already exists')
                path.parent.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
                name=relative(root,path);artifacts['frame-'+str(len(artifacts))]=name
                packet['frames'].append({'path':name,'sha256':digest(path),'time':time,'camera':view,'view':view,'activeCues':active,'cueProxies':positions})
        packets.append(packet)
    flattened=[frame for packet in packets for frame in packet['frames']]
    if len(flattened)!=requested or len({frame['path'] for frame in flattened})!=requested:
        raise ValueError('Technical review frame coverage or uniqueness is incomplete')
    data={'schemaVersion':'opencaw-action-review/v1','asset':job['asset'],'profile':job['profile'],'inputSha256':digest(source),
          'frameCount':requested,'requestedFrameCount':requested,'packets':packets,'cameras':cameras,'previewFps':settings['fps'],
          'resolution':settings['resolution'],'renderer':'BLENDER_WORKBENCH','metrics':measured,
          'independentReimport':{'actualGlb':True,'animationCount':len(document.get('animations',[])),'skinCount':len(document.get('skins',[]))},
          'cueRendering':'technical-proxies-only','humanApproval':'pending','independentReview':'pending','runtimeVerification':'not-run',
          'limits':['All declared durations and grid/step/cue/marker boundaries are sampled; finite sampling is not continuous visual acceptance.',
                    'Proxy spheres represent attachment/phase/trajectory only; native engine particles/materials and gameplay need independent target evidence.']}
    report_path=output/'action-review.json';save_json(report_path,data);artifacts['reviewReport']=relative(root,report_path)
    payload=[]
    for packet in packets:
        for view in cameras:
            frames=[image for image in packet['frames'] if image['camera']==view]
            payload.append({'name':packet['id']+' / '+view,'duration':packet['duration'],'frames':[{'path':__import__('os').path.relpath(root/image['path'],output).replace('\\','/'),'time':image['time'],'cues':image['activeCues']} for image in frames]})
    encoded=json.dumps(payload).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')
    page=output/'review.html'
    page.write_text('''<!doctype html><meta charset="utf-8"><title>Action sequence technical review</title><style>body{background:#222;color:#eee;font-family:sans-serif}section{display:inline-block;vertical-align:top;margin:12px}img{display:block;background:#444;max-width:480px}input{width:100%}</style><h1>Complete action sequence review</h1><p>Actual baked GLB motion with technical cue proxies. Engine effects and human runtime acceptance remain pending. Playback follows recorded seconds; pause and scrub exact sample boundaries.</p><a href="action-review.json">Frame hashes, exact times, cue labels and limitations</a><main></main><script>const packets='''+encoded+''';for(const p of packets){const s=document.createElement('section'),h=document.createElement('h2'),img=document.createElement('img'),range=document.createElement('input'),label=document.createElement('p'),button=document.createElement('button');h.textContent=p.name;range.type='range';range.min=0;range.max=p.frames.length-1;let cursor=0,playing=false,last=null,shown=-1;const show=i=>{if(i===shown)return;shown=i;const f=p.frames[i];img.src=f.path;label.textContent=f.time.toFixed(3)+' / '+p.duration.toFixed(3)+' sec; proxy cues: '+f.cues.join(', ');range.value=i};button.textContent='Play';button.onclick=()=>{playing=!playing;button.textContent=playing?'Pause':'Play';last=null};range.oninput=()=>{cursor=p.frames[+range.value].time;show(+range.value);last=null};s.append(h,img,button,range,label);document.querySelector('main').append(s);show(0);function tick(now){if(playing&&last!==null){cursor=(cursor+Math.min((now-last)/1000,.25))%p.duration;let i=0;while(i+1<p.frames.length&&p.frames[i+1].time<=cursor)i++;show(i)}last=now;requestAnimationFrame(tick)}requestAnimationFrame(tick)};</script>''',encoding='utf-8')
    artifacts['review']=relative(root,page)
    return artifacts,data,measured
