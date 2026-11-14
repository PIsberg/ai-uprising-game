"""Primitive kit for the robot models this game builds itself (build_reaper.py,
build_gunslinger.py): flat materials, bevelled boxes, cylinders, beams and rods
collected into named groups, then joined into one mesh per group, recentred so
RobotModel's fit is a scale of 1 and no shift, exported and previewed.

Blender axes: +Y is the front (Godot -Z after export), Z up, metres. After
`centre()`, a Blender point (x, y, z) is the Godot body-frame point (x, z, -y).
"""
import bpy, os, math
from mathutils import Vector, Matrix


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, col, metal=0.8, rough=0.45, emis=None, ee=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emis:
        b.inputs['Emission Color'].default_value = (emis[0], emis[1], emis[2], 1)
        b.inputs['Emission Strength'].default_value = ee
    m.diffuse_color = (col[0], col[1], col[2], 1)  # workbench preview colour
    return m


def _finish(o, m, group, bevel):
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0.0:
        mod = o.modifiers.new("b", 'BEVEL')
        mod.width = bevel; mod.segments = 2; mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(40)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(m)
    group.append(o)
    return o


def box(group, loc, size, m, rot=(0, 0, 0), bevel=0.012):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = size
    o.rotation_euler = [math.radians(a) for a in rot]
    return _finish(o, m, group, bevel)


def cyl(group, loc, r, depth, m, axis='Z', verts=14, r2=None, bevel=0.0, rot=None):
    """A cylinder (or a cone frustum when r2 is given: r at the -axis end, r2 at the + end)."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, vertices=verts)
    o = bpy.context.active_object
    if rot is not None:
        o.rotation_euler = [math.radians(a) for a in rot]
    elif axis == 'Y':
        o.rotation_euler = (math.radians(-90), 0, 0)   # +Z end -> +Y
    elif axis == 'X':
        o.rotation_euler = (0, math.radians(90), 0)    # +Z end -> +X
    return _finish(o, m, group, bevel)


def ball(group, loc, r, m, segs=12, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=segs, ring_count=max(6, segs // 2))
    o = bpy.context.active_object
    o.scale = scale
    return _finish(o, m, group, 0.0)


def beam(group, p0, p1, w, h, m, bevel=0.012):
    """A box running from p0 to p1, w wide (x-ish) and h deep."""
    p0 = Vector(p0); p1 = Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(p0 + p1) * 0.5)
    o = bpy.context.active_object
    o.scale = (w, d.length, h)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Y', 'Z')
    return _finish(o, m, group, bevel)


def rod(group, p0, p1, r, m, verts=8, r2=None):
    p0 = Vector(p0); p1 = Vector(p1)
    d = p1 - p0
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(p0 + p1) * 0.5, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=d.length, location=(p0 + p1) * 0.5, vertices=verts)
    o = bpy.context.active_object
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    return _finish(o, m, group, 0.0)


def join(parts, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name; o.data.name = name
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    except Exception as e:  # older Blender: leave it flat
        print("shade_smooth_by_angle unavailable:", e)
    return o


def bounds(objs):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return mn, mx


def centre(objs, height):
    """Shift every mesh so the model's box is centred on x and y with its feet at
    z = 0, then scale it (by at most 3 %) to stand exactly `height` tall:
    RobotModel's fit (fit_height = `height`) is then a scale of 1 and no shift, so
    body-frame numbers measured here are the ones the game sees. Returns the
    transform applied, for points the script placed by hand."""
    for o in objs:  # bake each object's placement into its mesh, so the scale is about the world origin
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    mn, mx = bounds(objs)
    shift = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    s = height / (mx.z - mn.z)
    assert abs(s - 1.0) < 0.03, "built %.3f m tall, too far from %.2f m" % (mx.z - mn.z, height)
    m = Matrix.Scale(s, 4) @ Matrix.Translation(shift)
    for o in objs:
        o.data.transform(m)
        o.data.update()
    mn, mx = bounds(objs)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print("BOUNDS min %s max %s  tris %d  shift %s scale %.4f" % (
        tuple(round(c, 3) for c in mn), tuple(round(c, 3) for c in mx), tris, tuple(round(c, 3) for c in shift), s))
    assert abs(mx.z - height) < 1e-3 and abs(mn.z) < 1e-3
    assert abs(mn.x + mx.x) < 1e-3 and abs(mn.y + mx.y) < 1e-3
    return m


def godot(v):
    """A Blender point as the Godot body-frame point."""
    return Vector((v.x, v.z, -v.y))


def top_band(o, band=0.02):
    """The mean of a part's vertices within `band` of its highest point, Godot frame."""
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    top = max(w.z for w in ws)
    sel = [w for w in ws if w.z > top - band]
    return godot(sum(sel, Vector()) / len(sel))


def export(objs, out):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True)
    print("EXPORTED", out, os.path.getsize(out), "bytes")


VIEWS = [(1.1, 1.5, 0.3), (-1.4, 0.9, 0.2), (0.0, 1.9, 0.1), (1.9, 0.0, 0.15), (-0.9, -1.5, 0.5)]


def previews(objs, paths):
    mn, mx = bounds(objs)
    ctr = (mn + mx) * 0.5; rad = max((mx - mn).x, (mx - mn).y, (mx - mn).z) * 1.25
    t = bpy.data.objects.new("T", None); t.location = ctr
    bpy.context.scene.collection.objects.link(t)
    cam_d = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    cam.constraints.new('TRACK_TO').target = t
    bpy.context.scene.camera = cam
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = True
    sc.render.resolution_x = 700; sc.render.resolution_y = 700
    for i, path in enumerate(paths):
        v = VIEWS[i % len(VIEWS)]
        cam.location = (ctr.x + rad * v[0], ctr.y + rad * v[1], ctr.z + rad * v[2])
        sc.render.filepath = os.path.abspath(path)
        bpy.ops.render.render(write_still=True)
        print("RENDERED", path)
