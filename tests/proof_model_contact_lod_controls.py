"""Adversarial native contact-ring LOD fixtures; no autorun or process launch.

Art, rights and admission records are SIMULATED. Native operations, export,
baking and reimport are real when root invokes the registered Blender cases.
"""
from pathlib import Path
from collections import Counter, defaultdict
from fractions import Fraction
import copy
import hashlib
import json
import math
import struct


POLICY = 'protected-contact-rings-v1'


def _f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def contact_geometry(scale=1.0, edge_contact=False, cavity=True):
    """One closed positive boundary, two touching lobes joined remotely.

    Indexed contact owners are distinct and connected elsewhere by an external
    U-tube. This is unlike two disconnected touching shells, which would never
    exercise the internally-coincident-owner retention branch.
    """
    radius = .025 * scale
    sides = 16
    xs = (-.875, -.625, -.375, -.125, .125, .375, .625, .875)
    points = [(-2*radius, 0.0, 0.0)]
    rings = []
    for x in xs:
        ring = []
        rr = radius*math.sqrt(1-x*x)
        for j in range(sides):
            angle = (j+.5)*2*math.pi/sides
            ring.append(len(points))
            points.append((radius*(x-1), rr*math.sin(angle), rr*math.cos(angle)))
        rings.append(ring)
    pole = len(points)
    points.append((0.0, 0.0, 0.0))
    if edge_contact:
        # Both lobes remain on opposite closed halfspaces. Their support sets
        # now share one geometric edge, while source vertex owners stay apart.
        vertex = rings[-1][0]
        points[vertex] = (0.0, points[vertex][1], points[vertex][2])
    faces = []
    for j in range(sides):
        faces.append((0, rings[0][j], rings[0][(j+1) % sides]))
    hole = None
    for i in range(len(rings)-1):
        for j in range(sides):
            a, b = rings[i][j], rings[i+1][j]
            c, d = rings[i+1][(j+1) % sides], rings[i][(j+1) % sides]
            if i == 3 and j == 7:
                hole = (a, b, c)
            else:
                faces.append((a, b, c))
            faces.append((a, c, d))
    for j in range(sides):
        faces.append((pole, rings[-1][(j+1) % sides], rings[-1][j]))
    left_count = len(points)
    points += [(-x, y, z) for x, y, z in list(points)]
    faces += [(left_count+a, left_count+c, left_count+b) for a, b, c in list(faces)]
    center = tuple(sum(points[v][i] for v in hole)/3 for i in range(3))
    relative = [tuple(points[v][i]-center[i] for i in range(3)) for v in hole]
    assert max(abs(v[2]) for v in relative) < 1e-14*scale
    path = [hole]
    for step in range(1, 8):
        angle = math.pi*step/8
        x = center[0]*math.cos(angle)
        z = center[2]+center[0]*math.sin(angle)
        ring = []
        for qx, qy, unused in relative:
            ring.append(len(points))
            points.append((x+math.cos(angle)*qx, center[1]+qy, z+math.sin(angle)*qx))
        path.append(tuple(ring))
    path.append(tuple(left_count+v for v in hole))
    for first, second in zip(path, path[1:]):
        for j in range(3):
            a, b = first[j], first[(j+1) % 3]
            c, d = second[(j+1) % 3], second[j]
            faces.extend(((a, b, c), (a, c, d)))
    if cavity:
        first = len(points)
        x, y, z, size = -radius-.002*scale, -.002*scale, -.002*scale, .004*scale
        points += [(x, y, z), (x+size, y, z), (x, y+size, z), (x, y, z+size)]
        tetra = ((0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3))
        faces += [(first+a, first+c, first+b) for a, b, c in tetra]
    # Canonical positive zero for source storage; signed-zero classification is
    # tested separately by exact predicate controls, without source-key changes.
    return [tuple(0.0 if value == 0 else _f32(value) for value in p) for p in points], faces


def _all_held_geometry():
    """Positive 12-face pinched prism, with every owner in the contact ring."""
    points = [(0,0,0),(-.02,-.01,-.01),(-.02,.01,-.01),(-.02,0,.01),
              (0,0,0),(.02,-.01,-.01),(.02,.01,-.01),(.02,0,.01)]
    sides = [(0,2,1),(0,1,3),(0,3,2)]
    faces = sides+[(a+4,c+4,b+4)for a,b,c in sides]
    base = (1,2,3)
    for j in range(3):
        a,b=base[j],base[(j+1)%3];c,d=b+4,a+4
        faces.extend(((a,b,c),(a,c,d)))
    x,y,z,size=-.005,0,-.006,.001
    points.extend(((x,y,z),(x+size,y,z),(x,y+size,z),(x,y,z+size)))
    faces.extend((8+a,8+c,8+b)for a,b,c in ((0,2,1),(0,1,3),(1,2,3),(2,0,3)))
    return [tuple(_f32(v)for v in p)for p in points],faces


def _sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def _cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def _dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def exact_relation(first, second):
    """Independent rational plane/segment and coplanar-clipping oracle.

    AABBs only select work. Positive-area and proper-interior predicates remain
    exact even for one-float32-ULP gaps; no epsilon classifies a defect away.
    """
    a, b = [tuple(tuple(Fraction(float(v)) for v in p) for p in tri) for tri in (first, second)]
    na, nb = _cross(_sub(a[1], a[0]), _sub(a[2], a[0])), _cross(_sub(b[1], b[0]), _sub(b[2], b[0]))
    if not any(na) or not any(nb):
        return 'degenerate'
    da, db = [_dot(nb, _sub(p, b[0])) for p in a], [_dot(na, _sub(p, a[0])) for p in b]
    if min(da) > 0 or max(da) < 0 or min(db) > 0 or max(db) < 0:
        return 'disjoint'
    line = _cross(na, nb)
    if not any(line):
        if any(da) or any(db):
            return 'disjoint'
        drop = max(range(3), key=lambda i: abs(na[i]))
        keep = [i for i in range(3) if i != drop]
        aa, bb = [[tuple(p[i] for i in keep) for p in tri] for tri in (a, b)]
        orient = lambda p, q, r: (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
        sign = 1 if orient(*bb) > 0 else -1
        polygon = aa
        for start, end in zip(bb, bb[1:]+bb[:1]):
            old, polygon = polygon, []
            if not old:
                break
            for p, q in zip(old, old[1:]+old[:1]):
                x, y = sign*orient(start, end, p), sign*orient(start, end, q)
                if x >= 0:
                    polygon.append(p)
                if (x > 0 and y < 0) or (x < 0 and y > 0):
                    t = x/(x-y)
                    polygon.append(tuple(p[i]+t*(q[i]-p[i]) for i in range(2)))
        area2 = sum(p[0]*q[1]-p[1]*q[0] for p, q in zip(polygon, polygon[1:]+polygon[:1])) if polygon else 0
        return 'disjoint' if not polygon else 'coplanar-positive' if area2 else 'contact'
    axis = max(range(3), key=lambda i: abs(line[i]))

    def interval(triangle, distances):
        points = [p[axis] for p, d in zip(triangle, distances) if d == 0]
        for i in range(3):
            j = (i+1) % 3
            if distances[i]*distances[j] < 0:
                t = distances[i]/(distances[i]-distances[j])
                points.append(triangle[i][axis]+t*(triangle[j][axis]-triangle[i][axis]))
        return (min(points), max(points)) if points else None

    x, y = interval(a, da), interval(b, db)
    if x is None or y is None or max(x[0], y[0]) > min(x[1], y[1]):
        return 'disjoint'
    if max(x[0], y[0]) < min(x[1], y[1]) and min(da) < 0 < max(da) and min(db) < 0 < max(db):
        return 'proper'
    return 'contact'


def physical(points, faces, maximum_pairs=100000, maximum_seconds=30):
    import numpy as np
    import time
    started = time.monotonic()
    triangles = np.asarray(points, np.float64)[np.asarray(faces, np.int32)]
    low, high = triangles.min(1), triangles.max(1)
    counts, pairs = Counter(), 0
    for i in range(len(faces)):
        if i % 32 == 0 and time.monotonic()-started > maximum_seconds:
            raise AssertionError('Test exact oracle deadline; incomplete is not a pass')
        js = np.flatnonzero(np.all(low[i+1:] <= high[i], axis=1) & np.all(high[i+1:] >= low[i], axis=1))+i+1
        for j in js:
            assert pairs < maximum_pairs, 'Test exact oracle pair cap'
            counts[exact_relation(triangles[i], triangles[j])] += 1
            pairs += 1
    return {'complete': True, 'inclusiveAabbPairs': pairs, 'relations': dict(counts), 'seconds': time.monotonic()-started}


def run_exact_controls():
    import numpy as np
    result = []
    for scale in (.01, 1, 32):
        s,z=_f32(scale),_f32(scale*.125)
        below=float(np.nextafter(np.float32(z),np.float32(-np.inf)))
        above=float(np.nextafter(np.float32(z),np.float32(np.inf)))
        p=lambda x,y,zz:( _f32(s*x),_f32(s*y),zz)
        a=(p(0,0,z),p(1,0,z),p(0,1,z))
        cases=[('shared-edge',a,(p(0,0,z),p(1,0,z),p(0,-1,z)),'contact'),
               ('point-only-signed-zero',a,((-0.0,0.0,z),p(-1,0,z),p(0,-1,z)),'contact'),
               ('coplanar-overlap',a,(p(.1,.1,z),p(.6,.1,z),p(.1,.6,z)),'coplanar-positive'),
               ('coplanar-disjoint-with-overlapping-aabb',a,(p(.8,.8,z),p(1,.8,z),p(.8,1,z)),'disjoint'),
               ('strict-one-f32-ulp-cross',a,(p(.25,.25,below),p(.75,.25,above),p(.25,.75,above)),'proper'),
               ('strict-one-f32-ulp-gap',a,(p(.25,.25,above),p(.75,.25,above),p(.25,.75,above)),'disjoint')]
        for name, first, second, expected in cases:
            value = exact_relation(first,second)
            assert value == expected, (name, scale, value)
            result.append({'case': name, 'scale': scale, 'relation': value,
                           'everyInputCoordinateExactlyF32':True,'planeF32':z,'oneF32StepBelow':below,'oneF32StepAbove':above,
                           'execution': 'EXACT_RATIONAL_NOT_NATIVE'})
    return result


def _field(items, prop, width, dtype):
    import numpy as np
    result = np.empty(len(items)*width, dtype)
    items.foreach_get(prop, result)
    return result


def _snapshot(obj):
    import numpy as np
    mesh = obj.data
    fields = {'positions': _field(mesh.vertices, 'co', 3, np.float32),
              'loops': _field(mesh.loops, 'vertex_index', 1, np.int32),
              'edges': _field(mesh.edges, 'vertices', 2, np.int32),
              'starts': _field(mesh.polygons, 'loop_start', 1, np.int32),
              'counts': _field(mesh.polygons, 'loop_total', 1, np.int32),
              'materials': _field(mesh.polygons, 'material_index', 1, np.int32),
              'smooth': _field(mesh.polygons, 'use_smooth', 1, np.bool_),
              'normals': _field(mesh.corner_normals, 'vector', 3, np.float32),
              'sharp':_field(mesh.edges,'use_edge_sharp',1,np.bool_),
              'seams':_field(mesh.edges,'use_seam',1,np.bool_)}
    for uv in mesh.uv_layers:
        fields['uv:'+uv.name] = _field(uv.data, 'uv', 2, np.float32)
    attributes=[]
    encodings={'FLOAT':('value',1,np.float32),'INT':('value',1,np.int32),'BOOLEAN':('value',1,np.bool_),
               'FLOAT_VECTOR':('vector',3,np.float32),'FLOAT2':('vector',2,np.float32),
               'INT32_2D':('value',2,np.int32),'INT16_2D':('value',2,np.int16)}
    for attr in mesh.attributes:
        if attr.name in mesh.uv_layers:continue
        assert attr.data_type in encodings
        prop,width,dtype=encodings[attr.data_type]
        attributes.append((attr.name,attr.domain,attr.data_type,hashlib.sha256(_field(attr.data,prop,width,dtype).tobytes()).hexdigest()))
    return {'fields': {k: hashlib.sha256(v.tobytes()).hexdigest() for k, v in fields.items()},'attributes':sorted(attributes),
            'world': [[float(v) for v in row] for row in obj.matrix_world],
            'uvMetadata': [(u.name,u.active_render,u.active_clone) for u in mesh.uv_layers],
            'materials': [m.as_pointer() for m in mesh.materials]}


def _rows(obj):
    import numpy as np
    mesh = obj.data
    mesh.calc_loop_triangles()
    points = _field(mesh.vertices, 'co', 3, np.float32).reshape((-1,3))
    faces, rows = [], []
    for triangle in mesh.loop_triangles:
        ids, loops = tuple(triangle.vertices), tuple(triangle.loops)
        corners = []
        for vi, li in zip(ids, loops):
            corners.append(points[vi].tobytes()+b''.join(np.asarray(layer.data[li].uv,np.float32).tobytes() for layer in mesh.uv_layers))
        rotation = min(range(3), key=lambda k:tuple(corners[k:]+corners[:k]))
        rows.append({'key':(mesh.polygons[triangle.polygon_index].material_index, tuple(corners[rotation:]+corners[:rotation])),
                     'vertices':ids[rotation:]+ids[:rotation], 'loops':loops[rotation:]+loops[:rotation],
                     'polygon':triangle.polygon_index})
        faces.append(ids)
    return points, faces, rows


def _groups(points, faces):
    parents = list(range(len(points)))
    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    for face in faces:
        for vertex in face[1:]:
            a, b = find(face[0]), find(vertex)
            if a != b:
                parents[b] = a
    grouped = defaultdict(list)
    for i, face in enumerate(faces):
        grouped[find(face[0])].append(i)
    result = []
    for ids in grouped.values():
        vertices = sorted({v for i in ids for v in faces[i]})
        origin = points[vertices[0]]
        volume = sum(_dot(_sub(points[a],origin),_cross(_sub(points[b],origin),_sub(points[c],origin)))/6
                     for i in ids for a,b,c in [faces[i]])
        assert volume != 0
        result.append({'faces':ids,'vertices':vertices,'sign':1 if volume > 0 else -1})
    return result


def contact_snapshot(obj):
    """Independent protected source-corner/owner oracle, not runtime hashes."""
    points, faces, rows = _rows(obj)
    groups = _groups(points.astype(float), faces)
    protected, negative, aliases = [], [], []
    for group in groups:
        if group['sign'] < 0:
            negative.extend(group['faces'])
            continue
        coordinates = defaultdict(list)
        for vi in group['vertices']:
            coordinates[tuple(float(x) for x in points[vi])].append(vi)
        same = [ids for ids in coordinates.values() if len(ids) > 1]
        aliases.extend(same)
        held = {vi for ids in same for vi in ids}
        protected.extend(i for i in group['faces'] if any(vi in held for vi in faces[i]))
    assert aliases and protected and len(groups) == 2
    return {'points':points,'faces':faces,'rows':rows,'protected':sorted(protected),'negative':sorted(negative),
            'aliases':aliases,'groups':groups,'hardUvEdges':_hard_uv_edges(obj),
            'world':[[float(x)for x in row]for row in obj.matrix_world],
            'uvMetadata':[(u.name,u.active_render,u.active_clone)for u in obj.data.uv_layers]}


def _hard_uv_edges(obj):
    import numpy as np
    mesh=obj.data;edges=defaultdict(list);points=np.asarray([tuple(v.co)for v in mesh.vertices],np.float32)
    for polygon in mesh.polygons:
        loops=list(polygon.loop_indices)
        for first,second in zip(loops,loops[1:]+loops[:1]):
            a,b=mesh.loops[first].vertex_index,mesh.loops[second].vertex_index
            if a>b:a,b,first,second=b,a,second,first
            side=(polygon.material_index,tuple(np.asarray((*u.data[first].uv,*u.data[second].uv),np.float32).tobytes()for u in mesh.uv_layers))
            edges[(a,b)].append(side)
    result=Counter()
    for(a,b),sides in edges.items():
        assert len(sides)==2
        if sides[0]==sides[1]:continue
        pa,pb=points[a].tobytes(),points[b].tobytes()
        if pa>pb:
            pa,pb=pb,pa;sides=[(m,tuple(v[8:]+v[:8]for v in values))for m,values in sides]
        result[(pa,pb,tuple(sorted(sides)))]+=1
    return result


def verify_contact_snapshot(reference, candidate, api, bound):
    import numpy as np
    measured = api.topology_measure(candidate)
    assert measured['boundaryEdges'] == measured['nonManifoldEdges'] == measured['inconsistentWindingEdges'] == measured['nonManifoldVertices'] == measured['looseVertices'] == measured['degenerateFaces'] == 0
    points, faces, rows = _rows(candidate)
    groups = _groups(points.astype(float), faces)
    assert sorted(g['sign'] for g in groups) == [-1,1]
    lookup = defaultdict(list)
    for row in rows:
        lookup[row['key']].append(row)
    owner_map = {}
    for index in reference['protected']+reference['negative']:
        old = reference['rows'][index]
        assert len(lookup[old['key']]) == 1, 'Protected triangle positions/winding/UV/material absent/ambiguous'
        actual = lookup[old['key']][0]
        for before, after in zip(old['vertices'],actual['vertices']):
            assert before not in owner_map or owner_map[before] == after, 'Protected source owner split'
            owner_map[before] = after
            assert reference['points'][before].tobytes() == points[after].tobytes(), 'Protected owner position changed'
    assert len(set(owner_map.values())) == len(owner_map), 'Distinct source owners merged'
    for alias in reference['aliases']:
        assert len({owner_map[v] for v in alias}) == len(alias)
    negative_actual = next(g for g in groups if g['sign'] < 0)
    assert Counter(rows[i]['key'] for i in negative_actual['faces']) == Counter(reference['rows'][i]['key'] for i in reference['negative'])
    assert [(u.name,u.active_render,u.active_clone)for u in candidate.data.uv_layers] == reference['uvMetadata']
    assert _hard_uv_edges(candidate)==reference['hardUvEdges'], 'Complete hard UV/material boundary changed'
    assert [[float(x)for x in row]for row in candidate.matrix_world]==reference['world']
    # Independent actual BVH queries per signed boundary, never nearest unrelated
    # surfaces. These are finite all-vertex checks, not Hausdorff certification.
    from mathutils.bvhtree import BVHTree
    errors = []
    frame=np.asarray(reference['world'],np.float64)
    old_world=reference['points'].astype(np.float64)@frame[:3,:3].T+frame[:3,3]
    new_world=points.astype(np.float64)@frame[:3,:3].T+frame[:3,3]
    for source in reference['groups']:
        target = next(g for g in groups if g['sign'] == source['sign'])
        a = BVHTree.FromPolygons([tuple(p)for p in old_world], [reference['faces'][i]for i in source['faces']], all_triangles=True)
        b = BVHTree.FromPolygons([tuple(p)for p in new_world], [faces[i]for i in target['faces']], all_triangles=True)
        pair = [max(b.find_nearest(tuple(old_world[vi]))[3]for vi in source['vertices']),
                max(a.find_nearest(tuple(new_world[vi]))[3]for vi in target['vertices'])]
        assert max(pair) <= bound
        errors.append(pair)
    exact = physical(points, faces)
    assert not any(exact['relations'].get(k,0) for k in ('proper','coplanar-positive','degenerate'))
    return {'protectedTriangles':len(reference['protected']), 'negativeTriangles':len(reference['negative']),
            'protectedOwnerVertices':len(owner_map),'distinctContactOwnerClasses':len(reference['aliases']),
            'everyProtectedCornerUvMaterialWindingAndOwnerExact':True,'negativeBoundaryExact':True,
            'independentEveryVertexBoundaryDistances':errors,'completeExactPhysical':exact,'triangles':len(faces)}


def replace_fixture_core(root, job, rigid, api, topology, *, scale=1.0, edge_contact=False,
                         textured=True, all_held=False, import_prepared=False, smooth=False):
    """Rebuild SIMULATED fixture inputs before immutable admission, not assets."""
    import bpy, numpy as np, shutil, zlib
    root = Path(root)
    points, faces = _all_held_geometry() if all_held else contact_geometry(scale, edge_contact)
    image_path = root/'contact-pattern.png'
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    pixels = (b'\0'+bytes((96,128,160,255))*2)*2
    image_path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))
    image = bpy.data.images.load(str(image_path),check_existing=False);image.pack()
    materials = []
    for label in ('surface','protected'):
        material = bpy.data.materials.new('SIMULATED.ContactRing.'+label);material.use_nodes=True
        if textured:
            texture = material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
            uv = material.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='UVMap'
            material.node_tree.links.new(uv.outputs['UV'],texture.inputs['Vector'])
            material.node_tree.links.new(texture.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        materials.append(material)
    coords = np.asarray(points,np.float32)
    # A fixed oblique affine projection is continuous across every source edge
    # and non-collinear on all fixture faces, including the tetra's axis planes.
    # The native UV guard still verifies the actual stored float32 field.
    q = coords[:,0]+math.sqrt(5)*coords[:,1]+math.sqrt(7)*coords[:,2]
    r = math.sqrt(2)*coords[:,0]+math.sqrt(3)*coords[:,1]+math.sqrt(11)*coords[:,2]
    u = (q-q.min())/(q.max()-q.min())*.6+.2
    v = (r-r.min())/(r.max()-r.min())*.6+.2
    aliases = Counter(tuple(p)for p in points)
    contact_face = next(i for i,f in enumerate(faces)if any(aliases[tuple(points[v])] > 1 for v in f))
    for name in ('core_HIGH','core_LOW'):
        obj = bpy.data.objects[name];old=obj.data
        mesh = bpy.data.meshes.new('SIMULATED.ContactRing.'+name);mesh.from_pydata(points,[],faces);mesh.update()
        for mat in materials:mesh.materials.append(mat)
        layer=mesh.uv_layers.new(name='UVMap')
        for loop in mesh.loops:layer.data[loop.index].uv=(float(u[loop.vertex_index]),float(v[loop.vertex_index]))
        mesh.polygons[contact_face].material_index=1
        for face in mesh.polygons:face.use_smooth=smooth
        obj.data=mesh
        if old.users==0:bpy.data.meshes.remove(old)
        api.uv_measure(obj);api.require_usable(obj,'SIMULATED contact fixture')
    bpy.context.view_layer.update()
    sources=[bpy.data.objects[name]for name in ('core_HIGH','core_LOW','marker_HIGH','marker_LOW')]
    authored_before={source.name:_snapshot(source)for source in sources}
    bpy.ops.object.select_all(action='DESELECT')
    for source in sources:source.select_set(True)
    assert bpy.ops.export_scene.gltf(filepath=str(root/'prepared.glb'),export_format='GLB',use_selection=True)=={'FINISHED'}
    glb=api.inspect_glb(root/'prepared.glb')
    node=next(row for row in glb['nodes']if row.get('name')=='core_LOW')
    primitives=glb['meshes'][node['mesh']]['primitives']
    render_vertices=sum(glb['accessors'][p['attributes']['POSITION']]['count']for p in primitives)
    if smooth:
        # Real packing sees the exported render graph. Flat split normals can
        # fragment that graph into per-face UV charts, making all owners held.
        # Only this authored end-to-end fixture selects smooth normals; source
        # owner/contact authority still comes from the original native receipt.
        assert render_vertices<=len(points)+3,'Smooth fixture has unexpected non-material render seams'
    authored_after_export={source.name:_snapshot(source)for source in sources}
    assert authored_before==authored_after_export,'Fixture export changed authored source fields'
    shutil.copyfile(root/'prepared.glb',root/'raw.glb')
    sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
    def write(path, data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    receipt_path='.hephaera/.cache/tasks/fixture/source-topology.json'
    receipt=topology.capture(root/'prepared.glb',[o for o in sources if o.name.endswith('_LOW')],rigid,max_file_bytes=10000000)
    authored_after_capture={source.name:_snapshot(source)for source in sources}
    assert authored_after_export==authored_after_capture,'Fixture capture changed authored source fields'
    write(root/receipt_path,receipt)
    authoring=json.loads((root/'authoring.json').read_text());handoff=job['rigidHandoff']
    authoring.update(sourceRawSha256=sha(root/'raw.glb'),preparedGlbSha256=sha(root/'prepared.glb'))
    for row in authoring['repairs']:
        row['highTriangles']=api.triangles(bpy.data.objects[row['partId']+'_HIGH']);row['lowTriangles']=api.triangles(bpy.data.objects[row['partId']+'_LOW'])
    authoring['sources']=[r for r in authoring['sources']if r['path']!=receipt_path]+[{'path':receipt_path,'sha256':sha(root/receipt_path),'role':'SIMULATED actual source-owned contact/cavity receipt'}]
    write(root/'authoring.json',authoring)
    handoff.update(sourceRawSha256=sha(root/'raw.glb'),preparedGlbSha256=sha(root/'prepared.glb'),authoringEvidenceSha256=sha(root/'authoring.json'))
    for part in handoff['parts']:part['maxTriangles']=1500
    write(root/'handoff.json',handoff)
    settings=job['finishingSettings'];settings['rigidParts']['handoffSha256']=sha(root/'handoff.json')
    settings['rigidParts']['sourceTopology']={'method':'reviewed-source-corners-v1','receipt':receipt_path,'receiptSha256':sha(root/receipt_path)}
    settings['rigidParts']['lods']['contactPolicy']=POLICY
    settings['rigidParts']['maxLod0Triangles']=2000
    review_path=root/settings['rigidParts']['reviewEvidence'];review=json.loads(review_path.read_text())
    review.update(sourceRawSha256=sha(root/'raw.glb'),preparedGlbSha256=sha(root/'prepared.glb'),handoffSha256=sha(root/'handoff.json'),authoringEvidenceSha256=sha(root/'authoring.json'))
    write(review_path,review);settings['rigidParts']['reviewEvidenceSha256']=sha(review_path)
    job['recipe']['maxTriangles']=5000
    representation={'authoredExportAndCaptureGuardsExact':True,'authored':authored_after_capture,
        'authoredSmoothNormalsSelected':smooth,'authoredOwnerVertices':len(points),'actualExportedRenderVertices':render_vertices,
        'receiptSha256':sha(root/receipt_path),'preparedGlbSha256':sha(root/'prepared.glb'),
        'directBuilderUsesActuallyImportedGlb':import_prepared,
        'sourceOwnerAuthority':'Authored native vertex IDs captured into actual GLB corner order; imported render indices are not authority'}
    if import_prepared:
        # This deliberately resets the authored scene. Bindings expect the
        # actual importer's UV decode, not the pre-export native UV bytes.
        imported=api.import_glb(root/'prepared.glb')
        bpy.context.view_layer.update()
        assert {obj.name for obj in imported}==set(authored_after_capture)
        representation['actuallyImported']={obj.name:_snapshot(obj)for obj in imported}
        assert api.triangles(bpy.data.objects['core_LOW'])==len(faces)
    write(root/'contact-fixture-representations.json',representation)
    bindings=topology.load(root/receipt_path,root/'prepared.glb',handoff,rigid,
                           expected_receipt_sha256=sha(root/receipt_path),max_file_bytes=10000000)
    return job,bindings


def _source_owned_snapshot(source, binding, rigid):
    """Independent reference on the receipt's authored graph and imported UVs."""
    import bpy
    before=_snapshot(source);objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
    owned=binding.reindex_copy(source,rigid,preserve_loops=True)
    try:return contact_snapshot(owned)
    finally:
        _dispose([owned])
        assert _snapshot(source)==before and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes


def _dispose(objects):
    import bpy
    for obj in objects:
        mesh=obj.data;bpy.data.objects.remove(obj,do_unlink=True)
        if mesh.users==0:bpy.data.meshes.remove(mesh)


def _finite(report):
    for level in report['levels']:
        for component in level['components']:
            grid=component['finiteRatioGrid']
            assert grid==sorted(set(grid)) and grid[-1]==1 and len(grid)<=10
            assert len(component['trials'])<=len(grid)
            assert all(t['gridRatio']==r for t,r in zip(component['trials'],grid))


def _profile(rigid,job,selected=True):
    settings=copy.deepcopy(job['finishingSettings'])
    if not selected:settings['rigidParts']['lods'].pop('contactPolicy')
    profile=rigid.resolve_lod_settings(settings,job['recipe'])
    profile['componentPolicy']='retain-every-reviewed-signed-boundary-min4'
    if selected:assert profile['contactPolicy']==POLICY
    else:assert 'contactPolicy'not in profile
    return profile


def run_regressions(rigid,api,topology,work,factory):
    """Root invokes once inside real Blender; injected faults are labelled."""
    import bpy,bmesh,numpy as np
    from unittest.mock import patch
    def report_evidence(label,report):
        path=Path(work)/('contact-'+label+'-native-report.json')
        with path.open('x',encoding='utf-8')as stream:json.dump(report,stream,indent=2,allow_nan=False);stream.write('\n')
        return {'path':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    result={'status':'STARTED','cases':[],'exactRationalControls':run_exact_controls(),
            'nativeExecution':True,'artRightsReviews':'SIMULATED','humanAcceptance':False}
    for edge in (False,True):
        root,job,bindings=factory(edge_contact=edge,scale=1)
        source=bpy.data.objects['core_LOW'];binding=bindings[source.name]
        reference=_source_owned_snapshot(source,binding,rigid);guard=_snapshot(source)
        assert len(reference['aliases'])==(2 if edge else 1)
        source_faces=len(reference['faces'])
        for selected in (False,True):
            profile=_profile(rigid,job,selected)
            objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
            outputs,report=rigid._clod_build_constrained_lods(source,profile,api,
                name_prefix=('Edge'if edge else'Point')+('Selected'if selected else'Default'),source_topology=binding)
            try:
                _finite(report)
                checked=[verify_contact_snapshot(reference,lod,api,level['maxVertexSurfaceErrorMetres'])
                         for lod,level in zip(outputs,profile['levels'])]
                if selected:
                    assert any(row['triangles']<source_faces for row in checked), 'No actual contact-ring reduction occurred'
                    assert report['exactWeldRemovedSeamVertices'] is None
                else:
                    assert all(row['triangles']==source_faces for row in checked), 'Omitted policy changed exact default'
                result['cases'].append({'case':('edge'if edge else'point')+('-selected'if selected else'-default'),
                    'execution':'ACTUAL_NATIVE','sourceTriangles':source_faces,'levels':checked,
                    'nativeReport':report_evidence(('edge'if edge else'point')+('-selected'if selected else'-default'),report),
                    'actualReductionAwayFromProtectedRing':selected,'sourceGuardExact':_snapshot(source)==guard})
            finally:_dispose(outputs)
            assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes

    root,job,bindings=factory(edge_contact=False,scale=1,textured=False)
    source=bpy.data.objects['core_LOW'];guard=_snapshot(source);reference=_source_owned_snapshot(source,bindings[source.name],rigid)
    objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
    profile=_profile(rigid,job)
    outputs,report=rigid._clod_build_constrained_lods(source,profile,api,name_prefix='ConstantContact',source_topology=bindings[source.name])
    try:
        assert report['materialDependency']['policy']=='deterministic-unit-grid-triangles'
        checked=[verify_contact_snapshot(reference,lod,api,level['maxVertexSurfaceErrorMetres'])for lod,level in zip(outputs,profile['levels'])]
        assert any(row['triangles']<562 for row in checked)
        result['cases'].append({'case':'constant-material-selected','execution':'ACTUAL_NATIVE','levels':checked,
                              'protectedAndNegativeUvsNotRegenerated':True,'nativeReport':report_evidence('constant-selected',report)})
    finally:_dispose(outputs)
    assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes

    # Constant-material positive geometry whose complete contact one-ring holds
    # every original owner must retain finitely without a native modifier call.
    root,job,bindings=factory(all_held=True,textured=False)
    source=bpy.data.objects['core_LOW'];binding=bindings[source.name]
    reference=_source_owned_snapshot(source,binding,rigid);guard=_snapshot(source)
    objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
    positive=next(g for g in reference['groups']if g['sign']>0)
    assert len(positive['faces'])==12
    assert {v for i in reference['protected']for v in reference['faces'][i]}==set(positive['vertices'])
    def no_native(*args,**kwargs):raise AssertionError('All-held Euler-locked fixture invoked COLLAPSE')
    with patch.object(rigid,'_clod_apply_collapse',no_native):
        outputs,report=rigid._clod_build_constrained_lods(source,_profile(rigid,job),api,
            name_prefix='AllHeldConstantContact',source_topology=binding)
    try:
        _finite(report)
        checks=[verify_contact_snapshot(reference,lod,api,level['maxVertexSurfaceErrorMetres'])
                for lod,level in zip(outputs,_profile(rigid,job)['levels'])]
        assert all(row['triangles']==16 for row in checks)
        assert report['materialDependency']['policy']=='deterministic-unit-grid-triangles'
        for level in report['levels']:
            for component in level['components']:
                assert component['terminalOriginalRetention']
                assert all(t['status']=='rejected'for t in component['trials'][:-1])
                assert all(not t.get('nativeModifier')for t in component['trials'])
        result['cases'].append({'case':'all-held-positive-uv-independent','execution':'ACTUAL_NATIVE_GEOMETRY_GUARDS_NO_COLLAPSE',
            'allOriginalContactOwnersHeld':True,'finiteTerminalRetention':True,'levels':checks,
            'nativeReport':report_evidence('all-held-positive',report)})
    finally:_dispose(outputs)
    assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes

    # Small but legal native geometry keeps all deliberately injected distances
    # below the unchanged3mm guard; physical defects cannot hide behind an error
    # bound failure. Every native face still must exceed1e-12.
    root,job,bindings=factory(edge_contact=False,scale=.01)
    source=bpy.data.objects['core_LOW'];binding=bindings[source.name]
    reference=_source_owned_snapshot(source,binding,rigid);guard=_snapshot(source);profile=_profile(rigid,job)
    objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
    for label,value in [('unknown','other-v1'),('null',None),('boolean',True),('number',1),('object',{})]:
        bad=copy.deepcopy(profile);bad['contactPolicy']=value
        try:rigid._clod_build_constrained_lods(source,bad,api,name_prefix='Invalid'+label,source_topology=binding)
        except (ValueError,TypeError):pass
        else:raise AssertionError('Invalid explicit contact policy accepted '+label)
        assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
        result['cases'].append({'case':'invalid-'+label,'execution':'ACTUAL_NATIVE_VALIDATOR','rejected':True})
    missing=copy.deepcopy(profile);missing['componentPolicy']='retain-every-original-closed-positive-component-min4'
    try:rigid._clod_build_constrained_lods(source,missing,api,name_prefix='MissingBinding')
    except ValueError:pass
    else:raise AssertionError('Selected contact policy without actual sourceTopology binding accepted')
    assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
    result['cases'].append({'case':'selected-without-source-topology','execution':'ACTUAL_NATIVE_VALIDATOR','rejected':True})

    original_apply=rigid._clod_apply_collapse
    for label in ('position','uv','material','winding','owner','merge','nonfinite','subfloor','proper','coplanar'):
        hits=[]
        def injected(obj,*args,**kwargs):
            measured=original_apply(obj,*args,**kwargs)
            points,faces,rows=_rows(obj)
            before_tamper_triangles=len(faces)
            fault_physical=None
            lookup={row['key']:row for row in rows}
            first=reference['rows'][reference['protected'][0]]
            assert first['key']in lookup,'Native modifier altered protected ring before simulated fault'
            actual=lookup[first['key']];mesh=obj.data
            if label=='position':
                vi,axis=max(((v,k)for v in actual['vertices']for k in range(3)),key=lambda item:abs(mesh.vertices[item[0]].co[item[1]]))
                old=np.float32(mesh.vertices[vi].co[axis]);assert old!=0
                mesh.vertices[vi].co[axis]=float(np.nextafter(old,np.float32(np.inf)))
            elif label=='uv':mesh.uv_layers[0].data[actual['loops'][0]].uv.x+=.03125
            elif label=='material':mesh.polygons[actual['polygon']].material_index^=1
            elif label=='winding':
                bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();bmesh.ops.reverse_faces(bm,faces=[bm.faces[actual['polygon']]]);bm.to_mesh(mesh);bm.free()
            elif label=='owner':
                attr=mesh.attributes.get('hephaera_contact_owner')
                assert attr is not None and attr.domain=='POINT' and attr.data_type=='INT'
                vi=actual['vertices'][0];assert attr.data[vi].value>0;attr.data[vi].value=0
            elif label=='merge':
                alias=reference['aliases'][0];mapping={}
                for fi in reference['protected']:
                    old=reference['rows'][fi];new=lookup[old['key']]
                    mapping.update(zip(old['vertices'],new['vertices']))
                a,b=(mapping[vi]for vi in alias)
                bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table();bmesh.ops.weld_verts(bm,targetmap={bm.verts[b]:bm.verts[a]});bm.to_mesh(mesh);bm.free()
            elif label=='nonfinite':
                mesh.vertices[actual['vertices'][0]].co.x=float('nan')
                assert math.isnan(mesh.vertices[actual['vertices'][0]].co.x)
            elif label=='subfloor':
                owners=mesh.attributes['hephaera_contact_owner']
                eligible=[face for face in faces if all(owners.data[v].value==0 for v in face)]
                assert eligible
                a,b,c=max(eligible,key=lambda face:float(points[list(face),0].mean()))
                mesh.vertices[a].co=(points[b].astype(float)+points[c].astype(float))*.5
                mesh.update()
                assert api.topology_measure(obj,allow_degenerate=True)['degenerateFaces']>0
            else:
                owners=mesh.attributes['hephaera_contact_owner']
                free=[i for i in range(len(mesh.vertices))if owners.data[i].value==0]
                assert free
                if label=='proper':
                    vi=max(free,key=lambda v:mesh.vertices[v].co.x)
                    mesh.vertices[vi].co.x=-.00025
                else:
                    eligible=[i for i,face in enumerate(faces)if all(owners.data[v].value==0 for v in face)]
                    assert len(eligible)>2
                    first=max(eligible,key=lambda i:float(points[list(faces[i]),0].mean()))
                    second=min(eligible,key=lambda i:float(points[list(faces[i]),0].mean()))
                    assert not set(faces[first])&set(faces[second])
                    for vi,target in zip(faces[first],faces[second]):mesh.vertices[vi].co=points[target]
                mesh.update()
                # Real topology/area stay usable; the inserted defect is an
                # actual geometric pair, not an AABB or mocked predicate result.
                api.require_usable(obj,'SIMULATED invalid-intersection native output')
                fault_points,fault_faces,unused=_rows(obj)
                relation=physical(fault_points,fault_faces)
                assert relation['relations'].get('proper'if label=='proper'else'coplanar-positive',0)>0
                fault_physical=relation
            mesh.update();hits.append({'kind':label,'actualNativeTrianglesBeforeTamper':before_tamper_triangles,
                'independentExactFaultPhysical':fault_physical,
                'execution':'ACTUAL_NATIVE_OPERATOR_THEN_SIMULATED_OUTPUT_TAMPER'})
            return measured
        with patch.object(rigid,'_clod_apply_collapse',injected):
            outputs,report=rigid._clod_build_constrained_lods(source,profile,api,name_prefix='Reject'+label,source_topology=binding)
        try:
            assert hits,'Fault never reached an actual reduction trial'
            assert any(row['actualNativeTrianglesBeforeTamper']<558 for row in hits), 'Fault never exercised an actual native reduction'
            _finite(report)
            for level in report['levels']:
                positive=next(c for c in level['components']if c['sourceComponentId']==next(r['sourceComponentId']for r in report['originalComponents']if r['topology']['worldSignedOrientation']>0))
                assert all(t['status']=='rejected'for t in positive['trials'][:-1])
                assert positive['terminalOriginalRetention']and positive['triangles']==558
            for lod,level in zip(outputs,profile['levels']):verify_contact_snapshot(reference,lod,api,level['maxVertexSurfaceErrorMetres'])
            if label in ('proper','coplanar'):
                rejected=[t for level in report['levels']for component in level['components']for t in component['trials']
                          if t['status']=='rejected'and t.get('withinBoundaryPhysical',{}).get('kind')]
                assert rejected,'No real complete physical guard rejected the injected intersecting output'
            result['cases'].append({'case':'reject-'+label,'execution':'INJECTED_NATIVE_OUTPUT_FAULT_REAL_GUARDS','hits':hits,
                                  'acceptedOnlyExactTerminalRetention':True,'nativeReport':report_evidence('reject-'+label,report)})
        finally:_dispose(outputs)
        assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes

    for after_native in (False,True):
        hit=[]
        proof_names=binding.contact_lod_names()
        def tracked(*args,**kwargs):
            answer=original_apply(*args,**kwargs);hit.append(True);return answer
        def cancel():
            if hit or not after_native:raise RuntimeError('TEST injected contact cancellation')
        with patch.object(rigid,'_clod_apply_collapse',tracked):
            try:rigid._clod_build_constrained_lods(source,profile,api,name_prefix='CancelContact',source_topology=binding,cancel=cancel)
            except ValueError as error:
                assert 'TEST injected contact cancellation'in str(error)
                cancellation_report=report_evidence('cancel-after-native'if after_native else'cancel-before',getattr(error,'report',{}))
            else:raise AssertionError('Contact LOD cancellation accepted')
        assert bool(hit)==after_native and _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
        assert binding.contact_lod_names()==proof_names,'Cancelled work retained stale private LOD proof'
        result['cases'].append({'case':'cancel-after-native'if after_native else'cancel-before-work',
                              'execution':'INJECTED_CALLBACK_WITH_REAL_NATIVE_WHEN_REACHED','cleanupExact':True,'nativeReport':cancellation_report})
    budget=copy.deepcopy(profile);budget['budgets']={'maxLod0Triangles':562,'maxPackageTriangles':563}
    proof_names=binding.contact_lod_names()
    try:rigid._clod_build_constrained_lods(source,budget,api,name_prefix='BudgetContact',source_topology=binding)
    except ValueError as error:budget_report=report_evidence('global-package-budget',getattr(error,'report',{}))
    else:raise AssertionError('Complete constrained package budget silently exceeded')
    assert _snapshot(source)==guard and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
    assert binding.contact_lod_names()==proof_names,'Rejected package retained stale private LOD proof'
    result['cases'].append({'case':'global-package-budget','execution':'ACTUAL_NATIVE','rejected':True,
                          'cleanupExact':True,'nativeReport':budget_report})
    result.update(status='NATIVE_PROTECTED_CONTACT_RING_CONTROLS_PASS',sourceAndOwnedCleanupExact=True,
                  negativeCavityExact=True,actualReductionAwayFromProtectedContactTriangles=True,
                  finiteSearchAndUnchangedAreaErrorBudgetGuards=True,sourceTopologyRequired=True)
    return result


def _indexed_components(count, faces):
    parent=list(range(count))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for face in faces:
        for v in face[1:]:
            a,b=find(int(face[0])),find(int(v))
            if a!=b:parent[b]=a
    return len({find(int(face[0]))for face in faces})


def _except_uv(snapshot):
    result=copy.deepcopy(snapshot)
    result['fields']={k:v for k,v in result['fields'].items()if not k.startswith('uv:')}
    result.pop('uvMetadata')
    return result


def owner_uv_preconditions(root, job, rigid, api, topology):
    """Actual flat GLB import; negative maps reject before any helper allocation."""
    import bpy, numpy as np
    from unittest.mock import patch
    root=Path(root);api.import_glb(root/'prepared.glb');bpy.context.view_layer.update()
    selected=job['finishingSettings']['rigidParts']['sourceTopology']
    bindings=topology.load(root/selected['receipt'],root/'prepared.glb',job['rigidHandoff'],rigid,
        expected_receipt_sha256=selected['receiptSha256'],max_file_bytes=10000000)
    lows=[bpy.data.objects[part['lowObject']]for part in job['rigidHandoff']['parts']]
    for part,low in zip(job['rigidHandoff']['parts'],lows):low['semanticPart']=part['id']
    before={low.name:_snapshot(low)for low in lows};objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
    mappings={low.name:bindings[low.name]for low in lows};coverage=[]
    for low in lows:
        row=mappings[low.name].uv_helper_topology(low,rigid)
        assert all(not row[key].flags.writeable for key in ('nativeVertexForOwner','triangleOwners','nativeLoopVertices'))
        raw=_field(low.data.loops,'vertex_index',1,np.int32).reshape((-1,3))
        count=_indexed_components(len(low.data.vertices),raw)
        owned=_indexed_components(len(row['nativeVertexForOwner']),row['triangleOwners'])
        if low.name=='core_LOW':assert count>owned==2 and len(low.data.vertices)>len(row['nativeVertexForOwner'])==285
        coverage.append({'name':low.name,'actualImportedRenderVertices':len(low.data.vertices),'renderComponents':count,
                         'authoredOwnerVertices':len(row['nativeVertexForOwner']),'ownerComponents':owned,'readonlyOwnerMap':True})
    class Forward:
        def __init__(self,target,**overrides):self.target=target;self.overrides=overrides
        def __getattr__(self,name):return self.overrides[name]if name in self.overrides else getattr(self.target,name)
    made=[];native_new=bpy.data.meshes.new
    def track_new(*args,**kwargs):made.append(args);return native_new(*args,**kwargs)
    proxy=Forward(bpy,data=Forward(bpy.data,meshes=Forward(bpy.data.meshes,new=track_new)))
    bad=[('missing',{}),('wrong-type',{name:object()for name in mappings}),
         ('wrong-node',{lows[0].name:mappings[lows[1].name],lows[1].name:mappings[lows[0].name]})]
    negatives=[]
    for label,value in bad:
        with patch.object(rigid,'bpy',proxy):
            try:rigid.pack_group(lows,job['recipe'],'RejectOwnerUV'+label,source_topology=value)
            except ValueError as error:reason=str(error)
            else:raise AssertionError('Invalid owner UV mapping accepted '+label)
        assert not made and before=={low.name:_snapshot(low)for low in lows}
        assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
        negatives.append({'case':label,'execution':'ACTUAL_NATIVE_BINDING_GUARDS','error':reason,'helperAllocations':0,'sourceAndCleanupExact':True})
    hit=[];smart=bpy.ops.uv.smart_project
    def interrupt(*args,**kwargs):
        assert smart(*args,**kwargs)=={'FINISHED'};hit.append(True)
        raise RuntimeError('TEST injected interruption after actual owner-connected SmartUV')
    interrupted=Forward(proxy,ops=Forward(bpy.ops,uv=Forward(bpy.ops.uv,smart_project=interrupt)))
    with patch.object(rigid,'bpy',interrupted):
        try:rigid.pack_group(lows,job['recipe'],'CancelledOwnerUV',source_topology=mappings)
        except RuntimeError as error:assert 'TEST injected interruption'in str(error)
        else:raise AssertionError('Injected owner helper interruption ignored')
    assert hit and len(made)==1 and before=={low.name:_snapshot(low)for low in lows}
    assert bpy.context.mode=='OBJECT'and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
    return {'status':'ACTUAL_OWNER_UV_PRECONDITIONS_PASS','coverage':coverage,'negativeMappings':negatives,
            'interruption':{'execution':'ACTUAL_SMART_UV_THEN_INJECTED_EXCEPTION','sourceAndOwnedCleanupExact':True},
            'authoredSmoothingChanged':False}


def observe_owner_uv_pack(original, lows, recipe, name, uv_atlas, source_topology, rigid):
    """Independently compare actual helper corners and actual runtime loop UVs."""
    import bpy, numpy as np
    assert type(source_topology)is dict and set(source_topology)=={low.name for low in lows}
    snapshots=[_snapshot(low)for low in lows];expected=[];faces=[];offset=0;counts=[]
    for low in lows:
        row=source_topology[low.name].uv_helper_topology(low,rigid)
        points=_field(low.data.vertices,'co',3,np.float32).reshape((-1,3)).astype(np.float64)
        frame=np.asarray(low.matrix_world,np.float64)
        world=(points@frame[:3,:3].T+frame[:3,3]).astype(np.float32)
        owner_points=world[row['nativeVertexForOwner']]
        assert owner_points[row['triangleOwners'].reshape(-1)].tobytes()==world[row['nativeLoopVertices']].tobytes()
        expected.append(world[row['nativeLoopVertices']]);faces.extend((row['triangleOwners']+offset).tolist())
        counts.append({'name':low.name,'renderVertices':len(points),'ownerVertices':len(owner_points),
                       'ownerComponents':_indexed_components(len(owner_points),row['triangleOwners'])})
        offset+=len(owner_points)
    result=original(lows,recipe,name,uv_atlas,source_topology=source_topology)
    helper=bpy.data.objects[result['target']]
    hp=_field(helper.data.vertices,'co',3,np.float32).reshape((-1,3));hl=_field(helper.data.loops,'vertex_index',1,np.int32)
    assert len(hp)==offset and hl.reshape((-1,3)).tolist()==faces
    assert hp[hl].tobytes()==np.concatenate(expected).tobytes()
    expected_uv=np.concatenate([_field(low.data.uv_layers.active.data,'uv',2,np.float32)for low in lows])
    assert expected_uv.tobytes()==_field(helper.data.uv_layers.active.data,'uv',2,np.float32).tobytes()
    assert all(_except_uv(old)==_except_uv(_snapshot(low))for old,low in zip(snapshots,lows))
    proof=result['sourceOwnerHelper']
    assert proof['exactWorldFloat32Corners']and proof['exactOriginalLoopScatter']and not proof['coordinateWeld']
    assert not proof['sourceSmoothingOrNormalSetter']
    assert _indexed_components(len(hp),hl.reshape((-1,3)))==sum(row['ownerComponents']for row in counts)
    core=next(row for row in counts if row['name'].startswith('core'))
    assert core['renderVertices']>core['ownerVertices']==285
    return result,{'execution':'ACTUAL_NATIVE_OWNER_CONNECTED_UV_HELPER','parts':counts,'helperVertices':len(hp),
        'helperComponents':sum(row['ownerComponents']for row in counts),'exactWorldCornerBitsAndLoopScatter':True,
        'actualRuntimeGeometryNormalsFlagsGraphMaterialsAndWorldExactExceptUv':True,'coordinateWeld':False}
