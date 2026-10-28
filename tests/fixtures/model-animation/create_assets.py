"""Original controlled engineering geometry and declarative motion recipes.

Run only in Blender4.5. No source asset, model weight or provider is required.
These fixtures demonstrate production mechanics, not production art acceptance.
"""
import argparse
import json
import math
from pathlib import Path
import sys


def quaternion(axis, angle):
    result=[0,0,0,math.cos(angle/2)]
    result[axis]=math.sin(angle/2)
    return result


def channel(kind,name,prop,values):
    return {"target":{kind:name},"property":prop,"keyframes":[[frame,value] for frame,value in zip((0,3,6),values)]}


def clip(identifier,channels,loop=True,role=None):
    return {"id":identifier,"role":role or identifier,"loop":loop,"rootMotion":"in-place","startFrame":0,"endFrame":6,"channels":channels,"markers":[]}


def budgets(skinned):
    return {"maxTriangles":10000,"maxBones":64 if skinned else 0,"maxInfluences":4 if skinned else 0,"maxMaterials":6,"maxTextureBytes":1048576,"maxRuntimeBytes":8388608,"maxClips":24,"maxClipSeconds":5,"maxSamples":10000,"maxPreviewFrames":600,"maxAttempts":20,"timeoutSeconds":120,"maxLogBytes":16777216}


def recipe(profile,clips):
    return {"schemaVersion":1,"profile":profile,"fps":12,"requiredClips":[item["id"] for item in clips],"rig":{"mode":"preserve","rootNode":"MotionRoot"},"parts":[],"anchors":[],"clips":clips,
            "states":[{"id":item["id"],"clip":item["id"],"terminal":item["id"]=="death"} for item in clips],"transitions":[],"parameters":[],"effects":[],"budgets":budgets(profile=="skinned"),
            "review":{"renderer":"BLENDER_WORKBENCH","fps":4,"resolution":[128,128],"cameras":["front","three-quarter"]},"provenance":{"provider":"native-blender","rights":"Original controlled engineering fixture; no external artwork or animation","quality":"Does not certify production art or human acceptance"}}


def main():
    import bpy
    from mathutils import Vector
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    output=Path(args.output).resolve()
    repository=Path(__file__).resolve().parents[3]
    output.relative_to(repository)
    output.mkdir(parents=True,exist_ok=True)
    result={}

    def reset():bpy.ops.wm.read_factory_settings(use_empty=True)
    def material(name,color):
        value=bpy.data.materials.new(name);value.diffuse_color=(*color,1);value.use_nodes=True
        bsdf=value.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1)
        return value
    def cube(name,location,scale,mat):
        bpy.ops.mesh.primitive_cube_add(size=1,location=location)
        value=bpy.context.object;value.name=name;value.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);value.data.materials.append(mat)
        return value
    def export(name):
        path=output/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_animations=False)
        return path
    def write_recipe(name,value,source):
        path=output/(name+'-recipe.json');path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')
        result[name]={'model':str(source),'recipe':str(path)}

    reset();skin=material('HumanoidFixture',(0.1,0.55,0.8))
    pieces=[]
    for name,location,scale in [('Torso',(0,0,1.25),(.42,.22,.55)),('Head',(0,0,1.7),(.3,.3,.3)),('Hip',(0,0,.92),(.4,.24,.2)),
        ('ArmL',(.52,0,1.42),(.65,.14,.14)),('ArmR',(-.52,0,1.42),(.65,.14,.14)),('LegL',(.13,0,.48),(.16,.18,.82)),('LegR',(-.13,0,.48),(.16,.18,.82)),('FootL',(.13,-.08,.07),(.18,.32,.12)),('FootR',(-.13,-.08,.07),(.18,.32,.12))]:pieces.append(cube(name,location,scale,skin))
    bpy.ops.object.select_all(action='DESELECT')
    for value in pieces:value.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();body=bpy.context.object;body.name='Humanoid'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    source=export('humanoid')
    # Compute explicit fixture assignments against the actual re-imported vertices.
    reset();bpy.ops.import_scene.gltf(filepath=str(source));body=bpy.data.objects['Humanoid']
    bones=[{'name':'root','head':[0,0,0],'tail':[0,0,.2],'deform':False},
        {'name':'hips','head':[0,0,.9],'tail':[0,0,1.1],'parent':'root'},
        {'name':'spine','head':[0,0,1.1],'tail':[0,0,1.45],'parent':'hips'},
        {'name':'head','head':[0,0,1.45],'tail':[0,0,1.85],'parent':'spine'}]
    for suffix,sign in [('L',1),('R',-1)]:
        bones += [{'name':'upperarm.'+suffix,'head':[.2*sign,0,1.42],'tail':[.6*sign,0,1.42],'parent':'spine'},
            {'name':'forearm.'+suffix,'head':[.6*sign,0,1.42],'tail':[.95*sign,0,1.42],'parent':'upperarm.'+suffix},
            {'name':'thigh.'+suffix,'head':[.13*sign,0,.9],'tail':[.13*sign,0,.48],'parent':'hips'},
            {'name':'shin.'+suffix,'head':[.13*sign,0,.48],'tail':[.13*sign,0,.1],'parent':'thigh.'+suffix},
            {'name':'foot.'+suffix,'head':[.13*sign,0,.1],'tail':[.13*sign,-.22,.1],'parent':'shin.'+suffix}]
    weights={bone['name']:[] for bone in bones if bone.get('deform',True)}
    for vertex in body.data.vertices:
        point=body.matrix_world@vertex.co;distances=[]
        for bone in bones:
            if not bone.get('deform',True):continue
            a,b=Vector(bone['head']),Vector(bone['tail']);ab=b-a
            t=max(0,min(1,(point-a).dot(ab)/ab.length_squared));distance=(point-(a+t*ab)).length
            distances.append((1/max(distance,.02)**4,bone['name']))
        chosen=sorted(distances,reverse=True)[:2];total=sum(x[0] for x in chosen)
        for weight,name in chosen:weights[name].append([vertex.index,weight/total])
    groups=[{'node':'Humanoid','bone':name,'weights':value} for name,value in weights.items() if value]
    q0=[0,0,0,1]
    motions=[clip('idle',[channel('bone','spine','rotation_quaternion',[q0,quaternion(0,.04),q0])]),
        clip('run',[channel('bone','thigh.L','rotation_quaternion',[quaternion(0,-.45),quaternion(0,.45),quaternion(0,-.45)]),channel('bone','thigh.R','rotation_quaternion',[quaternion(0,.45),quaternion(0,-.45),quaternion(0,.45)]),channel('bone','upperarm.L','rotation_quaternion',[quaternion(0,.3),quaternion(0,-.3),quaternion(0,.3)])]),
        clip('jump-start',[channel('bone','hips','location',[[0,0,0],[0,-.12,0],[0,.1,0]])],False),
        clip('airborne',[channel('bone','hips','location',[[0,.1,0],[0,.15,0],[0,.1,0]])]),
        clip('land',[channel('bone','hips','location',[[0,.1,0],[0,-.15,0],[0,0,0]])],False),
        clip('swim-enter',[channel('bone','hips','rotation_quaternion',[q0,quaternion(0,.75),quaternion(0,1.5)])],False),
        clip('swim',[channel('bone','hips','rotation_quaternion',[quaternion(0,1.5),quaternion(0,1.56),quaternion(0,1.5)]),channel('bone','thigh.L','rotation_quaternion',[quaternion(0,-.2),quaternion(0,.2),quaternion(0,-.2)])]),
        clip('swim-exit',[channel('bone','hips','rotation_quaternion',[quaternion(0,1.5),quaternion(0,.75),q0])],False),
        clip('death',[channel('bone','hips','rotation_quaternion',[q0,quaternion(0,.6),quaternion(0,1.4)]),channel('bone','hips','location',[[0,0,0],[0,-.2,0],[0,-.65,0]])],False)]
    human=recipe('skinned',motions);human['rig']={'mode':'declared','node':'MotionRig','rootNode':'MotionRoot','rootBone':'root','bones':bones,'skinning':{'method':'declared-groups','groups':groups}}
    human['anchors']=[{'id':'body.center','node':'Humanoid','position':[0,0,1]}]
    human['transitions']=[{'from':'idle','to':'run','trigger':'run','duration':.25},{'from':'run','to':'jump-start','trigger':'jump','duration':.25},{'from':'swim','to':'death','trigger':'death','duration':.25}]
    write_recipe('humanoid',human,source)

    reset();metal=material('ShipMetal',(0.45,.55,.65));light=material('Thruster',(0.05,.7,1))
    cube('Hull',(0,0,.6),(.7,1.7,.35),metal);cube('ThrusterL',(-.3,.85,.6),(.18,.3,.2),light);cube('ThrusterR',(.3,.85,.6),(.18,.3,.2),light)
    source=export('ship')
    ship=recipe('rigid',[clip('cruise',[channel('node','Hull','rotation_quaternion',[q0,quaternion(1,.03),q0])]),clip('boost',[channel('node','Hull','rotation_quaternion',[q0,quaternion(0,.08),q0])]),clip('warp-enter',[channel('node','Hull','scale',[[1,1,1],[1,1.08,1],[1,1.15,1]])],False),clip('warp-sustain',[channel('node','Hull','scale',[[1,1.15,1],[1,1.18,1],[1,1.15,1]])]),clip('warp-exit',[channel('node','Hull','scale',[[1,1.15,1],[1,1.08,1],[1,1,1]])],False)])
    ship['parts']=[{'node':'Hull'},{'node':'ThrusterL','parent':'Hull'},{'node':'ThrusterR','parent':'Hull'}]
    ship['anchors']=[{'id':'exhaust.primary','node':'Hull','position':[0,1.0,0]}]
    ship['parameters']=[{'id':'speed','unit':'metres-per-second','min':0,'max':100,'default':0},{'id':'acceleration','unit':'metres-per-second-squared','min':-20,'max':20,'default':0}]
    ship['effects']=[{'id':'exhaust','type':'particles','anchor':'exhaust.primary','parameter':'speed','states':['cruise','boost','warp-enter','warp-sustain','warp-exit'],'maxParticles':64,'lifetime':.5,'space':'world','rate':30,'size':.06,'velocity':[0,0,-2],'color':[.05,.5,1],'reducedMotionScale':.25}]
    ship['transitions']=[{'from':'cruise','to':'boost','trigger':'boost','duration':.25},{'from':'boost','to':'warp-enter','trigger':'warp','duration':.25},{'from':'warp-enter','to':'warp-sustain','trigger':'entered','duration':.25},{'from':'warp-sustain','to':'warp-exit','trigger':'exit','duration':.25},{'from':'warp-enter','to':'cruise','trigger':'cancel','duration':.25},{'from':'warp-exit','to':'cruise','trigger':'exited','duration':.25}]
    write_recipe('ship',ship,source)

    reset();rubber=material('Rubber',(.08,.08,.1));bodymat=material('CarBody',(.65,.2,.1));cube('Chassis',(0,0,.45),(.85,1.6,.35),bodymat)
    parts=[{'node':'Chassis'}]
    for suffix,x,y in [('front-left',.48,-.5),('front-right',-.48,-.5),('rear-left',.48,.5),('rear-right',-.48,.5)]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.22,depth=.14,location=(x,y,.22),rotation=(0,math.pi/2,0));obj=bpy.context.object;obj.name='Wheel.'+suffix;obj.data.materials.append(rubber)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);parts.append({'node':obj.name,'parent':'Chassis','pivot':[x,y,.22],'independent':True})
    source=export('car')
    car=recipe('articulated',[clip('idle',[channel('node','Chassis','location',[[0,0,.45],[0,0,.455],[0,0,.45]])]),clip('drive',[channel('node','Chassis','rotation_quaternion',[q0,quaternion(1,.04),q0])])])
    car['parts']=parts;car['anchors']=[{'id':'wheel.front-left.contact','node':'Wheel.front-left','position':[0,0,-.22]}]
    car['parameters']=[{'id':'speed','unit':'metres-per-second','min':0,'max':50,'default':0,'bindings':[{'node':part['node'],'property':'rotation','axis':'x','mode':'angular-speed','scale':1/.22} for part in parts[1:]]}]
    car['transitions']=[{'from':'idle','to':'drive','trigger':'drive','duration':.25}]
    write_recipe('car',car,source)
    (output/'fixtures.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print('ORIGINAL_MOTION_FIXTURES',str(output/'fixtures.json'))


if __name__=='__main__':main()
