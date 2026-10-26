# Builds R15_AnimRig.blend headless from r15_rig.json (the default R15 rig pulled out of Roblox Studio).
# Run: blender --background --factory-startup --python build_r15_rig.py
import bpy, bmesh, json, math, os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, "r15_rig.json"), encoding="utf-8"))
OUT = os.path.join(HERE, "R15_AnimRig.blend")
M = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox -> Blender, self-inverse

# (motor, part0, part1) in parent-before-child order
MOTORS = [
    ("Root", "HumanoidRootPart", "LowerTorso"),
    ("Waist", "LowerTorso", "UpperTorso"),
    ("Neck", "UpperTorso", "Head"),
    ("LeftShoulder", "UpperTorso", "LeftUpperArm"),
    ("LeftElbow", "LeftUpperArm", "LeftLowerArm"),
    ("LeftWrist", "LeftLowerArm", "LeftHand"),
    ("RightShoulder", "UpperTorso", "RightUpperArm"),
    ("RightElbow", "RightUpperArm", "RightLowerArm"),
    ("RightWrist", "RightLowerArm", "RightHand"),
    ("LeftHip", "LowerTorso", "LeftUpperLeg"),
    ("LeftKnee", "LeftUpperLeg", "LeftLowerLeg"),
    ("LeftAnkle", "LeftLowerLeg", "LeftFoot"),
    ("RightHip", "LowerTorso", "RightUpperLeg"),
    ("RightKnee", "RightUpperLeg", "RightLowerLeg"),
    ("RightAnkle", "RightLowerLeg", "RightFoot"),
]


def bone_name(part):
    """Blender-friendly names with .L/.R so pose flipping and symmetry work."""
    for side, suffix in (("Left", ".L"), ("Right", ".R")):
        if part.startswith(side):
            return part[len(side):] + suffix
    return part


# --- rest pose in Roblox space -------------------------------------------------
att = {k: Vector(v) for k, v in DATA["attachments"].items()}
motors = []
rest = {"HumanoidRootPart": Matrix.Translation((0, DATA["hipHeight"] + DATA["parts"]["HumanoidRootPart"]["size"][1] / 2, 0))}
for motor, p0, p1 in MOTORS:
    c0 = att["%s.%sRigAttachment" % (p0, motor)]
    c1 = att["%s.%sRigAttachment" % (p1, motor)]
    rest[p1] = rest[p0] @ Matrix.Translation(c0) @ Matrix.Translation(-c1)
    motors.append({"name": motor, "part0": p0, "part1": p1, "c0": list(c0), "c1": list(c1)})

# drop everything so the feet rest on y = 0
foot_bottom = min(rest[f].translation.y - DATA["parts"][f]["size"][1] / 2 for f in ("LeftFoot", "RightFoot"))
shift = Matrix.Translation((0, -foot_bottom, 0))
for k in rest:
    rest[k] = shift @ rest[k]


def joint_world(motor_name):
    """World position (Blender space) of a motor's joint at rest."""
    for motor, p0, p1 in MOTORS:
        if motor == motor_name:
            return (M @ rest[p1] @ Matrix.Translation(att["%s.%sRigAttachment" % (p1, motor)])).translation
    raise KeyError(motor_name)


def part_center(part):
    return (M @ rest[part]).translation


# --- scene ---------------------------------------------------------------------
bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, 30
scene.unit_settings.system = 'NONE'

coll_body = bpy.data.collections.new("R15_Body")
coll_wgt = bpy.data.collections.new("R15_Widgets")
scene.collection.children.link(coll_body)
scene.collection.children.link(coll_wgt)

arm_data = bpy.data.armatures.new("R15_Rig")
arm_data.display_type = 'OCTAHEDRAL'
rig = bpy.data.objects.new("R15_Rig", arm_data)
scene.collection.objects.link(rig)
rig.show_in_front = True
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones

UP, FWD = Vector((0, 0, 1)), Vector((0, -1, 0))


def add_bone(name, head, tail, parent=None, deform=True, connect=False):
    b = eb.new(name)
    b.head, b.tail = Vector(head), Vector(tail)
    b.roll = 0
    b.use_deform = deform
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


add_bone("root", (0, 0, 0), (0, 1.5, 0), deform=False)
hrp_c = part_center("HumanoidRootPart")
add_bone("HumanoidRootPart", hrp_c, hrp_c + UP * 0.6, "root")
add_bone("LowerTorso", joint_world("Root"), joint_world("Waist"), "HumanoidRootPart")
add_bone("UpperTorso", joint_world("Waist"), joint_world("Neck"), "LowerTorso", connect=True)
add_bone("Head", joint_world("Neck"), joint_world("Neck") + UP * 1.2, "UpperTorso", connect=True)
for side in ("Left", "Right"):
    s = ".L" if side == "Left" else ".R"
    add_bone("UpperArm" + s, joint_world(side + "Shoulder"), joint_world(side + "Elbow"), "UpperTorso")
    add_bone("LowerArm" + s, joint_world(side + "Elbow"), joint_world(side + "Wrist"), "UpperArm" + s, connect=True)
    add_bone("Hand" + s, joint_world(side + "Wrist"), joint_world(side + "Wrist") - UP * 0.45, "LowerArm" + s, connect=True)
    add_bone("UpperLeg" + s, joint_world(side + "Hip"), joint_world(side + "Knee"), "LowerTorso")
    add_bone("LowerLeg" + s, joint_world(side + "Knee"), joint_world(side + "Ankle"), "UpperLeg" + s, connect=True)
    ankle = joint_world(side + "Ankle")
    add_bone("Foot" + s, ankle, ankle + FWD * 0.6, "LowerLeg" + s, connect=True)
    # controls: IK targets sit where the hand/foot bones are, poles in front of knees and behind elbows
    add_bone("IK_Foot" + s, ankle, ankle + FWD * 0.6, "root", deform=False)
    knee = joint_world(side + "Knee")
    add_bone("Pole_Knee" + s, knee + FWD * 2.5, knee + FWD * 2.5 + UP * 0.3, "IK_Foot" + s, deform=False)
    wrist = joint_world(side + "Wrist")
    add_bone("IK_Hand" + s, wrist, wrist - UP * 0.45, "root", deform=False)
    elbow = joint_world(side + "Elbow")
    add_bone("Pole_Elbow" + s, elbow - FWD * 2.5, elbow - FWD * 2.5 + UP * 0.3, "root", deform=False)

# make the knees bend forward and the elbows bend back: nudge the middle joints off the straight line
for s in (".L", ".R"):
    eb["UpperLeg" + s].tail += FWD * 0.02
    eb["UpperArm" + s].tail -= FWD * 0.02
bpy.ops.object.mode_set(mode='POSE')

# --- constraints -----------------------------------------------------------------
pose = rig.pose.bones
for s in (".L", ".R"):
    ik = pose["LowerLeg" + s].constraints.new('IK')
    ik.target, ik.subtarget = rig, "IK_Foot" + s
    ik.pole_target, ik.pole_subtarget = rig, "Pole_Knee" + s
    ik.pole_angle = math.radians(-90)
    ik.chain_count = 2
    cr = pose["Foot" + s].constraints.new('COPY_ROTATION')
    cr.target, cr.subtarget = rig, "IK_Foot" + s
    # arms start in FK; raise these two influences to 1 to drive an arm by IK_Hand
    ik = pose["LowerArm" + s].constraints.new('IK')
    ik.name = "Arm IK"
    ik.target, ik.subtarget = rig, "IK_Hand" + s
    ik.pole_target, ik.pole_subtarget = rig, "Pole_Elbow" + s
    ik.pole_angle = math.radians(-90)
    ik.chain_count = 2
    ik.influence = 0
    cr = pose["Hand" + s].constraints.new('COPY_ROTATION')
    cr.name = "Arm IK rot"
    cr.target, cr.subtarget = rig, "IK_Hand" + s
    cr.influence = 0

for pb in pose:
    pb.rotation_mode = 'QUATERNION'
pose["HumanoidRootPart"].lock_location = (True, True, True)
pose["HumanoidRootPart"].lock_rotation = (True, True, True)
pose["HumanoidRootPart"].lock_rotation_w = True

# --- control shapes ------------------------------------------------------------
def widget(name, verts, edges):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, edges, [])
    ob = bpy.data.objects.new(name, me)
    coll_wgt.objects.link(ob)
    return ob


def circle(n=24, r=1.0):
    v = [(r * math.cos(2 * math.pi * i / n), 0, r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return v, [(i, (i + 1) % n) for i in range(n)]


def square(w, d):
    v = [(-w, 0, -d), (w, 0, -d), (w, 0, d), (-w, 0, d)]
    return v, [(0, 1), (1, 2), (2, 3), (3, 0)]


def diamond(r):
    v = [(r, 0, 0), (-r, 0, 0), (0, r, 0), (0, -r, 0), (0, 0, r), (0, 0, -r)]
    return v, [(0, 2), (2, 1), (1, 3), (3, 0), (0, 4), (4, 1), (1, 5), (5, 0), (2, 4), (4, 3), (3, 5), (5, 2)]


w_root = widget("WGT_root", *circle(32, 1.0))
w_ring = widget("WGT_ring", *circle(24, 1.0))
w_foot = widget("WGT_foot", *square(0.45, 0.5))
w_pole = widget("WGT_pole", *diamond(0.25))
coll_wgt.hide_viewport = True
coll_wgt.hide_render = True

pose["root"].custom_shape = w_root
pose["root"].custom_shape_scale_xyz = (2.2, 2.2, 2.2)
pose["LowerTorso"].custom_shape = w_ring
pose["LowerTorso"].custom_shape_scale_xyz = (3.4, 3.4, 3.4)
for s in (".L", ".R"):
    pose["IK_Foot" + s].custom_shape = w_foot
    pose["IK_Hand" + s].custom_shape = w_ring
    pose["IK_Hand" + s].custom_shape_scale_xyz = (0.9, 0.9, 0.9)
    pose["Pole_Knee" + s].custom_shape = w_pole
    pose["Pole_Elbow" + s].custom_shape = w_pole

# colour groups: controls yellow, left side blue, right side red
for pb in pose:
    if not pb.bone.use_deform:
        pb.color.palette = 'THEME09'
    elif pb.name.endswith(".L"):
        pb.color.palette = 'THEME04'
    elif pb.name.endswith(".R"):
        pb.color.palette = 'THEME01'

# --- body meshes ------------------------------------------------------------------
def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    if mat.node_tree:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    return mat


MAT = {
    "mid": material("Body_Mid", (0.62, 0.62, 0.64)),
    "L": material("Body_Left", (0.42, 0.55, 0.78)),
    "R": material("Body_Right", (0.78, 0.45, 0.42)),
    "head": material("Body_Head", (0.85, 0.78, 0.62)),
}

tail_offset = {}
for b in arm_data.bones:
    tail_offset[b.name] = b.matrix_local @ Matrix.Translation((0, b.length, 0))

for part, info in DATA["parts"].items():
    if part == "HumanoidRootPart":
        continue
    world = M @ rest[part]  # Roblox part-local point -> Blender world
    me = bpy.data.meshes.new("Mesh_" + part)
    if info.get("verts"):
        verts = [world @ Vector(v) for v in info["verts"]]
        me.from_pydata(verts, [], [tuple(f) for f in info["faces"]])
    else:
        # the head mesh can't be loaded from Roblox, so use a rounded block of the same size
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        sx, sy, sz = info["size"]
        bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=0.22, segments=4, affect='EDGES')
        bmesh.ops.translate(bm, vec=world.translation, verts=bm.verts)
        bm.to_mesh(me)
        bm.free()
    me.update()
    ob = bpy.data.objects.new("Mesh_" + part, me)
    coll_body.objects.link(ob)
    side = "L" if part.startswith("Left") else "R" if part.startswith("Right") else ("head" if part == "Head" else "mid")
    me.materials.append(MAT[side])
    for poly in me.polygons:
        poly.use_smooth = False
    bn = bone_name(part)
    ob.parent, ob.parent_type, ob.parent_bone = rig, 'BONE', bn
    ob.matrix_parent_inverse = (rig.matrix_world @ tail_offset[bn]).inverted()
    ob.hide_select = True

# --- data the exporter needs ----------------------------------------------------------
rig["r15_rest"] = json.dumps({
    "hipHeight": DATA["hipHeight"],
    "parts": {k: [list(row) for row in v] for k, v in rest.items()},
    "motors": motors,
    "bones": {part: bone_name(part) for part in rest},
})

# --- exporter and a starter action -------------------------------------------------------
text = bpy.data.texts.new("r15_export.py")
text.from_string(open(os.path.join(HERE, "r15_export.py"), encoding="utf-8").read())
text.use_module = True
exec(compile(text.as_string(), "r15_export.py", "exec"), {"__name__": "r15_export"})

rig.animation_data_create()
rig.animation_data.action = bpy.data.actions.new("NewAnim")
scene.r15_export.folder = "//exports/"
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("R15RIG_JSON " + json.dumps({"bones": len(arm_data.bones), "meshes": len(coll_body.objects), "out": OUT,
                                    "foot_shift": round(-foot_bottom, 4)}))
