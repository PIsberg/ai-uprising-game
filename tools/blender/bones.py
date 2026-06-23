import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--")+1:]
path, render = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
arm = next(o for o in bpy.data.objects if o.type=='ARMATURE')
print("##", os.path.basename(path))
for b in arm.data.bones:
    h = arm.matrix_world @ b.head_local
    print(f"  {b.name:14} ({h.x:.2f},{h.y:.2f},{h.z:.2f})")
mn=Vector((1e9,)*3); mx=Vector((-1e9,)*3)
for o in bpy.data.objects:
    if o.type=='MESH':
        for c in o.bound_box:
            w=o.matrix_world@Vector(c)
            for i in range(3): mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
print(f"  BOUNDS min=({mn.x:.2f},{mn.y:.2f},{mn.z:.2f}) max=({mx.x:.2f},{mx.y:.2f},{mx.z:.2f})")
ctr=(mn+mx)*0.5; rad=max((mx-mn))
cam_d=bpy.data.cameras.new("C"); cam=bpy.data.objects.new("C",cam_d); bpy.context.scene.collection.objects.link(cam)
cam.location=(ctr.x+rad*0.9, ctr.y-rad*2.4, ctr.z+rad*0.4)
tgt=bpy.data.objects.new("T",None); tgt.location=ctr; bpy.context.scene.collection.objects.link(tgt)
cam.constraints.new('TRACK_TO').target=tgt; bpy.context.scene.camera=cam
sd=bpy.data.lights.new("S",'SUN'); s=bpy.data.objects.new("S",sd); s.rotation_euler=(math.radians(55),0,math.radians(40)); sd.energy=4
bpy.context.scene.collection.objects.link(s)
sc=bpy.context.scene; sc.render.engine='BLENDER_WORKBENCH'; sc.render.resolution_x=600; sc.render.resolution_y=600; sc.render.filepath=render
bpy.ops.render.render(write_still=True)
print("R", render)
