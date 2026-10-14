#!/usr/bin/env python3
"""Fast direct test runner for Godot tests."""
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT_EXE = r"K:\Godot_v4.7.2-stable_win64.exe"

ENGINE_ERROR = re.compile(r"(?:^|\n)\s*(?:SCRIPT ERROR|ERROR|FATAL):", re.MULTILINE)

def run_single_test(test_file: Path, timeout: float = 30.0) -> tuple[bool, str, float]:
    cmd = [
        GODOT_EXE,
        "--headless",
        "--path",
        str(ROOT),
        "-s",
        str(test_file.relative_to(ROOT)).replace("\\", "/")
    ]
    start = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout
        )
        duration = round(time.monotonic() - start, 2)
        has_error = proc.returncode != 0 or bool(ENGINE_ERROR.search(proc.stdout))
        return (not has_error), proc.stdout, duration
    except subprocess.TimeoutExpired as exc:
        duration = round(time.monotonic() - start, 2)
        out = exc.stdout or ""
        return False, out + f"\nTIMEOUT after {timeout}s", duration
    except Exception as e:
        duration = round(time.monotonic() - start, 2)
        return False, f"EXECUTION ERROR: {e}", duration

def main():
    filter_arg = sys.argv[1] if len(sys.argv) > 1 else ""
    tests = sorted(ROOT.glob("tests/test_*.gd"))
    if filter_arg:
        tests = [t for t in tests if filter_arg in t.name]

    print(f"Running {len(tests)} test suites with {GODOT_EXE}...\n")
    passed = 0
    failed = []

    for idx, test in enumerate(tests, 1):
        ok, out, dur = run_single_test(test)
        if ok:
            passed += 1
            print(f"[{idx}/{len(tests)}] PASS ({dur:.2f}s): {test.name}")
        else:
            failed.append((test.name, out, dur))
            print(f"[{idx}/{len(tests)}] FAIL ({dur:.2f}s): {test.name}")

    print("\n" + "=" * 60)
    print(f"SUMMARY: {passed} passed, {len(failed)} failed out of {len(tests)}")
    print("=" * 60)

    if failed:
        print("\nFAILED TESTS DETAILS:")
        for name, out, dur in failed:
            print(f"\n--- {name} ({dur:.2f}s) ---")
            lines = [l for l in out.splitlines() if "ERROR" in l or "FAIL" in l or "SCRIPT" in l or "Parse Error" in l or "Compile Error" in l]
            if lines:
                print("\n".join(lines[:15]))
            else:
                print("\n".join(out.splitlines()[-15:]))

    return 0 if not failed else 1

if __name__ == "__main__":
    sys.exit(main())
