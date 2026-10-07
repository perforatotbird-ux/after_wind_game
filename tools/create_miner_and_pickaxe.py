"""
Blender 5.2 Automation Script
Creates:
1. Pickaxe 3D model (GLB, Blend, 2D Icon)
2. Miner 3D character model (GLB, Blend, 2D Portrait, 2D Isometric Sprite)
3. Rigged skeleton with 4 baked animations: idle, walk, run, mine
Matches concept art from:
- assets/concept art/miner.jpg
- assets/concept art/instruments/pickaxe.jpg
- Design Document.txt Sections 41, 42, 51, 79
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix, Euler, Quaternion

# Configure Output Paths
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODELS_CHAR_DIR = os.path.join(BASE_DIR, "assets", "models", "character")
MODELS_TOOL_DIR = os.path.join(BASE_DIR, "assets", "models", "tools")
SPRITES_DIR = os.path.join(BASE_DIR, "assets", "sprites")
TOOLS_SPRITES_DIR = os.path.join(BASE_DIR, "assets", "tools")

for d in [MODELS_CHAR_DIR, MODELS_TOOL_DIR, SPRITES_DIR, TOOLS_SPRITES_DIR]:
    os.makedirs(d, exist_ok=True)

PICKAXE_GLB = os.path.join(MODELS_TOOL_DIR, "pickaxe.glb")
PICKAXE_BLEND = os.path.join(MODELS_TOOL_DIR, "pickaxe.blend")
PICKAXE_ICON = os.path.join(TOOLS_SPRITES_DIR, "pickaxe_icon.png")

MINER_GLB = os.path.join(MODELS_CHAR_DIR, "miner.glb")
MINER_BLEND = os.path.join(MODELS_CHAR_DIR, "miner.blend")
MINER_PORTRAIT = os.path.join(SPRITES_DIR, "miner_portrait.png")
MINER_SPRITE = os.path.join(SPRITES_DIR, "miner_isometric.png")

def reset_scene():
    """Clear all objects, meshes, materials, armatures from scene."""
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    for collection in [bpy.data.meshes, bpy.data.materials, bpy.data.armatures, 
                       bpy.data.actions, bpy.data.cameras, bpy.data.lights, bpy.data.images]:
        for block in collection:
            collection.remove(block, do_unlink=True)

def create_pbr_material(name, base_color, metallic=0.0, roughness=0.5, emission=None, emission_strength=1.0):
    """Creates a Principled BSDF material with specified physical parameters."""
    mat = bpy.data.materials.new(name=name)
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    out_node = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    
    bsdf.inputs['Base Color'].default_value = base_color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    
    if emission:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission
            bsdf.inputs['Emission Strength'].default_value = emission_strength
        elif 'Emission' in bsdf.inputs:
            bsdf.inputs['Emission'].default_value = emission
            if 'Emission Strength' in bsdf.inputs:
                bsdf.inputs['Emission Strength'].default_value = emission_strength
                
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out_node.inputs['Surface'])
    return mat

# ==============================================================================
# 1. BUILD PICKAXE MODEL
# ==============================================================================

def build_pickaxe_mesh(centered=False):
    """
    Builds a high quality game-ready pickaxe with hardwood handle, collar, rivets, and forged double head.
    If centered=True, centers origin in middle of tool (ideal for standalone asset & icon rendering).
    If centered=False, keeps handle grip at origin (ideal for character socket attachment).
    """
    mat_wood = create_pbr_material("M_Hardwood", (0.34, 0.20, 0.10, 1.0), metallic=0.0, roughness=0.65)
    mat_metal = create_pbr_material("M_ForgedIron", (0.22, 0.24, 0.26, 1.0), metallic=0.92, roughness=0.34)
    mat_steel = create_pbr_material("M_PolishedSteel", (0.65, 0.68, 0.72, 1.0), metallic=0.96, roughness=0.20)
    mat_leather = create_pbr_material("M_LeatherGrip", (0.22, 0.14, 0.08, 1.0), metallic=0.0, roughness=0.85)
    mat_brass = create_pbr_material("M_BrassRivet", (0.82, 0.66, 0.24, 1.0), metallic=0.90, roughness=0.30)

    parts = []

    # 1. Ergonomic Handle: length 0.85m
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.024, depth=0.85, location=(0, 0, 0.425))
    handle = bpy.context.active_object
    handle.name = "Pickaxe_Handle"
    handle.data.materials.append(mat_wood)
    
    bm = bmesh.new()
    bm.from_mesh(handle.data)
    for v in bm.verts:
        t = v.co.z / 0.85
        v.co.x *= 0.85 # Oval cross-section
        if t < 0.18:
            # Flare at pommel base
            f = 1.0 + (0.18 - t) * 2.0
            v.co.x *= f
            v.co.y *= f
        elif t > 0.75:
            # Flare towards head
            f = 1.0 + (t - 0.75) * 0.9
            v.co.x *= f
            v.co.y *= f
    bm.to_mesh(handle.data)
    bm.free()
    parts.append(handle)

    # 2. Leather grip wrap
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.028, depth=0.18, location=(0, 0, 0.68))
    grip = bpy.context.active_object
    grip.name = "Pickaxe_Grip"
    grip.data.materials.append(mat_leather)
    parts.append(grip)

    # 3. Forged iron collar
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.035, depth=0.10, location=(0, 0, 0.81))
    collar = bpy.context.active_object
    collar.name = "Pickaxe_Collar"
    collar.data.materials.append(mat_metal)
    parts.append(collar)

    # 4. Brass rivets
    for y_sign in [-1, 1]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.008, location=(0, y_sign * 0.035, 0.81))
        rivet = bpy.context.active_object
        rivet.name = f"Pickaxe_Rivet_{y_sign}"
        rivet.data.materials.append(mat_brass)
        parts.append(rivet)

    # 5. Forged Double-sided Head
    mesh_head = bpy.data.meshes.new("Pickaxe_Head_Mesh")
    head_obj = bpy.data.objects.new("Pickaxe_Head", mesh_head)
    bpy.context.collection.objects.link(head_obj)
    head_obj.data.materials.append(mat_metal)
    head_obj.data.materials.append(mat_steel)

    bm = bmesh.new()
    
    # Eye cube
    eye_box = bmesh.ops.create_cube(bm, size=0.075)
    for v in eye_box['verts']:
        v.co.z = (v.co.z * 1.3) + 0.84
        v.co.x *= 0.92
        v.co.y *= 1.25

    # Sharp pointed pick arm (-Y)
    steps = 6
    arch_length = 0.25
    pick_rings = []
    for i in range(steps + 1):
        t = i / steps
        y = -0.045 - (t * arch_length)
        z = 0.84 - (t * t * 0.07)
        r = 0.028 * (1.0 - t * 0.92) + 0.003
        ring = []
        for a_idx in range(6):
            ang = a_idx * (2.0 * math.pi / 6.0)
            vx = math.cos(ang) * r * 0.8
            vz = math.sin(ang) * r
            v = bm.verts.new((vx, y, z + vz))
            ring.append(v)
        pick_rings.append(ring)
    
    for i in range(len(pick_rings) - 1):
        r1, r2 = pick_rings[i], pick_rings[i + 1]
        for j in range(6):
            j_next = (j + 1) % 6
            bm.faces.new([r1[j], r1[j_next], r2[j_next], r2[j]])
    
    tip_v = bm.verts.new((0.0, -0.045 - arch_length - 0.015, 0.84 - 0.08))
    for j in range(6):
        j_next = (j + 1) % 6
        bm.faces.new([pick_rings[-1][j], pick_rings[-1][j_next], tip_v])

    # Chisel blade arm (+Y)
    chisel_rings = []
    chisel_steps = 5
    for i in range(chisel_steps + 1):
        t = i / chisel_steps
        y = 0.045 + (t * 0.22)
        z = 0.84 - (t * t * 0.05)
        rx = 0.026 * (1.0 - t * 0.25) + 0.026 * t
        rz = 0.026 * (1.0 - t * 0.85)
        ring = []
        for a_idx in range(4):
            ang = a_idx * (math.pi / 2.0) + (math.pi / 4.0)
            vx = math.cos(ang) * rx
            vz = math.sin(ang) * rz
            v = bm.verts.new((vx, y, z + vz))
            ring.append(v)
        chisel_rings.append(ring)

    for i in range(len(chisel_rings) - 1):
        r1, r2 = chisel_rings[i], chisel_rings[i + 1]
        for j in range(4):
            j_next = (j + 1) % 4
            f = bm.faces.new([r1[j], r1[j_next], r2[j_next], r2[j]])
            if i == len(chisel_rings) - 2:
                f.material_index = 1

    f_end = bm.faces.new(chisel_rings[-1])
    f_end.material_index = 1

    bm.to_mesh(mesh_head)
    bm.free()
    parts.append(head_obj)

    # 6. Wooden Wedge at handle top
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.018, depth=0.04, location=(0, 0, 0.875))
    top_wood = bpy.context.active_object
    top_wood.name = "Pickaxe_TopWood"
    top_wood.data.materials.append(mat_wood)
    parts.append(top_wood)

    # Join
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = handle
    bpy.ops.object.join()
    
    pickaxe = bpy.context.active_object
    pickaxe.name = "Pickaxe"
    bpy.ops.object.shade_smooth()

    if centered:
        # Center origin at middle of pickaxe (around z=0.45)
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        pickaxe.location = Vector((0, 0, 0))
    else:
        # Move grip point (around z=0.35) to origin (0,0,0)
        bm = bmesh.new()
        bm.from_mesh(pickaxe.data)
        for v in bm.verts:
            v.co.z -= 0.35
        bm.to_mesh(pickaxe.data)
        bm.free()

    return pickaxe

def render_tool_icon(target_path):
    """Sets up studio lighting, isometric camera and renders a crisp 512x512 transparent PNG."""
    cam_data = bpy.data.cameras.new("IconCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 1.15
    cam_obj = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    
    cam_obj.location = Vector((1.0, -1.0, 0.9))
    cam_obj.rotation_euler = Euler((math.radians(55.0), 0.0, math.radians(45.0)), 'XYZ')
    bpy.context.scene.camera = cam_obj

    # Studio 3-Point Lighting
    key_data = bpy.data.lights.new("IconKey", type='SUN')
    key_data.energy = 4.5
    key_data.color = (1.0, 0.96, 0.90)
    key_obj = bpy.data.objects.new("IconKey", key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.rotation_euler = Euler((math.radians(45), math.radians(25), math.radians(-30)), 'XYZ')

    fill_data = bpy.data.lights.new("IconFill", type='SUN')
    fill_data.energy = 2.2
    fill_data.color = (0.75, 0.85, 1.0)
    fill_obj = bpy.data.objects.new("IconFill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = Euler((math.radians(-30), math.radians(-45), math.radians(120)), 'XYZ')

    rim_data = bpy.data.lights.new("IconRim", type='SUN')
    rim_data.energy = 3.0
    rim_obj = bpy.data.objects.new("IconRim", rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.rotation_euler = Euler((math.radians(-60), math.radians(20), math.radians(200)), 'XYZ')

    scene = bpy.context.scene
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = target_path

    # Rotate pickaxe diagonally for heroic icon angle
    pickaxe = bpy.data.objects.get("Pickaxe")
    if pickaxe:
        pickaxe.location = Vector((0.0, 0.0, 0.0))
        pickaxe.rotation_euler = Euler((math.radians(25), math.radians(-35), math.radians(15)), 'XYZ')

    bpy.ops.render.render(write_still=True)
    print(f"Rendered pickaxe icon to: {target_path}")

    if pickaxe:
        pickaxe.rotation_euler = Euler((0, 0, 0), 'XYZ')
        pickaxe.location = Vector((0, 0, 0))

# ==============================================================================
# 2. BUILD MINER CHARACTER MODEL
# ==============================================================================

def build_miner_character():
    """
    Builds the complete stylized semi-realistic 3D miner character matching assets/concept art/miner.jpg.
    """
    m_skin = create_pbr_material("M_MinerSkin", (0.78, 0.54, 0.36, 1.0), roughness=0.55)
    m_beard = create_pbr_material("M_MinerBeard", (0.20, 0.14, 0.09, 1.0), roughness=0.88)
    m_eyes = create_pbr_material("M_Eyes", (0.10, 0.08, 0.06, 1.0), roughness=0.3)
    m_helmet = create_pbr_material("M_HardHat", (0.88, 0.36, 0.06, 1.0), roughness=0.35) # Vivid safety orange
    m_lamp_casing = create_pbr_material("M_HeadlampCase", (0.18, 0.19, 0.20, 1.0), metallic=0.85, roughness=0.35)
    m_lamp_light = create_pbr_material("M_HeadlampLight", (1.0, 0.98, 0.85, 1.0), emission=(1.0, 0.98, 0.8, 1.0), emission_strength=5.0)
    m_shirt = create_pbr_material("M_WorkShirt", (0.86, 0.38, 0.10, 1.0), roughness=0.80) # Worker orange shirt
    m_vest = create_pbr_material("M_CanvasVest", (0.36, 0.24, 0.15, 1.0), roughness=0.78) # Weathered tan/brown canvas
    m_denim = create_pbr_material("M_DenimOveralls", (0.18, 0.27, 0.38, 1.0), roughness=0.82) # Dark denim blue
    m_patch = create_pbr_material("M_DenimPatch", (0.12, 0.18, 0.26, 1.0), roughness=0.85)
    m_leather = create_pbr_material("M_HeavyLeather", (0.22, 0.14, 0.08, 1.0), roughness=0.68)
    m_gloves = create_pbr_material("M_WorkGloves", (0.30, 0.20, 0.12, 1.0), roughness=0.75)
    m_brass = create_pbr_material("M_BrassBuckle", (0.82, 0.66, 0.24, 1.0), metallic=0.90, roughness=0.30)
    m_rope = create_pbr_material("M_WorkRope", (0.72, 0.62, 0.48, 1.0), roughness=0.90)
    m_backpack = create_pbr_material("M_Backpack", (0.26, 0.28, 0.19, 1.0), roughness=0.82)
    m_boot_sole = create_pbr_material("M_BootSole", (0.08, 0.08, 0.08, 1.0), roughness=0.92)

    parts = []

    # --- 1. HEAD & FACE ---
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=14, radius=0.14, location=(0, 0.0, 1.62))
    head = bpy.context.active_object
    head.name = "Miner_Head"
    head.scale = (0.94, 1.05, 1.08)
    bpy.ops.object.transform_apply(scale=True)
    head.data.materials.append(m_skin)
    parts.append(head)

    # Eyes & Eyebrows
    for side, x_loc in [(-1, -0.045), (1, 0.045)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.014, location=(x_loc, -0.135, 1.63))
        eye = bpy.context.active_object
        eye.data.materials.append(m_eyes)
        parts.append(eye)

        bpy.ops.mesh.primitive_cube_add(size=0.028, location=(x_loc, -0.14, 1.66))
        brow = bpy.context.active_object
        brow.scale = (1.4, 0.3, 0.3)
        bpy.ops.object.transform_apply(scale=True)
        brow.data.materials.append(m_beard)
        parts.append(brow)

    # Weathered Nose
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.022, depth=0.05, location=(0, -0.155, 1.60))
    nose = bpy.context.active_object
    nose.rotation_euler = Euler((math.radians(65), 0, 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    nose.data.materials.append(m_skin)
    parts.append(nose)

    # Rugged Beard (Jawline & Chin)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=10, radius=0.125, location=(0, -0.06, 1.50))
    beard = bpy.context.active_object
    beard.name = "Miner_Beard"
    beard.scale = (0.95, 1.05, 0.88)
    bpy.ops.object.transform_apply(scale=True)
    beard.data.materials.append(m_beard)
    parts.append(beard)

    # Mustache
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.020, depth=0.09, location=(0, -0.14, 1.565))
    mustache = bpy.context.active_object
    mustache.rotation_euler = Euler((0, math.radians(90), 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    mustache.data.materials.append(m_beard)
    parts.append(mustache)

    # Ears
    for side, y_loc in [(-1, -0.135), (1, 0.135)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.032, location=(y_loc, 0.0, 1.62))
        ear = bpy.context.active_object
        ear.scale = (0.35, 0.7, 1.1)
        bpy.ops.object.transform_apply(scale=True)
        ear.data.materials.append(m_skin)
        parts.append(ear)

    # --- 2. HARD HAT & HEADLAMP ---
    # Helmet Dome
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=12, radius=0.165, location=(0, 0.0, 1.73))
    helmet = bpy.context.active_object
    helmet.name = "Miner_Helmet"
    helmet.scale = (1.02, 1.12, 0.85)
    bpy.ops.object.transform_apply(scale=True)
    helmet.data.materials.append(m_helmet)
    parts.append(helmet)

    # Helmet Brim (at z=1.68, above eyebrows)
    bpy.ops.mesh.primitive_cylinder_add(vertices=18, radius=0.21, depth=0.016, location=(0, -0.01, 1.685))
    brim = bpy.context.active_object
    brim.name = "Miner_HelmetBrim"
    brim.scale = (0.96, 1.16, 1.0)
    brim.rotation_euler = Euler((math.radians(-4.0), 0, 0), 'XYZ')
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    brim.data.materials.append(m_helmet)
    parts.append(brim)

    # Helmet ridge
    bpy.ops.mesh.primitive_cube_add(size=0.035, location=(0, 0.0, 1.81))
    crest = bpy.context.active_object
    crest.scale = (0.6, 6.0, 0.5)
    bpy.ops.object.transform_apply(scale=True)
    crest.data.materials.append(m_helmet)
    parts.append(crest)

    # Forehead Headlamp Housing
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.032, depth=0.05, location=(0, -0.19, 1.73))
    lamp_housing = bpy.context.active_object
    lamp_housing.name = "Miner_Headlamp"
    lamp_housing.rotation_euler = Euler((math.radians(80.0), 0, 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    lamp_housing.data.materials.append(m_lamp_casing)
    parts.append(lamp_housing)

    # Headlamp Lens
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.026, location=(0, -0.215, 1.732))
    lens = bpy.context.active_object
    lens.scale = (1.0, 0.35, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    lens.data.materials.append(m_lamp_light)
    parts.append(lens)

    # --- 3. TORSO ---
    # Neck
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.09, depth=0.12, location=(0, 0.0, 1.49))
    neck = bpy.context.active_object
    neck.data.materials.append(m_skin)
    parts.append(neck)

    # Orange Shirt Collar
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.11, depth=0.06, location=(0, 0.0, 1.46))
    shirt_collar = bpy.context.active_object
    shirt_collar.data.materials.append(m_shirt)
    parts.append(shirt_collar)

    # Chest & Core (Shirt)
    bpy.ops.mesh.primitive_cube_add(size=0.36, location=(0, 0.01, 1.32))
    chest = bpy.context.active_object
    chest.name = "Miner_Torso"
    chest.scale = (1.28, 0.78, 1.1)
    bpy.ops.object.transform_apply(scale=True)
    chest.data.materials.append(m_shirt)
    parts.append(chest)

    # Canvas Vest
    bpy.ops.mesh.primitive_cube_add(size=0.38, location=(0, 0.015, 1.315))
    vest = bpy.context.active_object
    vest.name = "Miner_Vest"
    vest.scale = (1.34, 0.84, 1.08)
    bpy.ops.object.transform_apply(scale=True)
    vest.data.materials.append(m_vest)
    parts.append(vest)

    # Vest collar lapels
    for x_sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=0.08, location=(x_sign * 0.12, -0.15, 1.45))
        lapel = bpy.context.active_object
        lapel.scale = (0.7, 0.3, 1.6)
        lapel.rotation_euler = Euler((math.radians(20), x_sign * math.radians(-15), 0), 'XYZ')
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        lapel.data.materials.append(m_vest)
        parts.append(lapel)

    # Denim Overalls Bib & Straps
    bpy.ops.mesh.primitive_cube_add(size=0.28, location=(0, -0.15, 1.25))
    bib = bpy.context.active_object
    bib.name = "Miner_Bib"
    bib.scale = (0.9, 0.15, 0.75)
    bpy.ops.object.transform_apply(scale=True)
    bib.data.materials.append(m_denim)
    parts.append(bib)

    # Bib Pocket
    bpy.ops.mesh.primitive_cube_add(size=0.10, location=(0, -0.175, 1.25))
    bib_pocket = bpy.context.active_object
    bib_pocket.scale = (1.1, 0.1, 0.8)
    bpy.ops.object.transform_apply(scale=True)
    bib_pocket.data.materials.append(m_patch)
    parts.append(bib_pocket)

    # Straps over shoulders
    for x_sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=0.05, location=(x_sign * 0.14, 0.01, 1.38))
        strap = bpy.context.active_object
        strap.scale = (0.6, 3.4, 2.2)
        bpy.ops.object.transform_apply(scale=True)
        strap.data.materials.append(m_denim)
        parts.append(strap)

        # Brass button
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.014, depth=0.01, location=(x_sign * 0.14, -0.165, 1.32))
        button = bpy.context.active_object
        button.rotation_euler = Euler((math.radians(90), 0, 0), 'XYZ')
        bpy.ops.object.transform_apply(rotation=True)
        button.data.materials.append(m_brass)
        parts.append(button)

    # --- 4. TOOL BELT & ACCESSORIES ---
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.235, depth=0.08, location=(0, 0.01, 1.06))
    belt = bpy.context.active_object
    belt.name = "Miner_Belt"
    belt.scale = (1.08, 0.78, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    belt.data.materials.append(m_leather)
    parts.append(belt)

    # Brass Buckle
    bpy.ops.mesh.primitive_cube_add(size=0.07, location=(0, -0.185, 1.06))
    buckle = bpy.context.active_object
    buckle.scale = (1.1, 0.25, 0.9)
    bpy.ops.object.transform_apply(scale=True)
    buckle.data.materials.append(m_brass)
    parts.append(buckle)

    # Leather pouch on left hip
    bpy.ops.mesh.primitive_cube_add(size=0.10, location=(-0.255, -0.02, 1.02))
    pouch_l = bpy.context.active_object
    pouch_l.scale = (0.8, 1.1, 1.1)
    pouch_l.rotation_euler = Euler((0, math.radians(-12), 0), 'XYZ')
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    pouch_l.data.materials.append(m_leather)
    parts.append(pouch_l)

    # Coiled rope on right hip
    bpy.ops.mesh.primitive_torus_add(major_radius=0.085, minor_radius=0.022, location=(0.265, -0.01, 1.01))
    rope = bpy.context.active_object
    rope.rotation_euler = Euler((math.radians(75), math.radians(15), 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    rope.data.materials.append(m_rope)
    parts.append(rope)

    # --- 5. SHOULDERS & ARMS ---
    for side, x_mult in [("L", -1), ("R", 1)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.10, location=(x_mult * 0.28, 0.01, 1.38))
        shoulder = bpy.context.active_object
        shoulder.name = f"Miner_Shoulder_{side}"
        shoulder.data.materials.append(m_shirt)
        parts.append(shoulder)

        # Upper Arm (orange shirt sleeve)
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.072, depth=0.22, location=(x_mult * 0.30, 0.01, 1.24))
        upper_arm = bpy.context.active_object
        upper_arm.name = f"Miner_UpperArm_{side}"
        upper_arm.data.materials.append(m_shirt)
        parts.append(upper_arm)

        # Rolled sleeve cuff
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.082, depth=0.04, location=(x_mult * 0.30, 0.01, 1.14))
        cuff = bpy.context.active_object
        cuff.name = f"Miner_Cuff_{side}"
        cuff.data.materials.append(m_shirt)
        parts.append(cuff)

        # Muscular bare forearm
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.062, depth=0.22, location=(x_mult * 0.30, 0.00, 1.01))
        forearm = bpy.context.active_object
        forearm.name = f"Miner_Forearm_{side}"
        forearm.data.materials.append(m_skin)
        parts.append(forearm)

        # Work Glove gauntlet
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.068, depth=0.07, location=(x_mult * 0.30, 0.00, 0.91))
        gauntlet = bpy.context.active_object
        gauntlet.name = f"Miner_Gauntlet_{side}"
        gauntlet.data.materials.append(m_gloves)
        parts.append(gauntlet)

        # Glove hand
        bpy.ops.mesh.primitive_cube_add(size=0.09, location=(x_mult * 0.30, -0.01, 0.83))
        hand = bpy.context.active_object
        hand.name = f"Miner_Hand_{side}"
        hand.scale = (0.75, 1.1, 1.1)
        bpy.ops.object.transform_apply(scale=True)
        hand.data.materials.append(m_gloves)
        parts.append(hand)

    # --- 6. LEGS & BOOTS ---
    bpy.ops.mesh.primitive_cube_add(size=0.34, location=(0, 0.01, 0.96))
    pelvis = bpy.context.active_object
    pelvis.name = "Miner_Pelvis"
    pelvis.scale = (1.2, 0.85, 0.65)
    bpy.ops.object.transform_apply(scale=True)
    pelvis.data.materials.append(m_denim)
    parts.append(pelvis)

    for side, x_mult in [("L", -1), ("R", 1)]:
        # Thigh
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.105, depth=0.36, location=(x_mult * 0.135, 0.01, 0.76))
        thigh = bpy.context.active_object
        thigh.name = f"Miner_Thigh_{side}"
        thigh.data.materials.append(m_denim)
        parts.append(thigh)

        # Shin
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.095, depth=0.36, location=(x_mult * 0.135, 0.01, 0.44))
        shin = bpy.context.active_object
        shin.name = f"Miner_Shin_{side}"
        shin.data.materials.append(m_denim)
        parts.append(shin)

        # Knee patch on right knee
        if side == "R":
            bpy.ops.mesh.primitive_cube_add(size=0.10, location=(x_mult * 0.135, -0.088, 0.58))
            knee_patch = bpy.context.active_object
            knee_patch.name = "Miner_KneePatch"
            knee_patch.scale = (0.9, 0.1, 1.2)
            bpy.ops.object.transform_apply(scale=True)
            knee_patch.data.materials.append(m_patch)
            parts.append(knee_patch)

        # Boot Shaft
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.085, depth=0.20, location=(x_mult * 0.135, 0.01, 0.20))
        boot_shaft = bpy.context.active_object
        boot_shaft.name = f"Miner_BootShaft_{side}"
        boot_shaft.data.materials.append(m_leather)
        parts.append(boot_shaft)

        # Boot Foot
        bpy.ops.mesh.primitive_cube_add(size=0.14, location=(x_mult * 0.135, -0.05, 0.07))
        boot_foot = bpy.context.active_object
        boot_foot.name = f"Miner_Boot_{side}"
        boot_foot.scale = (0.9, 1.7, 0.75)
        bpy.ops.object.transform_apply(scale=True)
        boot_foot.data.materials.append(m_leather)
        parts.append(boot_foot)

        # Boot Sole
        bpy.ops.mesh.primitive_cube_add(size=0.145, location=(x_mult * 0.135, -0.05, 0.018))
        boot_sole = bpy.context.active_object
        boot_sole.name = f"Miner_BootSole_{side}"
        boot_sole.scale = (0.95, 1.75, 0.22)
        bpy.ops.object.transform_apply(scale=True)
        boot_sole.data.materials.append(m_boot_sole)
        parts.append(boot_sole)

    # --- 7. BACKPACK ---
    bpy.ops.mesh.primitive_cube_add(size=0.28, location=(0, 0.20, 1.28))
    pack = bpy.context.active_object
    pack.name = "Miner_Backpack"
    pack.scale = (1.1, 0.65, 1.35)
    bpy.ops.object.transform_apply(scale=True)
    pack.data.materials.append(m_backpack)
    parts.append(pack)

    bpy.ops.mesh.primitive_cube_add(size=0.26, location=(0, 0.24, 1.40))
    pack_flap = bpy.context.active_object
    pack_flap.scale = (1.15, 0.4, 0.4)
    bpy.ops.object.transform_apply(scale=True)
    pack_flap.data.materials.append(m_leather)
    parts.append(pack_flap)

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.065, depth=0.34, location=(0, 0.20, 1.06))
    bedroll = bpy.context.active_object
    bedroll.rotation_euler = Euler((0, math.radians(90), 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    bedroll.data.materials.append(m_backpack)
    parts.append(bedroll)

    # Join
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.join()
    
    miner_mesh = bpy.context.active_object
    miner_mesh.name = "Miner_Character"
    bpy.ops.object.shade_smooth()
    
    return miner_mesh

# ==============================================================================
# 3. RIGGING (ARMATURE & BONES)
# ==============================================================================

def create_miner_armature():
    """Creates a humanoid armature with dedicated ToolSocket.R for pickaxe holding."""
    arm_data = bpy.data.armatures.new("MinerArmature")
    arm_obj = bpy.data.objects.new("MinerRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    # 1. Root & Spine
    b_root = eb.new("Root")
    b_root.head = (0, 0, 0)
    b_root.tail = (0, 0, 0.2)

    b_hips = eb.new("Hips")
    b_hips.head = (0, 0, 0.95)
    b_hips.tail = (0, 0, 1.15)
    b_hips.parent = b_root

    b_chest = eb.new("Chest")
    b_chest.head = (0, 0, 1.15)
    b_chest.tail = (0, 0, 1.45)
    b_chest.parent = b_hips

    b_neck = eb.new("Neck")
    b_neck.head = (0, 0, 1.45)
    b_neck.tail = (0, 0, 1.54)
    b_neck.parent = b_chest

    b_head = eb.new("Head")
    b_head.head = (0, 0, 1.54)
    b_head.tail = (0, 0, 1.82)
    b_head.parent = b_neck

    # 2. Left Arm
    b_sh_l = eb.new("Shoulder.L")
    b_sh_l.head = (-0.12, 0, 1.42)
    b_sh_l.tail = (-0.28, 0, 1.38)
    b_sh_l.parent = b_chest

    b_uarm_l = eb.new("UpperArm.L")
    b_uarm_l.head = (-0.28, 0, 1.38)
    b_uarm_l.tail = (-0.30, 0, 1.14)
    b_uarm_l.parent = b_sh_l

    b_farm_l = eb.new("Forearm.L")
    b_farm_l.head = (-0.30, 0, 1.14)
    b_farm_l.tail = (-0.30, 0, 0.90)
    b_farm_l.parent = b_uarm_l

    b_hand_l = eb.new("Hand.L")
    b_hand_l.head = (-0.30, 0, 0.90)
    b_hand_l.tail = (-0.30, -0.05, 0.78)
    b_hand_l.parent = b_farm_l

    # 3. Right Arm & ToolSocket
    b_sh_r = eb.new("Shoulder.R")
    b_sh_r.head = (0.12, 0, 1.42)
    b_sh_r.tail = (0.28, 0, 1.38)
    b_sh_r.parent = b_chest

    b_uarm_r = eb.new("UpperArm.R")
    b_uarm_r.head = (0.28, 0, 1.38)
    b_uarm_r.tail = (0.30, 0, 1.14)
    b_uarm_r.parent = b_sh_r

    b_farm_r = eb.new("Forearm.R")
    b_farm_r.head = (0.30, 0, 1.14)
    b_farm_r.tail = (0.30, 0, 0.90)
    b_farm_r.parent = b_uarm_r

    b_hand_r = eb.new("Hand.R")
    b_hand_r.head = (0.30, 0, 0.90)
    b_hand_r.tail = (0.30, -0.05, 0.78)
    b_hand_r.parent = b_farm_r

    # Socket dedicated for Pickaxe attachment
    b_socket = eb.new("ToolSocket.R")
    b_socket.head = (0.30, -0.04, 0.82)
    b_socket.tail = (0.30, -0.15, 0.40)
    b_socket.parent = b_hand_r

    # 4. Legs
    b_thigh_l = eb.new("Thigh.L")
    b_thigh_l.head = (-0.135, 0, 0.95)
    b_thigh_l.tail = (-0.135, 0, 0.55)
    b_thigh_l.parent = b_hips

    b_shin_l = eb.new("Shin.L")
    b_shin_l.head = (-0.135, 0, 0.55)
    b_shin_l.tail = (-0.135, 0, 0.15)
    b_shin_l.parent = b_thigh_l

    b_foot_l = eb.new("Foot.L")
    b_foot_l.head = (-0.135, 0, 0.15)
    b_foot_l.tail = (-0.135, -0.15, 0.0)
    b_foot_l.parent = b_shin_l

    b_thigh_r = eb.new("Thigh.R")
    b_thigh_r.head = (0.135, 0, 0.95)
    b_thigh_r.tail = (0.135, 0, 0.55)
    b_thigh_r.parent = b_hips

    b_shin_r = eb.new("Shin.R")
    b_shin_r.head = (0.135, 0, 0.55)
    b_shin_r.tail = (0.135, 0, 0.15)
    b_shin_r.parent = b_thigh_r

    b_foot_r = eb.new("Foot.R")
    b_foot_r.head = (0.135, 0, 0.15)
    b_foot_r.tail = (0.135, -0.15, 0.0)
    b_foot_r.parent = b_shin_r

    bpy.ops.object.mode_set(mode='OBJECT')

    # Force all pose bones to Euler XYZ
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = 'XYZ'

    return arm_obj

def bind_mesh_to_armature(mesh_obj, arm_obj):
    """Binds mesh to armature and assigns bone weight vertex groups."""
    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new(name="Armature", type='ARMATURE')
    mod.object = arm_obj
    mod.use_vertex_groups = True

    bone_names = [b.name for b in arm_obj.data.bones]
    for b_name in bone_names:
        mesh_obj.vertex_groups.new(name=b_name)

    for v in mesh_obj.data.vertices:
        x, y, z = v.co.x, v.co.y, v.co.z
        
        if z >= 1.50:
            mesh_obj.vertex_groups["Head"].add([v.index], 1.0, 'REPLACE')
        elif z >= 1.42:
            mesh_obj.vertex_groups["Neck"].add([v.index], 0.8, 'REPLACE')
            mesh_obj.vertex_groups["Head"].add([v.index], 0.2, 'ADD')
        elif abs(x) > 0.22 and z >= 0.70:
            side = "L" if x < 0 else "R"
            if z >= 1.30:
                mesh_obj.vertex_groups[f"Shoulder.{side}"].add([v.index], 0.8, 'REPLACE')
                mesh_obj.vertex_groups["Chest"].add([v.index], 0.2, 'ADD')
            elif z >= 1.10:
                mesh_obj.vertex_groups[f"UpperArm.{side}"].add([v.index], 1.0, 'REPLACE')
            elif z >= 0.88:
                mesh_obj.vertex_groups[f"Forearm.{side}"].add([v.index], 1.0, 'REPLACE')
            else:
                mesh_obj.vertex_groups[f"Hand.{side}"].add([v.index], 1.0, 'REPLACE')
        elif z >= 1.10:
            mesh_obj.vertex_groups["Chest"].add([v.index], 0.85, 'REPLACE')
            mesh_obj.vertex_groups["Hips"].add([v.index], 0.15, 'ADD')
        elif z >= 0.90:
            mesh_obj.vertex_groups["Hips"].add([v.index], 1.0, 'REPLACE')
        else:
            side = "L" if x < 0 else "R"
            if z >= 0.52:
                mesh_obj.vertex_groups[f"Thigh.{side}"].add([v.index], 1.0, 'REPLACE')
            elif z >= 0.16:
                mesh_obj.vertex_groups[f"Shin.{side}"].add([v.index], 1.0, 'REPLACE')
            else:
                mesh_obj.vertex_groups[f"Foot.{side}"].add([v.index], 1.0, 'REPLACE')

# ==============================================================================
# 4. KEYFRAME ANIMATIONS (IDLE, WALK, RUN, MINE)
# ==============================================================================

def create_animation_action(arm_obj, action_name, frame_count, keyframe_func):
    """Helper to generate a clean baked action on the armature."""
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()
        
    action = bpy.data.actions.new(name=action_name)
    arm_obj.animation_data.action = action
    
    # Ensure all pose bones are in XYZ Euler
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = 'XYZ'

    keyframe_func(arm_obj, frame_count)
    action.use_fake_user = True
    return action

def anim_idle(arm_obj, frame_count=40):
    p_bones = arm_obj.pose.bones
    for f in [1, 20, 40]:
        t = math.sin((f - 1) / 39.0 * 2.0 * math.pi)
        p_bones["Chest"].location = Vector((0, 0, t * 0.012))
        p_bones["Chest"].rotation_euler = Euler((t * 0.03, 0, 0), 'XYZ')
        
        p_bones["UpperArm.L"].rotation_euler = Euler((math.radians(10) + t * 0.02, 0, math.radians(-5)), 'XYZ')
        p_bones["UpperArm.R"].rotation_euler = Euler((math.radians(15) + t * 0.02, 0, math.radians(6)), 'XYZ')
        p_bones["Forearm.R"].rotation_euler = Euler((math.radians(35) + t * 0.02, 0, 0), 'XYZ')
        
        for b_name in ["Chest", "UpperArm.L", "UpperArm.R", "Forearm.R"]:
            p_bones[b_name].keyframe_insert(data_path="location", frame=f)
            p_bones[b_name].keyframe_insert(data_path="rotation_euler", frame=f)

def anim_walk(arm_obj, frame_count=30):
    p_bones = arm_obj.pose.bones
    for f in range(1, frame_count + 1):
        phase = ((f - 1) / (frame_count - 1)) * 2.0 * math.pi
        sin_p = math.sin(phase)
        
        p_bones["Hips"].location = Vector((sin_p * 0.02, 0, abs(sin_p) * -0.03))
        p_bones["Hips"].rotation_euler = Euler((0, sin_p * 0.05, -sin_p * 0.03), 'XYZ')
        
        p_bones["Thigh.L"].rotation_euler = Euler((sin_p * math.radians(28), 0, 0), 'XYZ')
        p_bones["Shin.L"].rotation_euler = Euler((max(0, -sin_p) * math.radians(35), 0, 0), 'XYZ')
        
        p_bones["Thigh.R"].rotation_euler = Euler((-sin_p * math.radians(28), 0, 0), 'XYZ')
        p_bones["Shin.R"].rotation_euler = Euler((max(0, sin_p) * math.radians(35), 0, 0), 'XYZ')
        
        p_bones["UpperArm.L"].rotation_euler = Euler((-sin_p * math.radians(22), 0, 0), 'XYZ')
        p_bones["UpperArm.R"].rotation_euler = Euler((sin_p * math.radians(22), 0, 0), 'XYZ')
        p_bones["Forearm.R"].rotation_euler = Euler((math.radians(35), 0, 0), 'XYZ')
        
        for b in ["Hips", "Thigh.L", "Shin.L", "Thigh.R", "Shin.R", "UpperArm.L", "UpperArm.R", "Forearm.R"]:
            p_bones[b].keyframe_insert(data_path="location", frame=f)
            p_bones[b].keyframe_insert(data_path="rotation_euler", frame=f)

def anim_run(arm_obj, frame_count=20):
    p_bones = arm_obj.pose.bones
    for f in range(1, frame_count + 1):
        phase = ((f - 1) / (frame_count - 1)) * 2.0 * math.pi
        sin_p = math.sin(phase)
        
        p_bones["Hips"].location = Vector((0, -0.04, abs(sin_p) * -0.045))
        p_bones["Hips"].rotation_euler = Euler((math.radians(16), 0, 0), 'XYZ')
        p_bones["Chest"].rotation_euler = Euler((math.radians(8), sin_p * 0.1, 0), 'XYZ')
        
        p_bones["Thigh.L"].rotation_euler = Euler((sin_p * math.radians(45), 0, 0), 'XYZ')
        p_bones["Shin.L"].rotation_euler = Euler((max(0, -sin_p) * math.radians(60), 0, 0), 'XYZ')
        
        p_bones["Thigh.R"].rotation_euler = Euler((-sin_p * math.radians(45), 0, 0), 'XYZ')
        p_bones["Shin.R"].rotation_euler = Euler((max(0, sin_p) * math.radians(60), 0, 0), 'XYZ')
        
        p_bones["UpperArm.L"].rotation_euler = Euler((-sin_p * math.radians(45), 0, 0), 'XYZ')
        p_bones["UpperArm.R"].rotation_euler = Euler((sin_p * math.radians(45), 0, 0), 'XYZ')
        p_bones["Forearm.R"].rotation_euler = Euler((math.radians(45), 0, 0), 'XYZ')
        
        for b in ["Hips", "Chest", "Thigh.L", "Shin.L", "Thigh.R", "Shin.R", "UpperArm.L", "UpperArm.R", "Forearm.R"]:
            p_bones[b].keyframe_insert(data_path="location", frame=f)
            p_bones[b].keyframe_insert(data_path="rotation_euler", frame=f)

def anim_mine(arm_obj, frame_count=36):
    p_bones = arm_obj.pose.bones
    keyframes = {
        1:  {"Hips_rot": (0, 0, 0), "Chest_rot": (0, 0, 0), "ArmR_rot": (0.2, 0, 0.1), "FarmR_rot": (0.4, 0, 0)},
        12: {"Hips_rot": (-0.1, 0.1, 0), "Chest_rot": (-0.25, 0.2, 0), "ArmR_rot": (-1.8, 0, 0.3), "FarmR_rot": (1.4, 0, 0)},
        18: {"Hips_rot": (0.15, -0.05, 0), "Chest_rot": (0.35, -0.15, 0), "ArmR_rot": (0.85, 0, -0.1), "FarmR_rot": (0.2, 0, 0)},
        22: {"Hips_rot": (0.12, -0.03, 0), "Chest_rot": (0.30, -0.10, 0), "ArmR_rot": (0.75, 0, -0.05), "FarmR_rot": (0.3, 0, 0)},
        36: {"Hips_rot": (0, 0, 0), "Chest_rot": (0, 0, 0), "ArmR_rot": (0.2, 0, 0.1), "FarmR_rot": (0.4, 0, 0)}
    }
    for f, data in keyframes.items():
        p_bones["Hips"].rotation_euler = Euler(data["Hips_rot"], 'XYZ')
        p_bones["Chest"].rotation_euler = Euler(data["Chest_rot"], 'XYZ')
        p_bones["UpperArm.R"].rotation_euler = Euler(data["ArmR_rot"], 'XYZ')
        p_bones["Forearm.R"].rotation_euler = Euler(data["FarmR_rot"], 'XYZ')
        p_bones["UpperArm.L"].rotation_euler = Euler((0.4, 0, -0.3), 'XYZ')
        
        for b in ["Hips", "Chest", "UpperArm.R", "Forearm.R", "UpperArm.L"]:
            p_bones[b].keyframe_insert(data_path="rotation_euler", frame=f)

def render_miner_sprites(arm_obj):
    """Renders 2D UI Portrait and 2D Isometric Character Sprite."""
    scene = bpy.context.scene
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    # View transform for vibrant saturated colors
    scene.view_settings.view_transform = 'Standard'

    # 1. Portrait Render (Head, Helmet, Glowing Headlamp, Beard, Vest)
    cam_data = bpy.data.cameras.new("PortraitCam")
    cam_data.type = 'PERSP'
    cam_data.lens = 75
    cam_obj = bpy.data.objects.new("PortraitCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    
    # Position camera with framing centered on head and chest
    cam_obj.location = Vector((0.0, -1.25, 1.58))
    cam_obj.rotation_euler = Euler((math.radians(88), 0, 0), 'XYZ')
    scene.camera = cam_obj
    
    # Subtle soft uplight / face fill light to illuminate face under helmet brim
    face_fill_data = bpy.data.lights.new("FaceFill", type='POINT')
    face_fill_data.energy = 8.0
    face_fill_data.color = (1.0, 0.94, 0.88)
    face_fill_obj = bpy.data.objects.new("FaceFill", face_fill_data)
    bpy.context.collection.objects.link(face_fill_obj)
    face_fill_obj.location = Vector((0.0, -0.65, 1.45))

    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.filepath = MINER_PORTRAIT
    bpy.ops.render.render(write_still=True)
    print(f"Rendered miner portrait to: {MINER_PORTRAIT}")

    # 2. Isometric Full-body Render
    cam_data_iso = bpy.data.cameras.new("IsoCam")
    cam_data_iso.type = 'ORTHO'
    cam_data_iso.ortho_scale = 2.4
    cam_obj_iso = bpy.data.objects.new("IsoCam", cam_data_iso)
    bpy.context.collection.objects.link(cam_obj_iso)

    cam_obj_iso.location = Vector((2.6, -2.6, 3.0))
    cam_obj_iso.rotation_euler = Euler((math.radians(58), 0, math.radians(45)), 'XYZ')
    scene.camera = cam_obj_iso

    scene.render.filepath = MINER_SPRITE
    bpy.ops.render.render(write_still=True)
    print(f"Rendered miner isometric sprite to: {MINER_SPRITE}")

# ==============================================================================
# MAIN EXECUTION PIPELINE
# ==============================================================================

def main():
    print("==================================================================")
    print("🚀 BLENDER MCP: CREATING MINER CHARACTER & PICKAXE ASSETS")
    print("==================================================================")
    
    # --- PHASE 1: PICKAXE ---
    reset_scene()
    print("1. Modeling Pickaxe (Centered for standalone & icon)...")
    pickaxe = build_pickaxe_mesh(centered=True)
    
    print("2. Rendering Pickaxe 2D Icon...")
    render_tool_icon(PICKAXE_ICON)
    
    print("3. Exporting Pickaxe GLB and Blend...")
    bpy.ops.wm.save_as_mainfile(filepath=PICKAXE_BLEND)
    bpy.ops.export_scene.gltf(
        filepath=PICKAXE_GLB,
        export_format='GLB',
        use_selection=False,
        export_materials='EXPORT',
        export_apply=True
    )
    print(f"✅ Saved Pickaxe: {PICKAXE_GLB}")

    # --- PHASE 2: MINER CHARACTER ---
    reset_scene()
    print("4. Modeling Miner Character...")
    miner_mesh = build_miner_character()
    
    print("5. Rigging Armature and Tool Socket...")
    arm_obj = create_miner_armature()
    bind_mesh_to_armature(miner_mesh, arm_obj)

    # Build and attach Pickaxe to Character's Right Hand Socket
    print("5b. Attaching Pickaxe to Character Right Hand Socket...")
    pickaxe_in_hand = build_pickaxe_mesh(centered=False)
    pickaxe_in_hand.name = "Equipped_Pickaxe"
    pickaxe_in_hand.parent = arm_obj
    pickaxe_in_hand.parent_type = 'BONE'
    pickaxe_in_hand.parent_bone = "ToolSocket.R"
    pickaxe_in_hand.location = Vector((0, 0, 0))
    # Align head pointing forward/down naturally in hand grip
    pickaxe_in_hand.rotation_euler = Euler((0, 0, 0), 'XYZ')

    print("6. Baking Keyframed Actions (idle, walk, run, mine)...")
    create_animation_action(arm_obj, "idle", 40, anim_idle)
    create_animation_action(arm_obj, "walk", 30, anim_walk)
    create_animation_action(arm_obj, "run", 20, anim_run)
    create_animation_action(arm_obj, "mine", 36, anim_mine)

    # Set idle as active default action
    arm_obj.animation_data.action = bpy.data.actions["idle"]

    print("7. Setting up Studio Lighting and Rendering Sprites...")
    key_light = bpy.data.lights.new("MinerKeyLight", type='SUN')
    key_light.energy = 2.5
    key_light.color = (1.0, 0.96, 0.9)
    key_obj = bpy.data.objects.new("MinerKeyLight", key_light)
    bpy.context.collection.objects.link(key_obj)
    key_obj.rotation_euler = Euler((math.radians(45), math.radians(25), math.radians(-35)), 'XYZ')

    fill_light = bpy.data.lights.new("MinerFillLight", type='SUN')
    fill_light.energy = 1.2
    fill_light.color = (0.75, 0.85, 1.0)
    fill_obj = bpy.data.objects.new("MinerFillLight", fill_light)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = Euler((math.radians(-30), math.radians(-40), math.radians(120)), 'XYZ')

    render_miner_sprites(arm_obj)

    print("8. Exporting Miner GLB with Armature and Actions...")
    bpy.ops.wm.save_as_mainfile(filepath=MINER_BLEND)
    
    bpy.ops.export_scene.gltf(
        filepath=MINER_GLB,
        export_format='GLB',
        use_selection=False,
        export_materials='EXPORT',
        export_animations=True,
        export_anim_single_armature=True,
        export_nla_strips=True,
        export_apply=False
    )
    print(f"✅ Saved Miner Character: {MINER_GLB}")
    print("==================================================================")
    print("🎉 ALL 3D ASSETS AND SPRITES GENERATED SUCCESSFULLY!")
    print("==================================================================")

if __name__ == "__main__":
    main()
