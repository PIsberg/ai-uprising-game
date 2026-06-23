import bpy, sys, mathutils
from mathutils import Vector
a = sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
want = {"Head","Shoulder.L","Shoulder.R","Torso","Arm.L","Arm.R"}
for o in bpy.data.objects:
    if o.type=='MESH' and o.name in want:
        mn=Vector((1e9,)*3); mx=Vector((-1e9,)*3)
        for c in o.bound_box:
            w=o.matrix_world@Vector(c)
            for i in range(3): mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
        ctr=(mn+mx)*0.5
        print(f"{o.name:12} ctr=({ctr.x:.2f},{ctr.y:.2f},{ctr.z:.2f}) "
              f"min=({mn.x:.2f},{mn.y:.2f},{mn.z:.2f}) max=({mx.x:.2f},{mx.y:.2f},{mx.z:.2f})")
