#!/usr/bin/env python3
"""Run world.tscn headless for 120 frames and monitor runtime errors."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT_EXE = r"K:\Godot_v4.7.2-stable_win64.exe"

# We run Godot loading main scene directly with --quit-after 120
cmd = [
    GODOT_EXE,
    "--headless",
    "--path",
    str(ROOT),
    "--quit-after",
    "120",
    "--verbose"
]

print("Launching main scene (world.tscn) for 120 frames...")
proc = subprocess.run(
    cmd,
    cwd=str(ROOT),
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
    timeout=45
)

print(f"Exit code: {proc.returncode}")
errors = []
warnings = []

for line in proc.stdout.splitlines():
    if "ERROR" in line or "SCRIPT ERROR" in line or "FATAL" in line:
        errors.append(line)
    elif "WARNING" in line:
        warnings.append(line)

print(f"\nTotal Errors: {len(errors)}")
for err in errors[:25]:
    print(f"  [ERROR] {err}")

print(f"\nTotal Warnings: {len(warnings)}")
for warn in warnings[:25]:
    print(f"  [WARN] {warn}")

if errors:
    sys.exit(1)
print("\nWorld smoke test completed successfully!")
