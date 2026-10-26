# R15 animation exporter: writes the rig's active action as a Roblox KeyframeSequence (.rbxmx).
# Lives in R15_AnimRig.blend as a registered text block; the panel is in the 3D view sidebar (N) > "R15 Anim".
import bpy, json, os
from mathutils import Matrix

# Roblox space -> Blender space: x -> -x, y (up) -> z, z -> y. A proper rotation that is its own inverse,
# so the character faces -Y in Blender and its left side sits on +X (Blender's .L convention).
M = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

PRIORITIES = [
    ("Core", "Core", "Lowest; base locomotion", 1000),
    ("Idle", "Idle", "", 0),
    ("Movement", "Movement", "Walk, run, jump", 1),
    ("Action", "Action", "Attacks, emotes", 2),
    ("Action2", "Action2", "", 3),
    ("Action3", "Action3", "", 4),
    ("Action4", "Action4", "", 5),
]


def find_rig(context):
    ob = context.active_object
    if ob and ob.type == 'ARMATURE' and "r15_rest" in ob:
        return ob
    return next((o for o in bpy.data.objects if o.type == 'ARMATURE' and "r15_rest" in o), None)


def _orthonormal(m):
    out = m.to_quaternion().to_matrix().to_4x4()
    out.translation = m.translation
    return out


def sample_pose(rig, rest):
    """Motor6D.Transform for every joint at the current frame, in Roblox space."""
    world = {}
    for part, bone_name in rest["bones"].items():
        pb = rig.pose.bones[bone_name]
        posed = rig.matrix_world @ pb.matrix
        base = rig.matrix_world @ pb.bone.matrix_local
        delta = M @ (posed @ base.inverted()) @ M
        world[part] = _orthonormal(delta @ Matrix(rest["parts"][part]))
    transforms = {}
    for motor in rest["motors"]:
        c0 = Matrix.Translation(motor["c0"])
        c1 = Matrix.Translation(motor["c1"])
        transforms[motor["part1"]] = (world[motor["part0"]] @ c0).inverted() @ world[motor["part1"]] @ c1
    return transforms


def _cframe(m):
    t = m.translation
    vals = [("X", t.x), ("Y", t.y), ("Z", t.z)]
    for r in range(3):
        for c in range(3):
            vals.append(("R%d%d" % (r, c), m[r][c]))
    return "".join("<%s>%.6g</%s>" % (k, 0 if abs(v) < 1e-7 else v, k) for k, v in vals)


class _Writer:
    def __init__(self):
        self.lines, self.ref = [], 0

    def open(self, cls, props):
        self.ref += 1
        self.lines.append('<Item class="%s" referent="RBX%d"><Properties>%s</Properties>' % (cls, self.ref, props))

    def close(self):
        self.lines.append("</Item>")


def write_sequence(path, name, frames, rest, loop, priority):
    children = {}
    for motor in rest["motors"]:
        children.setdefault(motor["part0"], []).append(motor["part1"])
    identity = Matrix.Identity(4)
    w = _Writer()
    w.lines.append('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                   'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    w.open("KeyframeSequence", '<string name="Name">%s</string><bool name="Loop">%s</bool><token name="Priority">%d</token>'
           '<float name="AuthoredHipHeight">%.4f</float>' % (name, "true" if loop else "false", priority, rest["hipHeight"]))

    def pose(part, transforms):
        props = ('<string name="Name">%s</string><CoordinateFrame name="CFrame">%s</CoordinateFrame>'
                 '<float name="Weight">1</float><token name="EasingStyle">0</token><token name="EasingDirection">0</token>'
                 % (part, _cframe(transforms.get(part, identity))))
        w.open("Pose", props)
        for child in children.get(part, []):
            pose(child, transforms)
        w.close()

    for time, transforms in frames:
        w.open("Keyframe", '<string name="Name">Keyframe</string><float name="Time">%.5f</float>' % time)
        pose("HumanoidRootPart", transforms)
        w.close()
    w.close()
    w.lines.append("</roblox>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(w.lines))


def export_action(context, rig, folder, loop, priority, step):
    scene = context.scene
    rest = json.loads(rig["r15_rest"])
    action = rig.animation_data.action if rig.animation_data else None
    name = action.name if action else "Animation"
    if action and action.use_frame_range:
        start, end = int(action.frame_range[0]), int(action.frame_range[1])
    else:
        start, end = scene.frame_start, scene.frame_end
    fps = scene.render.fps / scene.render.fps_base
    current = scene.frame_current
    frames = []
    for f in list(range(start, end + 1, step)) + ([end] if (end - start) % step else []):
        scene.frame_set(f)
        frames.append(((f - start) / fps, sample_pose(rig, rest)))
    scene.frame_set(current)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name + ".rbxmx")
    write_sequence(path, name, frames, rest, loop, priority)
    return path, len(frames)


class R15ExportSettings(bpy.types.PropertyGroup):
    loop: bpy.props.BoolProperty(name="Loop", default=True)
    priority: bpy.props.EnumProperty(name="Priority", items=PRIORITIES, default="Movement")
    folder: bpy.props.StringProperty(name="Folder", subtype='DIR_PATH', default="//exports/")
    step: bpy.props.IntProperty(name="Every Nth frame", default=1, min=1, max=10,
                                description="Sample every Nth frame; Roblox interpolates linearly between them")


class R15_OT_export(bpy.types.Operator):
    bl_idname = "r15.export_keyframes"
    bl_label = "Export to Roblox (.rbxmx)"
    bl_description = "Bake the rig's active action into a Roblox KeyframeSequence file"

    def execute(self, context):
        rig = find_rig(context)
        if not rig:
            self.report({'ERROR'}, "No R15 rig found (an armature with r15_rest data)")
            return {'CANCELLED'}
        s = context.scene.r15_export
        priority = next(p[3] for p in PRIORITIES if p[0] == s.priority)
        path, count = export_action(context, rig, bpy.path.abspath(s.folder), s.loop, priority, s.step)
        self.report({'INFO'}, "Wrote %d keyframes to %s" % (count, path))
        return {'FINISHED'}


class R15_PT_export(bpy.types.Panel):
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "R15 Anim"
    bl_label = "Roblox R15 Export"

    def draw(self, context):
        s = context.scene.r15_export
        col = self.layout.column()
        col.prop(s, "loop")
        col.prop(s, "priority")
        col.prop(s, "step")
        col.prop(s, "folder")
        col.operator("r15.export_keyframes", icon='EXPORT')
        rig = find_rig(context)
        if rig and rig.animation_data and rig.animation_data.action:
            col.label(text="Action: " + rig.animation_data.action.name)


CLASSES = (R15ExportSettings, R15_OT_export, R15_PT_export)


def register():
    for cls in CLASSES:
        if hasattr(bpy.types, cls.__name__):
            bpy.utils.unregister_class(getattr(bpy.types, cls.__name__))
        bpy.utils.register_class(cls)
    bpy.types.Scene.r15_export = bpy.props.PointerProperty(type=R15ExportSettings)


register()
