#!/usr/bin/env python3
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def audit_input_actions():
    print("=== 1. AUDIT INPUT ACTIONS ===")
    project_godot = (ROOT / "project.godot").read_text(encoding="utf-8")
    input_section = re.search(r"\[input\](.*?)(?=\n\[|\Z)", project_godot, re.DOTALL)
    configured_actions = set()
    if input_section:
        configured_actions = set(re.findall(r"^([a-zA-Z0-9_]+)=\{", input_section.group(1), flags=re.MULTILINE))
    print(f"Configured actions ({len(configured_actions)}): {sorted(configured_actions)}")

    action_pattern = re.compile(r'Input\.(?:is_action_just_pressed|is_action_pressed|is_action_just_released|get_action_strength|get_axis|get_vector)\s*\(\s*["\']([^"\']+)["\']')
    action_calls = {}
    for gd in (ROOT / "scripts").rglob("*.gd"):
        content = gd.read_text(encoding="utf-8", errors="replace")
        for line_num, line in enumerate(content.splitlines(), 1):
            for m in action_pattern.finditer(line):
                action = m.group(1)
                action_calls.setdefault(action, []).append((gd.relative_to(ROOT).as_posix(), line_num))

    missing = {}
    for action, occurrences in sorted(action_calls.items()):
        in_cfg = action in configured_actions
        is_builtin = action.startswith("ui_")
        if not in_cfg and not is_builtin:
            missing[action] = occurrences
            print(f"  [MISSING] {action}: {occurrences}")
        else:
            status = "custom" if in_cfg else "builtin"
            print(f"  [OK - {status}] {action} ({len(occurrences)} calls)")
    return missing

def audit_resource_references():
    print("\n=== 2. AUDIT SCENE & RESOURCE REFERENCES ===")
    res_pattern = re.compile(r'res://([a-zA-Z0-9_\-\./]+(?:\.[a-zA-Z0-9_]+))')
    broken_refs = []
    total_refs = 0
    checked_files = list((ROOT / "scenes").rglob("*.tscn")) + list((ROOT / "scripts").rglob("*.gd")) + list((ROOT / "assets").rglob("*.tres"))
    for file_path in checked_files:
        try:
            content = file_path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for line_num, line in enumerate(content.splitlines(), 1):
            for m in res_pattern.finditer(line):
                total_refs += 1
                res_path = m.group(1)
                # Ignore self references or wildcards
                target = ROOT / res_path
                if not target.exists():
                    broken_refs.append((file_path.relative_to(ROOT).as_posix(), line_num, f"res://{res_path}"))
                    print(f"  [BROKEN REF] In {file_path.relative_to(ROOT).as_posix()}:{line_num} -> res://{res_path}")

    print(f"Total checked res:// references: {total_refs}, Broken: {len(broken_refs)}")
    return broken_refs

def audit_tscn_structure():
    print("\n=== 3. AUDIT TSCN EXT_RESOURCES & SUB_RESOURCES ===")
    tscn_files = list((ROOT / "scenes").rglob("*.tscn")) + list((ROOT / "assets").rglob("*.tscn"))
    broken_ext_resources = []
    for tscn in tscn_files:
        content = tscn.read_text(encoding="utf-8", errors="replace")
        # ext_resource format: [ext_resource type="..." path="res://..." id="..."]
        for m in re.finditer(r'\[ext_resource\s+type="([^"]+)"\s+path="res://([^"]+)"\s+id="([^"]+)"\]', content):
            res_type, res_path, res_id = m.groups()
            target = ROOT / res_path
            if not target.exists():
                broken_ext_resources.append((tscn.relative_to(ROOT).as_posix(), f"res://{res_path}", res_type, res_id))
                print(f"  [MISSING EXT_RESOURCE] in {tscn.relative_to(ROOT).as_posix()}: res://{res_path} ({res_type})")
    print(f"Total .tscn checked: {len(tscn_files)}, Broken ext_resources: {len(broken_ext_resources)}")
    return broken_ext_resources

if __name__ == "__main__":
    audit_input_actions()
    audit_resource_references()
    audit_tscn_structure()
