#!/usr/bin/env python3
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def analyze_gdscript():
    print("=" * 60)
    print("RUNNING DEEP STATIC GDScript ANALYSIS")
    print("=" * 60)

    gd_files = sorted((ROOT / "scripts").rglob("*.gd"))
    print(f"Analyzing {len(gd_files)} GDScript files in scripts/...")

    # 1. Collect all class_name declarations
    classes = {}
    for f in (ROOT / "scripts").rglob("*.gd"):
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*class_name\s+([A-Za-z0-9_]+)", line)
            if m:
                classes[m.group(1)] = f.relative_to(ROOT).as_posix()

    # 2. Check for 'is ClassName' usage where ClassName is not preloaded or in class_cache
    cache_path = ROOT / ".godot" / "global_script_class_cache.cfg"
    cache_text = cache_path.read_text(encoding="utf-8", errors="replace") if cache_path.exists() else ""

    print("\n--- 1. Check 'is <Type>' usages ---")
    type_checks = {}
    for f in gd_files:
        content = f.read_text(encoding="utf-8", errors="replace")
        for line_num, line in enumerate(content.splitlines(), 1):
            for m in re.finditer(r"\bis\s+([A-Z][A-Za-z0-9_]+)\b", line):
                t_name = m.group(1)
                # Ignore Godot built-in types
                builtins = {
                    "Node", "Node3D", "Node2D", "Control", "Area3D", "Area2D",
                    "CharacterBody3D", "CharacterBody2D", "RigidBody3D", "RigidBody2D",
                    "StaticBody3D", "StaticBody2D", "CollisionShape3D", "CollisionShape2D",
                    "MeshInstance3D", "Camera3D", "Camera2D", "AnimationPlayer", "AnimationTree",
                    "AudioStreamPlayer", "AudioStreamPlayer3D", "CanvasLayer", "BaseButton",
                    "Button", "TextureRect", "Label", "ProgressBar", "Panel", "Container",
                    "HBoxContainer", "VBoxContainer", "GridContainer", "MarginContainer",
                    "ScrollContainer", "InputEvent", "InputEventKey", "InputEventMouseButton",
                    "InputEventMouseMotion", "RefCounted", "Resource", "Texture2D", "Material",
                    "StandardMaterial3D", "ShaderMaterial", "Font", "PackedScene", "FileAccess",
                    "DirAccess", "Time", "JSON", "Marshalls", "RegEx", "AStar3D", "SkeletonModifier3D",
                    "Skeleton3D", "OmniLight3D", "DirectionalLight3D", "WorldEnvironment", "Key",
                    "MouseButton", "JoyButton", "JoyAxis"
                }
                if t_name in builtins:
                    continue
                type_checks.setdefault(t_name, []).append((f.relative_to(ROOT).as_posix(), line_num, line.strip()))

    for t_name, occurrences in sorted(type_checks.items()):
        # Check if declared or preloaded in the file
        print(f"Custom type check: 'is {t_name}' in {len(occurrences)} places:")
        for file_path, line_num, line in occurrences:
            file_content = (ROOT / file_path).read_text(encoding="utf-8", errors="replace")
            # check if preloaded as const t_name = ... or if t_name has class_name
            has_preload = bool(re.search(rf"\bconst\s+{t_name}\s*=\s*preload\(", file_content))
            is_global = t_name in classes
            if not has_preload and not is_global:
                print(f"  [POTENTIAL MISSING TYPE] {file_path}:{line_num} -> {t_name} not preloaded and not in classes!")
            elif not has_preload and is_global:
                print(f"  [GLOBAL TYPE] {file_path}:{line_num} -> uses global class {t_name} (defined in {classes[t_name]})")

    # 3. Check for get_node() or $ calls and check common patterns
    print("\n--- 2. Node Path & @onready Audit ---")
    node_pattern = re.compile(r'(?:get_node|get_node_or_null)\s*\(\s*["\']([^"\']+)["\']\s*\)')
    dollar_pattern = re.compile(r'\$([A-Za-z0-9_/]+)')
    
    get_node_calls = []
    for f in gd_files:
        content = f.read_text(encoding="utf-8", errors="replace")
        for line_num, line in enumerate(content.splitlines(), 1):
            # Skip comments
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            for m in node_pattern.finditer(line):
                get_node_calls.append((f.relative_to(ROOT).as_posix(), line_num, m.group(1), line.strip()))
            for m in dollar_pattern.finditer(line):
                get_node_calls.append((f.relative_to(ROOT).as_posix(), line_num, m.group(1), line.strip()))

    print(f"Total direct node path references: {len(get_node_calls)}")

    # 4. Check for dangerous calls, division by zero, null checks
    print("\n--- 3. Code patterns (await, queue_free, division) ---")
    suspicious = []
    for f in gd_files:
        content = f.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()
        for idx, line in enumerate(lines, 1):
            # check queue_free followed by using the same variable
            if "queue_free()" in line:
                m = re.search(r'([A-Za-z0-9_]+)\.queue_free\(\)', line)
                if m:
                    var_name = m.group(1)
                    # check next 3 lines for var_name usage
                    for next_idx in range(idx, min(idx + 3, len(lines))):
                        next_line = lines[next_idx]
                        if var_name in next_line and not re.search(rf'is_instance_valid\s*\(\s*{var_name}\s*\)', next_line) and not f"{var_name} = null" in next_line:
                            if not "queue_free" in next_line:
                                suspicious.append((f.relative_to(ROOT).as_posix(), idx, f"Use of {var_name} after queue_free(): {next_line.strip()}"))

            # Check for await without null/instance validity check
            if "await " in line:
                suspicious.append((f.relative_to(ROOT).as_posix(), idx, f"await pattern: {line.strip()}"))

    print(f"Suspicious post-queue_free usages: {len(suspicious)}")
    for s in suspicious:
        print(f"  {s[0]}:{s[1]} -> {s[2]}")

if __name__ == "__main__":
    analyze_gdscript()
