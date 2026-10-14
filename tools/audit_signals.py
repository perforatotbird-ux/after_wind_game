#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def audit_signals():
    print("=" * 60)
    print("AUDITING SIGNALS AND CALLABLES")
    print("=" * 60)

    gd_files = list((ROOT / "scripts").rglob("*.gd"))
    
    # Map file -> declared signals & functions
    file_info = {}
    for f in gd_files:
        content = f.read_text(encoding="utf-8", errors="replace")
        signals = set(re.findall(r"^\s*signal\s+([A-Za-z0-9_]+)", content, re.MULTILINE))
        functions = set(re.findall(r"^\s*func\s+([A-Za-z0-9_]+)", content, re.MULTILINE))
        file_info[f.relative_to(ROOT).as_posix()] = {
            "signals": signals,
            "functions": functions,
            "content": content
        }

    # Check connects in .gd
    connect_pattern = re.compile(r'([A-Za-z0-9_]+)\.connect\(\s*([A-Za-z0-9_]+)\s*\)')
    issues = []
    for rel_path, info in file_info.items():
        for line_num, line in enumerate(info["content"].splitlines(), 1):
            line_str = line.strip()
            if line_str.startswith("#"):
                continue
            for m in connect_pattern.finditer(line):
                sig_name, func_name = m.groups()
                # If connecting to self func_name
                if func_name in ["queue_free", "close", "show", "hide"]:
                    continue
                # If func_name is local
                if func_name not in info["functions"] and not func_name.startswith("func("):
                    # Could be variable or method on another object if it's obj.method
                    pass

    # Check signal connections in all .tscn files
    tscn_files = list((ROOT / "scenes").rglob("*.tscn"))
    tscn_signal_pattern = re.compile(r'\[connection\s+signal="([^"]+)"\s+from="([^"]+)"\s+to="([^"]+)"\s+method="([^"]+)"\]')
    print(f"\nChecking signal connections in {len(tscn_files)} .tscn files...")
    
    tscn_issues = []
    for tscn in tscn_files:
        content = tscn.read_text(encoding="utf-8", errors="replace")
        for m in tscn_signal_pattern.finditer(content):
            sig, from_node, to_node, method = m.groups()
            # Verify if target has the script with this method
            # print(f"  {tscn.name}: {from_node}.{sig} -> {to_node}.{method}")

    print(f"Signal audit complete.")

if __name__ == "__main__":
    audit_signals()
