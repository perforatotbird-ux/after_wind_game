#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def parse_tscn_nodes(tscn_path: Path):
    content = tscn_path.read_text(encoding="utf-8", errors="replace")
    # find ext_resources that are scripts
    scripts = {}
    for m in re.finditer(r'\[ext_resource[^\]]*type="Script"[^\]]*path="res://([^"]+)"[^\]]*id="([^"]+)"', content):
        scripts[m.group(2)] = m.group(1)

    # find all nodes and their parent/name/script
    nodes = {} # path -> script_path
    root_name = None
    
    # Read block by block
    blocks = re.split(r'\n(?=\[node\s)', content)
    for block in blocks:
        if not block.startswith('[node '):
            continue
        first_line = block.splitlines()[0]
        m = re.match(r'\[node\s+name="([^"]+)"', first_line)
        if not m:
            continue
        name = m.group(1)
        parent_match = re.search(r'parent="([^"]+)"', first_line)
        script_match = re.search(r'script\s*=\s*ExtResource\("([^"]+)"\)', block)
        script_id = script_match.group(1) if script_match else None
        script_file = scripts.get(script_id) if script_id else None

        if parent_match is None:
            # Root node
            root_name = name
            nodes["."] = script_file
            nodes[name] = script_file
        else:
            parent = parent_match.group(1)
            if parent == ".":
                full_path = name
            else:
                full_path = f"{parent}/{name}"
            nodes[full_path] = script_file

    return root_name, nodes

def audit_node_paths():
    print("=" * 60)
    print("AUDITING SCRIPT NODE PATHS AGAINST TSCN SCENES")
    print("=" * 60)

    tscn_files = list((ROOT / "scenes").rglob("*.tscn")) + list((ROOT / "assets").rglob("*.tscn"))
    scene_nodes = {} # tscn_path -> (root_name, {node_rel_path: script})
    script_to_scenes = {} # script_path -> list of (tscn_path, node_path_in_scene)

    for tscn in tscn_files:
        root_name, nodes = parse_tscn_nodes(tscn)
        rel_tscn = tscn.relative_to(ROOT).as_posix()
        scene_nodes[rel_tscn] = (root_name, nodes)
        for n_path, s_file in nodes.items():
            if s_file:
                script_to_scenes.setdefault(s_file, []).append((rel_tscn, n_path))

    print(f"Mapped {len(scene_nodes)} scenes and {len(script_to_scenes)} scripted nodes.\n")

    # Patterns in GDScript:
    # 1. @onready var foo = $Path or get_node("Path")
    # 2. get_node_or_null("Path")
    path_pattern = re.compile(r'(?:get_node|get_node_or_null)\s*\(\s*["\']([^"\']+)["\']\s*\)|\$([A-Za-z0-9_/]+)')

    issues = []
    checked_count = 0

    for script_rel, scenes in script_to_scenes.items():
        script_path = ROOT / script_rel
        if not script_path.exists():
            continue
        content = script_path.read_text(encoding="utf-8", errors="replace")

        for line_num, line in enumerate(content.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            for m in path_pattern.finditer(line):
                checked_count += 1
                raw_path = m.group(1) if m.group(1) is not None else m.group(2)
                # Ignore dynamic paths (%Unique, /root/, dynamic strings)
                if raw_path.startswith("%") or raw_path.startswith("/root/") or "{" in raw_path or " " in raw_path:
                    continue

                # Verify this path in each scene that uses this script
                # If script is attached at node_path_in_scene:
                for tscn_file, node_pos in scenes:
                    root_name, nodes = scene_nodes[tscn_file]
                    # If attached at root (".")
                    if node_pos in [".", root_name]:
                        expected_node = raw_path
                    else:
                        expected_node = f"{node_pos}/{raw_path}"
                    
                    # Normalize path
                    parts = expected_node.split("/")
                    norm_parts = []
                    for p in parts:
                        if p == "." or p == "":
                            continue
                        elif p == "..":
                            if norm_parts: norm_parts.pop()
                        else:
                            norm_parts.append(p)
                    resolved = "/".join(norm_parts)

                    # Check if resolved is in nodes
                    # Also check if it's a get_node_or_null (which might be optional)
                    is_optional = "get_node_or_null" in line
                    if resolved not in nodes and raw_path not in nodes:
                        issues.append({
                            "script": script_rel,
                            "line": line_num,
                            "code": line.strip(),
                            "path": raw_path,
                            "resolved": resolved,
                            "scene": tscn_file,
                            "is_optional": is_optional
                        })

    print(f"Checked {checked_count} node path queries.")
    print(f"Found {len(issues)} potential node path mismatches:")
    for iss in issues:
        opt_str = "OPTIONAL (get_node_or_null)" if iss["is_optional"] else "REQUIRED ($ or get_node)"
        print(f"  [{opt_str}] in {iss['script']}:{iss['line']}")
        print(f"      Code: {iss['code']}")
        print(f"      Path '{iss['path']}' not in scene {iss['scene']}")

if __name__ == "__main__":
    audit_node_paths()
