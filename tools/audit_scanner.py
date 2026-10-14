import os
import re
from pathlib import Path

ROOT = Path(r"k:\After Wind")
scripts_dir = ROOT / "scripts"

classes = {}
for path in scripts_dir.rglob("*.gd"):
    content = path.read_text(encoding="utf-8", errors="replace")
    for line in content.splitlines():
        m = re.match(r"^\s*class_name\s+([A-Za-z0-9_]+)", line)
        if m:
            rel = path.relative_to(ROOT).as_posix()
            classes[m.group(1)] = (rel, line.strip())

cache_path = ROOT / ".godot" / "global_script_class_cache.cfg"
cache_content = cache_path.read_text(encoding="utf-8", errors="replace") if cache_path.exists() else ""

missing_from_cache = []
for c, (p, line) in sorted(classes.items()):
    if f'&"{c}"' not in cache_content and f'"{c}"' not in cache_content:
        missing_from_cache.append((c, p))

print(f"Total class_name in scripts: {len(classes)}")
print(f"Missing from global_script_class_cache.cfg ({len(missing_from_cache)}):")
for c, p in missing_from_cache:
    print(f"  - {c} => {p}")
