import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Euler, Matrix, Quaternion

# ==============================================================================
# AFTER WIND - HIGH-FIDELITY REALISTIC STARDEW VALLEY PROTAGONIST GENERATOR
# Based on assets/concept art/farmer.jpg
# Human scale: ~1.78m height, 8 heads athletic proportions
# ==============================================================================

def clean_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)

def create_pbr_material(name, base_color, metallic=0.0, roughness=0.5, sss=0.0, sss_radius=(0.1, 0.05, 0.02), sheen=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    node_out = nodes.new(type='ShaderNodeOutputMaterial')
    node_out.location = (400, 0)
    
    node_bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    node_bsdf.location = (0, 0)
    
    if 'Base Color' in node_bsdf.inputs:
        node_bsdf.inputs['Base Color'].default_value = base_color
    if 'Metallic' in node_bsdf.inputs:
        node_bsdf.inputs['Metallic'].default_value = metallic
    if 'Roughness' in node_bsdf.inputs:
        node_bsdf.inputs['Roughness'].default_value = roughness
    if 'Subsurface Weight' in node_bsdf.inputs:
        node_bsdf.inputs['Subsurface Weight'].default_value = sss
    elif 'Subsurface' in node_bsdf.inputs:
        node_bsdf.inputs['Subsurface'].default_value = sss
    if 'Subsurface Radius' in node_bsdf.inputs:
        node_bsdf.inputs['Subsurface Radius'].default_value = sss_radius
    if 'Sheen Weight' in node_bsdf.inputs:
        node_bsdf.inputs['Sheen Weight'].default_value = sheen
    elif 'Sheen' in node_bsdf.inputs:
        node_bsdf.inputs['Sheen'].default_value = sheen
        
    mat.node_tree.links.new(node_bsdf.outputs['BSDF'], node_out.inputs['Surface'])
    return mat

def create_procedural_flannel_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    node_out = nodes.new(type='ShaderNodeOutputMaterial')
    node_out.location = (600, 0)
    
    node_bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    node_bsdf.location = (300, 0)
    node_bsdf.inputs['Roughness'].default_value = 0.82
    if 'Sheen Weight' in node_bsdf.inputs:
        node_bsdf.inputs['Sheen Weight'].default_value = 0.4
    elif 'Sheen' in node_bsdf.inputs:
        node_bsdf.inputs['Sheen'].default_value = 0.4
        
    node_coord = nodes.new(type='ShaderNodeTexCoord')
    node_coord.location = (-600, 0)
    
    node_wave_x = nodes.new(type='ShaderNodeTexWave')
    node_wave_x.location = (-350, 150)
    node_wave_x.bands_direction = 'X'
    node_wave_x.inputs['Scale'].default_value = 24.0
    node_wave_x.inputs['Distortion'].default_value = 0.3
    
    node_wave_y = nodes.new(type='ShaderNodeTexWave')
    node_wave_y.location = (-350, -150)
    node_wave_y.bands_direction = 'Y'
    node_wave_y.inputs['Scale'].default_value = 24.0
    node_wave_y.inputs['Distortion'].default_value = 0.3
    
    node_mix = nodes.new(type='ShaderNodeMix')
    node_mix.data_type = 'RGBA'
    node_mix.location = (-100, 100)
    node_mix.inputs[6].default_value = (0.72, 0.28, 0.20, 1.0) # Warm terracotta red
    node_mix.inputs[7].default_value = (0.20, 0.28, 0.38, 1.0) # Navy blue cross
    
    node_mix2 = nodes.new(type='ShaderNodeMix')
    node_mix2.data_type = 'RGBA'
    node_mix2.location = (100, 0)
    node_mix2.inputs[7].default_value = (0.88, 0.82, 0.70, 1.0) # Cream grid line
    
    mat.node_tree.links.new(node_coord.outputs['Generated'], node_wave_x.inputs['Vector'])
    mat.node_tree.links.new(node_coord.outputs['Generated'], node_wave_y.inputs['Vector'])
    mat.node_tree.links.new(node_wave_x.outputs['Fac'], node_mix.inputs['Factor'])
    mat.node_tree.links.new(node_mix.outputs[2], node_mix2.inputs[6])
    mat.node_tree.links.new(node_wave_y.outputs['Fac'], node_mix2.inputs['Factor'])
    mat.node_tree.links.new(node_mix2.outputs[2], node_bsdf.inputs['Base Color'])
    mat.node_tree.links.new(node_bsdf.outputs['BSDF'], node_out.inputs['Surface'])
    return mat

def assign_mat_to_verts(verts, mat_idx):
    for v in verts:
        for f in v.link_faces:
            f.material_index = mat_idx

def build_character_geometry():
    bm = bmesh.new()
    
    # 1. ANATOMICAL HEAD & FACIAL FEATURES (SLOT 0: SKIN, SLOT 6: HAIR, SLOT 8/9: EYES)
    head = bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=20, radius=0.115)
    for v in head['verts']:
        if v.co.z < 0:
            if v.co.y < 0:
                v.co.y *= 1.18
                v.co.x *= 0.85
                v.co.z *= 1.08
            else:
                v.co.x *= 0.92
        if v.co.z > 0.02 and v.co.y < -0.04:
            v.co.y -= 0.012
        v.co.z += 1.625
        v.co.y += 0.015
    assign_mat_to_verts(head['verts'], 0)
        
    nose = bmesh.ops.create_cone(bm, segments=12, radius1=0.018, radius2=0.008, depth=0.052)
    for v in nose['verts']:
        v.co.z += 1.615
        v.co.y -= 0.112
    assign_mat_to_verts(nose['verts'], 0)
        
    for sign in [-1, 1]:
        eye = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=10, radius=0.016)
        for v in eye['verts']:
            v.co.x += sign * 0.042
            v.co.y -= 0.092
            v.co.z += 1.642
        assign_mat_to_verts(eye['verts'], 8)
            
        iris = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=0.009)
        for v in iris['verts']:
            v.co.x += sign * 0.042
            v.co.y -= 0.104
            v.co.z += 1.642
        assign_mat_to_verts(iris['verts'], 9)
            
        eyelid = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.019)
        for v in eyelid['verts']:
            if v.co.y > 0:
                v.co.y *= 0.2
            v.co.x += sign * 0.042
            v.co.y -= 0.091
            v.co.z += 1.644
        assign_mat_to_verts(eyelid['verts'], 0)
            
        eyebrow = bmesh.ops.create_cube(bm, size=1.0)
        for v in eyebrow['verts']:
            v.co.x *= 0.032
            v.co.y *= 0.008
            v.co.z *= 0.008
            v.co.x += sign * 0.044
            v.co.y -= 0.104
            v.co.z += 1.668
        assign_mat_to_verts(eyebrow['verts'], 6)
            
    mouth = bmesh.ops.create_cube(bm, size=1.0)
    for v in mouth['verts']:
        v.co.x *= 0.038
        v.co.y *= 0.012
        v.co.z *= 0.014
        v.co.z += (v.co.x ** 2) * 2.0
        v.co.y -= 0.102
        v.co.z += 1.562
    assign_mat_to_verts(mouth['verts'], 0)
        
    for sign in [-1, 1]:
        ear = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.028)
        for v in ear['verts']:
            v.co.x *= 0.35
            v.co.y *= 0.75
            v.co.x += sign * 0.116
            v.co.y += 0.012
            v.co.z += 1.625
        assign_mat_to_verts(ear['verts'], 0)
            
    neck = bmesh.ops.create_cone(bm, segments=18, radius1=0.076, radius2=0.068, depth=0.15)
    for v in neck['verts']:
        v.co.z += 1.485
        v.co.y += 0.012
    assign_mat_to_verts(neck['verts'], 0)
        
    hair = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=0.125)
    for v in hair['verts']:
        if v.co.z < 0:
            v.co.z *= 0.65
        v.co.z += 1.65
        v.co.y += 0.018
        v.co.x *= 1.05
    assign_mat_to_verts(hair['verts'], 6)
        
    # 2. FLANNEL SHIRT (SLOT 1: PLAID)
    shirt = bmesh.ops.create_cone(bm, segments=22, radius1=0.225, radius2=0.205, depth=0.38)
    for v in shirt['verts']:
        v.co.x *= 1.14
        v.co.y *= 0.88
        v.co.z += 1.255
    assign_mat_to_verts(shirt['verts'], 1)
        
    abdomen = bmesh.ops.create_cone(bm, segments=22, radius1=0.205, radius2=0.218, depth=0.28)
    for v in abdomen['verts']:
        v.co.x *= 1.13
        v.co.y *= 0.88
        v.co.z += 0.99
    assign_mat_to_verts(abdomen['verts'], 1)
        
    for sign in [-1, 1]:
        collar = bmesh.ops.create_cube(bm, size=1.0)
        for v in collar['verts']:
            v.co.x *= 0.055
            v.co.y *= 0.082
            v.co.z *= 0.045
            v.co.x += sign * 0.072
            v.co.y -= 0.112
            v.co.z += 1.425
        assign_mat_to_verts(collar['verts'], 1)
            
    # 3. UTILITY CARGO VEST (SLOT 2: KHAKI CANVAS, SLOT 7: BRASS HARDWARE)
    vest = bmesh.ops.create_cone(bm, segments=24, radius1=0.245, radius2=0.218, depth=0.52)
    for v in vest['verts']:
        v.co.x *= 1.16
        v.co.y *= 0.90
        if v.co.y < -0.155 and abs(v.co.x) < 0.048:
            v.co.y += 0.035
        v.co.z += 1.18
    assign_mat_to_verts(vest['verts'], 2)
        
    zipper = bmesh.ops.create_cube(bm, size=1.0)
    for v in zipper['verts']:
        v.co.x *= 0.012
        v.co.y *= 0.015
        v.co.z *= 0.18
        v.co.y -= 0.182
        v.co.z += 1.20
    assign_mat_to_verts(zipper['verts'], 7)
        
    for sign in [-1, 1]:
        pocket = bmesh.ops.create_cube(bm, size=1.0)
        for v in pocket['verts']:
            v.co.x *= 0.065
            v.co.y *= 0.032
            v.co.z *= 0.075
            v.co.x += sign * 0.128
            v.co.y -= 0.186
            v.co.z += 1.245
        assign_mat_to_verts(pocket['verts'], 2)
            
        flap = bmesh.ops.create_cube(bm, size=1.0)
        for v in flap['verts']:
            v.co.x *= 0.072
            v.co.y *= 0.036
            v.co.z *= 0.024
            v.co.x += sign * 0.128
            v.co.y -= 0.192
            v.co.z += 1.295
        assign_mat_to_verts(flap['verts'], 2)
            
        snap = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.008)
        for v in snap['verts']:
            v.co.x += sign * 0.128
            v.co.y -= 0.212
            v.co.z += 1.288
        assign_mat_to_verts(snap['verts'], 7)
            
    harness = bmesh.ops.create_cube(bm, size=1.0)
    for v in harness['verts']:
        v.co.x *= 0.19
        v.co.y *= 0.024
        v.co.z *= 0.22
        v.co.y += 0.182
        v.co.z += 1.26
    assign_mat_to_verts(harness['verts'], 5)
        
    # 4. MODULAR UTILITY BELT & POUCHES (SLOT 5: LEATHER, SLOT 7: BRASS)
    belt = bmesh.ops.create_cone(bm, segments=22, radius1=0.22, radius2=0.22, depth=0.068)
    for v in belt['verts']:
        v.co.x *= 1.13
        v.co.y *= 0.88
        v.co.z += 0.885
    assign_mat_to_verts(belt['verts'], 5)
        
    buckle = bmesh.ops.create_cube(bm, size=1.0)
    for v in buckle['verts']:
        v.co.x *= 0.052
        v.co.y *= 0.022
        v.co.z *= 0.048
        v.co.y -= 0.194
        v.co.z += 0.885
    assign_mat_to_verts(buckle['verts'], 7)
        
    for sign in [-1, 1]:
        pouch = bmesh.ops.create_cube(bm, size=1.0)
        for v in pouch['verts']:
            v.co.x *= 0.058
            v.co.y *= 0.088
            v.co.z *= 0.092
            v.co.x += sign * 0.252
            v.co.y -= 0.015
            v.co.z += 0.845
        assign_mat_to_verts(pouch['verts'], 5)
            
        pouch_flap = bmesh.ops.create_cube(bm, size=1.0)
        for v in pouch_flap['verts']:
            v.co.x *= 0.062
            v.co.y *= 0.092
            v.co.z *= 0.03
            v.co.x += sign * 0.252
            v.co.y -= 0.015
            v.co.z += 0.895
        assign_mat_to_verts(pouch_flap['verts'], 5)
            
        carabiner = bmesh.ops.create_cone(bm, segments=8, radius1=0.014, radius2=0.014, depth=0.042)
        for v in carabiner['verts']:
            v.co.x += sign * 0.17
            v.co.y -= 0.18
            v.co.z += 0.84
        assign_mat_to_verts(carabiner['verts'], 7)
            
    # 5. ARMS, SLEEVES, FOREARMS & GLOVES (SLOT 1, SLOT 0, SLOT 5)
    for sign in [-1, 1]:
        u_arm = bmesh.ops.create_cone(bm, segments=14, radius1=0.075, radius2=0.065, depth=0.28)
        for v in u_arm['verts']:
            v.co.x += sign * 0.285
            v.co.z += 1.24
        assign_mat_to_verts(u_arm['verts'], 1)
            
        cuff = bmesh.ops.create_cone(bm, segments=14, radius1=0.078, radius2=0.078, depth=0.058)
        for v in cuff['verts']:
            v.co.x += sign * 0.302
            v.co.z += 1.095
        assign_mat_to_verts(cuff['verts'], 1)
            
        forearm = bmesh.ops.create_cone(bm, segments=14, radius1=0.056, radius2=0.050, depth=0.25)
        for v in forearm['verts']:
            v.co.x += sign * 0.322
            v.co.z += 0.95
        assign_mat_to_verts(forearm['verts'], 0)
            
        glove_wrist = bmesh.ops.create_cone(bm, segments=12, radius1=0.062, radius2=0.054, depth=0.085)
        for v in glove_wrist['verts']:
            v.co.x += sign * 0.338
            v.co.z += 0.825
        assign_mat_to_verts(glove_wrist['verts'], 5)
            
        palm = bmesh.ops.create_cube(bm, size=1.0)
        for v in palm['verts']:
            v.co.x *= 0.045
            v.co.y *= 0.088
            v.co.z *= 0.098
            v.co.x += sign * 0.342
            v.co.y -= 0.01
            v.co.z += 0.75
        assign_mat_to_verts(palm['verts'], 5)
            
        for f_idx in range(4):
            finger = bmesh.ops.create_cone(bm, segments=8, radius1=0.013, radius2=0.011, depth=0.076)
            for v in finger['verts']:
                v.co.x += sign * 0.342
                v.co.y += -0.036 + (f_idx * 0.024)
                v.co.z += 0.675
            assign_mat_to_verts(finger['verts'], 5)
                
        thumb = bmesh.ops.create_cone(bm, segments=8, radius1=0.015, radius2=0.012, depth=0.068)
        for v in thumb['verts']:
            v.co.x += sign * (0.342 - (sign * 0.024))
            v.co.y -= 0.046
            v.co.z += 0.735
        assign_mat_to_verts(thumb['verts'], 5)
            
    # 6. REINFORCED WORK TROUSERS (SLOT 3: OLIVE TWILL)
    pelvis = bmesh.ops.create_cone(bm, segments=20, radius1=0.208, radius2=0.202, depth=0.20)
    for v in pelvis['verts']:
        v.co.x *= 1.13
        v.co.y *= 0.88
        v.co.z += 0.795
    assign_mat_to_verts(pelvis['verts'], 3)
        
    for sign in [-1, 1]:
        thigh = bmesh.ops.create_cone(bm, segments=16, radius1=0.108, radius2=0.088, depth=0.38)
        for v in thigh['verts']:
            v.co.x += sign * 0.125
            v.co.z += 0.58
        assign_mat_to_verts(thigh['verts'], 3)
            
        knee_patch = bmesh.ops.create_cube(bm, size=1.0)
        for v in knee_patch['verts']:
            v.co.x *= 0.068
            v.co.y *= 0.018
            v.co.z *= 0.115
            v.co.x += sign * 0.125
            v.co.y -= 0.098
            v.co.z += 0.44
        assign_mat_to_verts(knee_patch['verts'], 2)
            
        cargo_thigh = bmesh.ops.create_cube(bm, size=1.0)
        for v in cargo_thigh['verts']:
            v.co.x *= 0.024
            v.co.y *= 0.082
            v.co.z *= 0.115
            v.co.x += sign * 0.232
            v.co.y += 0.01
            v.co.z += 0.535
        assign_mat_to_verts(cargo_thigh['verts'], 3)
            
        shin_trouser = bmesh.ops.create_cone(bm, segments=16, radius1=0.088, radius2=0.094, depth=0.22)
        for v in shin_trouser['verts']:
            v.co.x += sign * 0.125
            v.co.z += 0.34
        assign_mat_to_verts(shin_trouser['verts'], 3)
            
    # 7. HEAVY MUCK BOOTS (SLOT 4: RUBBER/LEATHER)
    for sign in [-1, 1]:
        boot_shaft = bmesh.ops.create_cone(bm, segments=16, radius1=0.096, radius2=0.085, depth=0.24)
        for v in boot_shaft['verts']:
            v.co.x += sign * 0.125
            v.co.z += 0.22
        assign_mat_to_verts(boot_shaft['verts'], 4)
            
        boot_foot = bmesh.ops.create_cube(bm, size=1.0)
        for v in boot_foot['verts']:
            v.co.x *= 0.076
            v.co.y *= 0.158
            v.co.z *= 0.082
            v.co.x += sign * 0.125
            v.co.y -= 0.046
            v.co.z += 0.082
        assign_mat_to_verts(boot_foot['verts'], 4)
            
        boot_sole = bmesh.ops.create_cube(bm, size=1.0)
        for v in boot_sole['verts']:
            v.co.x *= 0.084
            v.co.y *= 0.168
            v.co.z *= 0.034
            v.co.x += sign * 0.125
            v.co.y -= 0.046
            v.co.z += 0.022
        assign_mat_to_verts(boot_sole['verts'], 4)
            
    mesh = bpy.data.meshes.new(name="Farmer_Character")
    bm.to_mesh(mesh)
    bm.free()
    
    for poly in mesh.polygons:
        poly.use_smooth = True
        
    obj = bpy.data.objects.new("Farmer_Character", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj

def build_sun_hat_geometry(mat_hat, mat_band, mat_cord):
    bm = bmesh.new()
    
    crown = bmesh.ops.create_cone(bm, segments=24, radius1=0.138, radius2=0.122, depth=0.115)
    for v in crown['verts']:
        v.co.x *= 0.94
        v.co.y *= 1.08
        if abs(v.co.x) < 0.038 and v.co.z > 0.02:
            v.co.z -= 0.024
        v.co.z += 1.765
        v.co.y += 0.015
    assign_mat_to_verts(crown['verts'], 0)
        
    band = bmesh.ops.create_cone(bm, segments=24, radius1=0.144, radius2=0.144, depth=0.034)
    for v in band['verts']:
        v.co.x *= 0.95
        v.co.y *= 1.08
        v.co.z += 1.722
        v.co.y += 0.015
    assign_mat_to_verts(band['verts'], 1)
        
    brim = bmesh.ops.create_cone(bm, segments=32, radius1=0.295, radius2=0.142, depth=0.035)
    for v in brim['verts']:
        v.co.x *= 0.95
        v.co.y *= 1.14
        dist_rad = math.sqrt(v.co.x**2 + v.co.y**2)
        if dist_rad > 0.17:
            v.co.z -= (dist_rad - 0.17) * 0.38
        v.co.z += 1.712
        v.co.y += 0.015
    assign_mat_to_verts(brim['verts'], 0)
        
    for sign in [-1, 1]:
        cord = bmesh.ops.create_cone(bm, segments=8, radius1=0.005, radius2=0.005, depth=0.26)
        for v in cord['verts']:
            v.co.x += sign * 0.092
            v.co.z += 1.575
            v.co.y -= 0.018
        assign_mat_to_verts(cord['verts'], 2)
            
    toggle = bmesh.ops.create_cube(bm, size=1.0)
    for v in toggle['verts']:
        v.co.x *= 0.018
        v.co.y *= 0.018
        v.co.z *= 0.026
        v.co.z += 1.455
        v.co.y -= 0.018
    assign_mat_to_verts(toggle['verts'], 2)
        
    mesh = bpy.data.meshes.new(name="Sun_Hat")
    bm.to_mesh(mesh)
    bm.free()
    
    for poly in mesh.polygons:
        poly.use_smooth = True
        
    obj = bpy.data.objects.new("Sun_Hat", mesh)
    obj.data.materials.append(mat_hat)  # 0
    obj.data.materials.append(mat_band) # 1
    obj.data.materials.append(mat_cord) # 2
    bpy.context.scene.collection.objects.link(obj)
    return obj

def build_pickaxe_geometry(mat_wood, mat_iron, mat_leather, mat_brass):
    bm = bmesh.new()
    
    # 1. Wooden shaft (черенок) from Z=0.88 down to Z=0.28
    shaft = bmesh.ops.create_cone(bm, segments=12, radius1=0.024, radius2=0.022, depth=0.62)
    for v in shaft['verts']:
        v.co.x += 0.36
        v.co.y -= 0.02
        v.co.z += 0.58
    assign_mat_to_verts(shaft['verts'], 0)
        
    # 2. Leather grip on handle where Hand.R holds it (Hand palm is at Z=0.74)
    grip = bmesh.ops.create_cone(bm, segments=12, radius1=0.027, radius2=0.027, depth=0.22)
    for v in grip['verts']:
        v.co.x += 0.36
        v.co.y -= 0.02
        v.co.z += 0.74
    assign_mat_to_verts(grip['verts'], 2)
        
    # 3. Brass pommel cap on top end of handle
    pommel = bmesh.ops.create_cone(bm, segments=12, radius1=0.028, radius2=0.024, depth=0.03)
    for v in pommel['verts']:
        v.co.x += 0.36
        v.co.y -= 0.02
        v.co.z += 0.88
    assign_mat_to_verts(pommel['verts'], 3)
        
    # 4. Forged iron collar at the BOTTOM (Z=0.34)
    collar = bmesh.ops.create_cube(bm, size=1.0)
    for v in collar['verts']:
        v.co.x *= 0.072
        v.co.y *= 0.065
        v.co.z *= 0.095
        v.co.x += 0.36
        v.co.y -= 0.02
        v.co.z += 0.34
    assign_mat_to_verts(collar['verts'], 1)
        
    # 5. Brass reinforcing rivets on collar
    for sign in [-1, 1]:
        rivet = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.008)
        for v in rivet['verts']:
            v.co.x += 0.36 + (sign * 0.038)
            v.co.y -= 0.02
            v.co.z += 0.34
        assign_mat_to_verts(rivet['verts'], 3)
            
    # 6. Pick striker (curves forward and DOWN towards ground)
    pick = bmesh.ops.create_cone(bm, segments=12, radius1=0.034, radius2=0.005, depth=0.36)
    for v in pick['verts']:
        prog = max(0.0, min(1.0, float((v.co.z + 0.18) / 0.36)))
        v.co.y = -0.02 - (prog * 0.34)
        v.co.z = 0.34 - (prog * 0.10)
        v.co.x += 0.36
    assign_mat_to_verts(pick['verts'], 1)
        
    # 7. Chisel / hammer head (extends backward along positive Y)
    chisel = bmesh.ops.create_cube(bm, size=1.0)
    for v in chisel['verts']:
        v.co.x *= 0.024
        v.co.y *= 0.18
        v.co.z *= 0.038
        v.co.x += 0.36
        v.co.y += 0.07
        v.co.z += 0.34
    assign_mat_to_verts(chisel['verts'], 1)
        
    mesh = bpy.data.meshes.new(name="Equipped_Pickaxe")
    bm.to_mesh(mesh)
    bm.free()
    
    for poly in mesh.polygons:
        poly.use_smooth = True
        
    obj = bpy.data.objects.new("Equipped_Pickaxe", mesh)
    obj.data.materials.append(mat_wood)    # 0
    obj.data.materials.append(mat_iron)    # 1
    obj.data.materials.append(mat_leather) # 2
    obj.data.materials.append(mat_brass)   # 3
    bpy.context.scene.collection.objects.link(obj)
    return obj

# ==============================================================================
# RIGGING & ARMATURE (20+ HUMAN BONES)
# ==============================================================================

def create_humanoid_rig():
    arm_data = bpy.data.armatures.new(name="FarmerRig")
    arm_obj = bpy.data.objects.new("FarmerRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    
    root = eb.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 0.1)
    
    hips = eb.new("Hips")
    hips.head = (0.0, 0.0, 0.82)
    hips.tail = (0.0, 0.0, 0.98)
    hips.parent = root
    
    spine = eb.new("Spine")
    spine.head = (0.0, 0.0, 0.98)
    spine.tail = (0.0, 0.0, 1.20)
    spine.parent = hips
    
    chest = eb.new("Chest")
    chest.head = (0.0, 0.0, 1.20)
    chest.tail = (0.0, 0.0, 1.44)
    chest.parent = spine
    
    neck = eb.new("Neck")
    neck.head = (0.0, 0.0, 1.44)
    neck.tail = (0.0, 0.0, 1.54)
    neck.parent = chest
    
    head = eb.new("Head")
    head.head = (0.0, 0.0, 1.54)
    head.tail = (0.0, 0.0, 1.80)
    head.parent = neck
    
    for sign, side in [(-1, "L"), (1, "R")]:
        clavicle = eb.new(f"Clavicle.{side}")
        clavicle.head = (sign * 0.04, 0.0, 1.42)
        clavicle.tail = (sign * 0.22, 0.0, 1.40)
        clavicle.parent = chest
        
        u_arm = eb.new(f"UpperArm.{side}")
        u_arm.head = (sign * 0.22, 0.0, 1.40)
        u_arm.tail = (sign * 0.30, 0.0, 1.12)
        u_arm.parent = clavicle
        
        f_arm = eb.new(f"Forearm.{side}")
        f_arm.head = (sign * 0.30, 0.0, 1.12)
        f_arm.tail = (sign * 0.34, 0.0, 0.84)
        f_arm.parent = u_arm
        
        hand = eb.new(f"Hand.{side}")
        hand.head = (sign * 0.34, 0.0, 0.84)
        hand.tail = (sign * 0.36, -0.02, 0.68)
        hand.parent = f_arm
        
        if side == "R":
            tool_sock = eb.new("ToolSocket.R")
            tool_sock.head = (0.35, -0.02, 0.76)
            tool_sock.tail = (0.35, -0.02, 0.60)
            tool_sock.parent = hand
            
    for sign, side in [(-1, "L"), (1, "R")]:
        thigh = eb.new(f"Thigh.{side}")
        thigh.head = (sign * 0.125, 0.0, 0.82)
        thigh.tail = (sign * 0.125, 0.0, 0.44)
        thigh.parent = hips
        
        shin = eb.new(f"Shin.{side}")
        shin.head = (sign * 0.125, 0.0, 0.44)
        shin.tail = (sign * 0.125, 0.0, 0.08)
        shin.parent = thigh
        
        foot = eb.new(f"Foot.{side}")
        foot.head = (sign * 0.125, 0.0, 0.08)
        foot.tail = (sign * 0.125, -0.16, 0.02)
        foot.parent = shin
        
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj

def assign_weights(mesh_obj, arm_obj):
    for bone in arm_obj.data.bones:
        if bone.name not in mesh_obj.vertex_groups:
            mesh_obj.vertex_groups.new(name=bone.name)
            
    mesh = mesh_obj.data
    for v in mesh.vertices:
        co = v.co
        z = co.z
        x = co.x
        
        if z >= 1.52:
            mesh_obj.vertex_groups["Head"].add([v.index], 1.0, 'REPLACE')
        elif z >= 1.42:
            mesh_obj.vertex_groups["Neck"].add([v.index], 1.0, 'REPLACE')
        elif abs(x) > 0.20 and z > 0.65:
            side = "R" if x > 0 else "L"
            if z > 1.25:
                mesh_obj.vertex_groups[f"UpperArm.{side}"].add([v.index], 1.0, 'REPLACE')
            elif z > 0.95:
                mesh_obj.vertex_groups[f"Forearm.{side}"].add([v.index], 1.0, 'REPLACE')
            else:
                mesh_obj.vertex_groups[f"Hand.{side}"].add([v.index], 1.0, 'REPLACE')
        elif z >= 1.15:
            mesh_obj.vertex_groups["Chest"].add([v.index], 1.0, 'REPLACE')
        elif z >= 0.90:
            mesh_obj.vertex_groups["Spine"].add([v.index], 1.0, 'REPLACE')
        elif z >= 0.75:
            mesh_obj.vertex_groups["Hips"].add([v.index], 1.0, 'REPLACE')
        else:
            side = "R" if x >= 0 else "L"
            if z > 0.44:
                mesh_obj.vertex_groups[f"Thigh.{side}"].add([v.index], 1.0, 'REPLACE')
            elif z > 0.10:
                mesh_obj.vertex_groups[f"Shin.{side}"].add([v.index], 1.0, 'REPLACE')
            else:
                mesh_obj.vertex_groups[f"Foot.{side}"].add([v.index], 1.0, 'REPLACE')

def assign_single_bone_weight(mesh_obj, bone_name):
    vg = mesh_obj.vertex_groups.new(name=bone_name)
    all_indices = [v.index for v in mesh_obj.data.vertices]
    vg.add(all_indices, 1.0, 'REPLACE')

def attach_to_armature(child_obj, arm_obj):
    mod = child_obj.modifiers.new(name="Armature", type='ARMATURE')
    mod.object = arm_obj
    child_obj.parent = arm_obj

# ==============================================================================
# ANIMATIONS (IDLE, WALK, RUN, MINE)
# ==============================================================================

def bake_animations(arm_obj):
    arm_obj.animation_data_create()
    
    # 1. Idle (2.0s / 60 frames)
    act_idle = bpy.data.actions.new(name="idle")
    act_idle.use_fake_user = True
    arm_obj.animation_data.action = act_idle
    
    chest_bone = arm_obj.pose.bones["Chest"]
    chest_bone.rotation_mode = 'XYZ'
    chest_bone.rotation_euler = (0, 0, 0)
    chest_bone.keyframe_insert(data_path='rotation_euler', frame=1)
    chest_bone.rotation_euler = (-0.035, 0, 0)
    chest_bone.keyframe_insert(data_path='rotation_euler', frame=30)
    chest_bone.rotation_euler = (0, 0, 0)
    chest_bone.keyframe_insert(data_path='rotation_euler', frame=60)
    
    hips_bone = arm_obj.pose.bones["Hips"]
    hips_bone.rotation_mode = 'XYZ'
    hips_bone.location = (0, 0, 0)
    hips_bone.keyframe_insert(data_path='location', frame=1)
    hips_bone.location = (0, 0, -0.008)
    hips_bone.keyframe_insert(data_path='location', frame=30)
    hips_bone.location = (0, 0, 0)
    hips_bone.keyframe_insert(data_path='location', frame=60)
    
    # 2. Walk Cycle (1.2s / 36 frames)
    act_walk = bpy.data.actions.new(name="walk")
    act_walk.use_fake_user = True
    arm_obj.animation_data.action = act_walk
    
    thigh_l = arm_obj.pose.bones["Thigh.L"]
    thigh_r = arm_obj.pose.bones["Thigh.R"]
    arm_l = arm_obj.pose.bones["UpperArm.L"]
    arm_r = arm_obj.pose.bones["UpperArm.R"]
    
    for b in [thigh_l, thigh_r, arm_l, arm_r]:
        b.rotation_mode = 'XYZ'
        
    for frame, leg_fwd, arm_fwd in [(1, 0.35, -0.30), (18, -0.35, 0.30), (36, 0.35, -0.30)]:
        thigh_l.rotation_euler = (leg_fwd, 0, 0)
        thigh_r.rotation_euler = (-leg_fwd, 0, 0)
        arm_l.rotation_euler = (arm_fwd, 0, 0)
        arm_r.rotation_euler = (-arm_fwd, 0, 0)
        
        thigh_l.keyframe_insert(data_path='rotation_euler', frame=frame)
        thigh_r.keyframe_insert(data_path='rotation_euler', frame=frame)
        arm_l.keyframe_insert(data_path='rotation_euler', frame=frame)
        arm_r.keyframe_insert(data_path='rotation_euler', frame=frame)
        
    # 3. Run Cycle (0.8s / 24 frames)
    act_run = bpy.data.actions.new(name="run")
    act_run.use_fake_user = True
    arm_obj.animation_data.action = act_run
    
    chest_bone.rotation_euler = (0.16, 0, 0)
    chest_bone.keyframe_insert(data_path='rotation_euler', frame=1)
    chest_bone.keyframe_insert(data_path='rotation_euler', frame=24)
    
    for frame, leg_fwd, arm_fwd in [(1, 0.65, -0.60), (12, -0.65, 0.60), (24, 0.65, -0.60)]:
        thigh_l.rotation_euler = (leg_fwd, 0, 0)
        thigh_r.rotation_euler = (-leg_fwd, 0, 0)
        arm_l.rotation_euler = (arm_fwd, 0, 0)
        arm_r.rotation_euler = (-arm_fwd, 0, 0)
        
        thigh_l.keyframe_insert(data_path='rotation_euler', frame=frame)
        thigh_r.keyframe_insert(data_path='rotation_euler', frame=frame)
        arm_l.keyframe_insert(data_path='rotation_euler', frame=frame)
        arm_r.keyframe_insert(data_path='rotation_euler', frame=frame)
        
    # 4. Realistic Athletic Strike / Mine (24 frames / ~0.96s at 24 FPS, natural weight, grounded stance, zero backward tilt)
    act_mine = bpy.data.actions.new(name="mine")
    act_mine.use_fake_user = True
    arm_obj.animation_data.action = act_mine
    
    b_hips = arm_obj.pose.bones["Hips"]
    b_spine = arm_obj.pose.bones["Spine"]
    b_chest = arm_obj.pose.bones["Chest"]
    b_neck = arm_obj.pose.bones["Neck"]
    b_head = arm_obj.pose.bones["Head"]
    
    b_u_r = arm_obj.pose.bones["UpperArm.R"]
    b_f_r = arm_obj.pose.bones["Forearm.R"]
    b_h_r = arm_obj.pose.bones["Hand.R"]
    
    b_u_l = arm_obj.pose.bones["UpperArm.L"]
    b_f_l = arm_obj.pose.bones["Forearm.L"]
    b_h_l = arm_obj.pose.bones["Hand.L"]
    
    b_thigh_r = arm_obj.pose.bones["Thigh.R"]
    b_shin_r = arm_obj.pose.bones["Shin.R"]
    b_foot_r = arm_obj.pose.bones["Foot.R"]
    
    b_thigh_l = arm_obj.pose.bones["Thigh.L"]
    b_shin_l = arm_obj.pose.bones["Shin.L"]
    b_foot_l = arm_obj.pose.bones["Foot.L"]
    
    for b in [b_hips, b_spine, b_chest, b_neck, b_head,
              b_u_r, b_f_r, b_h_r, b_u_l, b_f_l, b_h_l,
              b_thigh_r, b_shin_r, b_foot_r, b_thigh_l, b_shin_l, b_foot_l]:
        b.rotation_mode = 'XYZ'
        
    mine_keyframes_data = [
        # Frame 1 (t=0.00s): Neutral Athletic Ready Stance
        (1,  (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),
             (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),
             (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0)),

        # Frame 4 (t=0.13s): Rising Overhead Windup
        (4,  (0.0, 0.005, -0.005),       (0.02, 0.02, -0.04),    (0.01, 0.02, -0.04),   (0.02, 0.03, -0.06),  (-0.02, 0.0, 0.02),   (-0.04, 0.0, 0.03),
             (-0.70, -0.20, 0.25),       (-0.60, 0.0, 0.0),      (-0.20, 0.0, 0.0),     (-0.55, 0.20, -0.25), (-0.45, 0.0, 0.0),    (-0.15, 0.0, 0.0),
             (0.08, 0.02, -0.02),        (-0.06, 0.0, 0.0),      (0.0, 0.0, 0.0),       (-0.10, -0.02, 0.02), (0.08, 0.0, 0.0),     (0.0, 0.0, 0.0)),

        # Frame 8 (t=0.30s): Peak Overhead Windup (Pickaxe high overhead in front)
        (8,  (0.0, 0.01, -0.01),         (0.03, 0.03, -0.06),    (0.02, 0.03, -0.06),   (0.03, 0.04, -0.08),  (-0.04, 0.0, 0.02),   (-0.06, 0.0, 0.03),
             (-1.35, -0.25, 0.35),       (-0.95, 0.0, 0.0),      (-0.25, 0.0, 0.0),     (-1.10, 0.25, -0.30), (-0.75, 0.0, 0.0),    (-0.20, 0.0, 0.0),
             (0.14, 0.03, -0.04),        (-0.10, 0.0, 0.0),      (0.0, 0.0, 0.0),       (-0.16, -0.03, 0.04), (0.12, 0.0, 0.0),     (0.0, 0.0, 0.0)),

        # Frame 11 (t=0.42s): Downward Acceleration Chop
        (11, (0.0, -0.02, -0.02),        (0.08, -0.01, 0.03),    (0.12, -0.01, 0.04),   (0.16, -0.02, 0.05),  (-0.06, 0.01, -0.02), (-0.08, 0.01, -0.03),
             (-0.95, -0.15, 0.15),       (-0.45, 0.0, 0.0),      (-0.10, 0.0, 0.0),     (-0.80, 0.15, -0.15), (-0.35, 0.0, 0.0),    (-0.10, 0.0, 0.0),
             (-0.10, -0.02, 0.0),        (0.08, 0.0, 0.0),       (0.0, 0.0, 0.0),       (0.15, 0.02, 0.0),    (-0.12, 0.0, 0.0),    (0.0, 0.0, 0.0)),

        # Frame 14 (t=0.54s): Solid Impact on Rock (Torso flexed forward, pickaxe strikes rock in front!)
        (14, (0.0, -0.035, -0.035),      (0.10, -0.02, 0.05),    (0.18, 0.01, 0.06),    (0.26, -0.02, 0.07),  (-0.08, 0.01, -0.03), (-0.10, 0.01, -0.04),
             (-0.60, -0.10, 0.0),        (-0.15, 0.0, 0.0),      (0.0, 0.0, 0.0),       (-0.50, 0.10, -0.10), (-0.15, 0.0, 0.0),    (0.0, 0.0, 0.0),
             (-0.22, -0.04, 0.0),        (0.18, 0.0, 0.0),       (0.08, 0.0, 0.0),      (0.30, 0.03, 0.0),    (-0.24, 0.0, 0.0),    (-0.03, 0.0, 0.0)),

        # Frame 17 (t=0.67s): Grounded Contact Hold (Absorbing impact into rock)
        (17, (0.0, -0.03, -0.03),        (0.09, -0.02, 0.04),    (0.16, 0.01, 0.05),    (0.22, -0.02, 0.06),  (-0.07, 0.01, -0.03), (-0.09, 0.01, -0.04),
             (-0.55, -0.08, 0.0),        (-0.12, 0.0, 0.0),      (0.0, 0.0, 0.0),       (-0.45, 0.08, -0.08), (-0.12, 0.0, 0.0),    (0.0, 0.0, 0.0),
             (-0.18, -0.03, 0.0),        (0.15, 0.0, 0.0),       (0.06, 0.0, 0.0),      (0.25, 0.02, 0.0),    (-0.20, 0.0, 0.0),    (-0.02, 0.0, 0.0)),

        # Frame 20 (t=0.80s): Smooth Ascent / Recovery (Torso rises cleanly toward neutral)
        (20, (0.0, -0.01, -0.01),        (0.03, -0.01, 0.02),    (0.06, 0.0, 0.02),     (0.08, -0.01, 0.02),  (-0.03, 0.0, -0.01),  (-0.04, 0.0, -0.02),
             (-0.25, -0.04, 0.0),        (-0.06, 0.0, 0.0),      (0.0, 0.0, 0.0),       (-0.20, 0.04, -0.04), (-0.06, 0.0, 0.0),    (0.0, 0.0, 0.0),
             (-0.06, 0.0, 0.0),          (0.05, 0.0, 0.0),       (0.0, 0.0, 0.0),       (0.10, 0.0, 0.0),     (-0.08, 0.0, 0.0),    (0.0, 0.0, 0.0)),

        # Frame 24 (t=0.96s): Reset to Athletic Neutral (Strict 0.0 neutral stance)
        (24, (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),
             (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),
             (0.0, 0.0, 0.0),            (0.0, 0.0, 0.0),        (0.0, 0.0, 0.0),       (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0),      (0.0, 0.0, 0.0)),
    ]
    
    for d in mine_keyframes_data:
        f = d[0]
        b_hips.location = d[1]
        b_hips.rotation_euler = d[2]
        b_spine.rotation_euler = d[3]
        b_chest.rotation_euler = d[4]
        b_neck.rotation_euler = d[5]
        b_head.rotation_euler = d[6]
        b_u_r.rotation_euler = d[7]
        b_f_r.rotation_euler = d[8]
        b_h_r.rotation_euler = d[9]
        b_u_l.rotation_euler = d[10]
        b_f_l.rotation_euler = d[11]
        b_h_l.rotation_euler = d[12]
        b_thigh_r.rotation_euler = d[13]
        b_shin_r.rotation_euler = d[14]
        b_foot_r.rotation_euler = d[15]
        b_thigh_l.rotation_euler = d[16]
        b_shin_l.rotation_euler = d[17]
        b_foot_l.rotation_euler = d[18]

        b_hips.keyframe_insert(data_path='location', frame=f)
        for b in [b_hips, b_spine, b_chest, b_neck, b_head,
                  b_u_r, b_f_r, b_h_r, b_u_l, b_f_l, b_h_l,
                  b_thigh_r, b_shin_r, b_foot_r, b_thigh_l, b_shin_l, b_foot_l]:
            b.keyframe_insert(data_path='rotation_euler', frame=f)
            
    # Push all 4 actions to NLA tracks for clean glTF export
    arm_obj.animation_data_create()
    for act in [act_idle, act_walk, act_run, act_mine]:
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, int(act.frame_range[0]), act)
    
    for b in arm_obj.pose.bones:
        b.rotation_euler = (0, 0, 0)
        b.location = (0, 0, 0)
        
    arm_obj.animation_data.action = act_idle

# ==============================================================================
# 2D HIGH-RES STUDIO RENDERS (PORTRAIT & ISOMETRIC SPRITE)
# ==============================================================================

def setup_studio_lighting_and_render(output_dir):
    os.makedirs(output_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.film_transparent = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    
    # Key Light (Warm Sun)
    key_light_data = bpy.data.lights.new(name="Key_Light", type='SUN')
    key_light_data.energy = 5.2
    key_light_data.color = (1.0, 0.95, 0.88)
    key_light = bpy.data.objects.new("Key_Light", key_light_data)
    key_light.rotation_euler = (math.radians(50), math.radians(20), math.radians(-30))
    scene.collection.objects.link(key_light)
    
    # Fill Light (Cool Sky)
    fill_light_data = bpy.data.lights.new(name="Fill_Light", type='POINT')
    fill_light_data.energy = 180.0
    fill_light_data.color = (0.75, 0.85, 1.0)
    fill_light = bpy.data.objects.new("Fill_Light", fill_light_data)
    fill_light.location = (-1.6, -1.8, 2.0)
    scene.collection.objects.link(fill_light)
    
    # Rim Light (Back Edge Definition)
    rim_light_data = bpy.data.lights.new(name="Rim_Light", type='POINT')
    rim_light_data.energy = 260.0
    rim_light_data.color = (1.0, 0.92, 0.75)
    rim_light = bpy.data.objects.new("Rim_Light", rim_light_data)
    rim_light.location = (1.2, 1.8, 2.5)
    scene.collection.objects.link(rim_light)
    
    # 4. Under-Hat Fill Light (Illuminates face, eyes, and smile under the brim)
    under_hat_light_data = bpy.data.lights.new(name="UnderHat_Light", type='POINT')
    under_hat_light_data.energy = 55.0
    under_hat_light_data.color = (1.0, 0.94, 0.86)
    under_hat_light = bpy.data.objects.new("UnderHat_Light", under_hat_light_data)
    under_hat_light.location = (0.0, -0.45, 1.58)
    scene.collection.objects.link(under_hat_light)
    
    # Portrait Camera: Centered on Face and Sun Hat (Z=1.65m)
    cam_data = bpy.data.cameras.new("PortraitCamera")
    cam_data.lens = 72.0
    cam_obj = bpy.data.objects.new("PortraitCamera", cam_data)
    cam_obj.location = (0.0, -0.98, 1.62)
    cam_obj.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam_obj)
    
    scene.camera = cam_obj
    portrait_path = os.path.join(output_dir, "farmer_portrait.png")
    scene.render.filepath = portrait_path
    bpy.ops.render.render(write_still=True)
    print(f"✅ Rendered portrait: {portrait_path}")
    
    # Isometric Hero Camera: Centered full-body framing from head to boots holding pickaxe
    cam_data_iso = bpy.data.cameras.new("IsoCamera")
    cam_data_iso.lens = 38.0
    cam_obj_iso = bpy.data.objects.new("IsoCamera", cam_data_iso)
    cam_obj_iso.location = (2.2, -2.6, 2.05)
    cam_obj_iso.rotation_euler = (math.radians(64), 0, math.radians(40))
    scene.collection.objects.link(cam_obj_iso)
    
    scene.camera = cam_obj_iso
    iso_path = os.path.join(output_dir, "farmer_isometric.png")
    scene.render.filepath = iso_path
    bpy.ops.render.render(write_still=True)
    print(f"✅ Rendered isometric sprite: {iso_path}")

# ==============================================================================
# MAIN PIPELINE
# ==============================================================================

def main():
    print("=================================================================")
    print("🌾 HIGH-FIDELITY STARDEW VALLEY PROTAGONIST MODEL PIPELINE")
    print("=================================================================")
    
    clean_scene()
    
    # 1. PBR Materials
    mat_skin = create_pbr_material("M_RealisticSkin", (0.84, 0.65, 0.54, 1.0), roughness=0.52, sss=0.08)
    mat_flannel = create_procedural_flannel_material("M_FlannelPlaid")
    mat_vest = create_pbr_material("M_UtilityVest", (0.64, 0.58, 0.46, 1.0), roughness=0.75)
    mat_pants = create_pbr_material("M_WorkTrousers", (0.38, 0.40, 0.32, 1.0), roughness=0.80)
    mat_boots = create_pbr_material("M_MuckBoots", (0.16, 0.15, 0.14, 1.0), roughness=0.50)
    mat_leather = create_pbr_material("M_OiledLeather", (0.34, 0.22, 0.16, 1.0), roughness=0.42)
    mat_hair = create_pbr_material("M_Hair", (0.24, 0.15, 0.10, 1.0), roughness=0.60)
    mat_brass = create_pbr_material("M_BrassHardware", (0.83, 0.69, 0.22, 1.0), metallic=0.90, roughness=0.28)
    mat_eyewhite = create_pbr_material("M_EyeWhite", (0.95, 0.95, 0.95, 1.0), roughness=0.1)
    mat_iris = create_pbr_material("M_EyeIris", (0.25, 0.38, 0.25, 1.0), roughness=0.2)
    
    mat_hat = create_pbr_material("M_SunHat", (0.76, 0.70, 0.58, 1.0), roughness=0.78)
    mat_hat_band = create_pbr_material("M_HatBand", (0.20, 0.18, 0.16, 1.0), roughness=0.60)
    mat_hat_cord = create_pbr_material("M_HatCord", (0.34, 0.22, 0.16, 1.0), roughness=0.50)
    
    mat_wood = create_pbr_material("M_Hardwood", (0.58, 0.42, 0.28, 1.0), roughness=0.65)
    mat_iron = create_pbr_material("M_ForgedIron", (0.48, 0.51, 0.53, 1.0), metallic=0.92, roughness=0.32)
    
    # 2. Build Meshes
    char_obj = build_character_geometry()
    char_obj.data.materials.append(mat_skin)      # 0
    char_obj.data.materials.append(mat_flannel)   # 1
    char_obj.data.materials.append(mat_vest)      # 2
    char_obj.data.materials.append(mat_pants)     # 3
    char_obj.data.materials.append(mat_boots)     # 4
    char_obj.data.materials.append(mat_leather)   # 5
    char_obj.data.materials.append(mat_hair)      # 6
    char_obj.data.materials.append(mat_brass)     # 7
    char_obj.data.materials.append(mat_eyewhite)  # 8
    char_obj.data.materials.append(mat_iris)      # 9
    
    hat_obj = build_sun_hat_geometry(mat_hat, mat_hat_band, mat_hat_cord)
    pickaxe_obj = build_pickaxe_geometry(mat_wood, mat_iron, mat_leather, mat_brass)
    
    # 3. Create Armature & Rig
    arm_obj = create_humanoid_rig()
    
    # Component-aware weighting avoids splitting boots/torso across limb groups.
    from rebuild_pickaxe_swing import reweight_character, build_mining_action
    reweight_character(char_obj, arm_obj)
    attach_to_armature(char_obj, arm_obj)
    
    # Skin Hat to Head bone (eliminating double-transform!)
    assign_single_bone_weight(hat_obj, "Head")
    attach_to_armature(hat_obj, arm_obj)
    
    # Skin Pickaxe to Hand.R bone
    assign_single_bone_weight(pickaxe_obj, "Hand.R")
    attach_to_armature(pickaxe_obj, arm_obj)
    
    # 4. Bake locomotion, then use the tested short two-hand mining action.
    bake_animations(arm_obj)
    from rebuild_pickaxe_swing import patch_and_export
    # Export patch also rebakes locomotion to a consistent quaternion mode.
    # It preserves all art and uses the same action as the in-game scene.
    patch_and_export()
    
    # 5. Render 2D Sprites
    project_root = r"K:\After Wind"
    sprites_dir = os.path.join(project_root, "assets", "sprites")
    setup_studio_lighting_and_render(sprites_dir)
    
    # 6. Export GLB & BLEND
    models_dir = os.path.join(project_root, "assets", "models", "character")
    os.makedirs(models_dir, exist_ok=True)
    
    blend_path = os.path.join(models_dir, "stardew_farmer.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"✅ Saved Blender file: {blend_path}")
    
    glb_path = os.path.join(models_dir, "stardew_farmer.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_lights=False,
        export_cameras=False
    )
    print(f"✅ Exported GLB model: {glb_path}")
    print("🎉 REALISTIC STARDEW VALLEY PROTAGONIST MODEL PIPELINE COMPLETED!")

if __name__ == "__main__":
    main()
