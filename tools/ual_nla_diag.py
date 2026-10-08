"""Diagnose UAL NLA vs Action evaluation."""
import bpy

bpy.ops.import_scene.gltf(
    filepath='C:/Users/inval/AppData/Local/Temp/opencode/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
for o in [o for o in bpy.data.objects if o.name != 'Mannequin' and o.type != 'ARMATURE']:
    bpy.data.objects.remove(o, do_unlink=True)
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
ad = rig.animation_data
print("USE_NLA:", ad.use_nla, "ACTION:", ad.action.name if ad.action else None)
print("TRACKS:", len(ad.nla_tracks))
for t in ad.nla_tracks[:5]:
    print(f"  track={t.name} mute={t.mute} strips={len(t.strips)}")
print("...")
muted = sum(1 for t in ad.nla_tracks if t.mute)
print(f"MUTED_COUNT: {muted}")


def sample(tag):
    print(f"--- {tag} ---")
    for f in (1, 30, 60, 90):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        hips = rig.matrix_world @ rig.pose.bones['DEF-hips'].matrix
        hand = rig.matrix_world @ rig.pose.bones['DEF-hand.R'].matrix
        print(f"f{f}: hips_z={hips.translation.z:.3f} handR={tuple(round(v,2) for v in hand.translation)}")


sample("AS_IMPORTED")
for t in ad.nla_tracks:
    t.mute = True
ad.action = bpy.data.actions.get('Fixing_Kneeling')
sample("NLA_MUTED+ACTION")
