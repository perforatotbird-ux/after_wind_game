#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def audit_tscn_connections():
    tscn_files = list((ROOT / "scenes").rglob("*.tscn"))
    pattern = re.compile(r'\[connection\s+signal="([^"]+)"\s+from="([^"]+)"\s+to="([^"]+)"\s+method="([^"]+)"\]')
    
    total = 0
    issues = []
    for tscn in tscn_files:
        content = tscn.read_text(encoding="utf-8")
        connections = pattern.findall(content)
        if connections:
            for sig, from_node, to_node, method in connections:
                total += 1
                # Find the node and script
                print(f"{tscn.name}: {from_node}.{sig} -> {to_node}.{method}")

    print(f"\nTotal tscn connections: {total}")

if __name__ == "__main__":
    audit_tscn_connections()
