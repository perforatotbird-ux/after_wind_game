#!/usr/bin/env python3
"""Run every Godot regression in a separate process and isolated user directory."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
# Godot can report script/import errors while returning exit code zero.
ENGINE_ERROR = re.compile(r"(?:^|\n)\s*(?:SCRIPT ERROR|ERROR|FAIL):", re.MULTILINE)


def run_checked(command: list[str], env: dict[str, str], timeout: float) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8",
            errors="replace", timeout=timeout, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or b""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return False, output + f"\nFAIL: timeout after {timeout:g}s\n"
    except OSError as exc:
        return False, f"FAIL: cannot run engine: {exc}\n"
    return result.returncode == 0 and not ENGINE_ERROR.search(result.stdout), result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=float, default=90.0, help="per-test timeout (seconds)")
    parser.add_argument("--logs", type=Path, default=ROOT / "outputs" / "test-results")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    engine = shutil.which(args.godot)
    if engine is None:
        parser.error("Godot not found; pass --godot PATH or set GODOT_BIN")
    engine = str(Path(engine).resolve())
    tests = sorted((ROOT / "tests").glob("test_*.gd"))
    if not tests:
        print("FAIL: no tests discovered", file=sys.stderr)
        return 1
    args.logs.mkdir(parents=True, exist_ok=True)
    results = []
    with tempfile.TemporaryDirectory(prefix="after-wind-tests-") as temp:
        env = os.environ.copy()
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        env["XDG_DATA_HOME"] = str(Path(temp) / "data")
        env["XDG_CONFIG_HOME"] = str(Path(temp) / "config")
        env["XDG_CACHE_HOME"] = str(Path(temp) / "cache")
        project = ROOT
        external_user_dirs = []
        if sys.platform in ("win32", "darwin"):
            # XDG variables do not affect Godot on Windows/macOS. Use a temporary
            # project with a unique application name instead of touching saves.
            project = Path(temp) / "project"
            shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(".git", "outputs", "__pycache__"))
        base = [engine, "--headless", "--path", str(project)]
        ok, output = run_checked(
            base + ["--editor", "--import"],
            env, max(args.timeout, 180.0),
        )
        (args.logs / "import.log").write_text(output, encoding="utf-8")
        if not ok:
            print(f"FAIL: project import; see {args.logs / 'import.log'}")
            print("\n".join(output.splitlines()[-25:]))
            return 1
        for test in tests:
            test_env = env.copy()
            test_env["XDG_DATA_HOME"] = str(Path(temp) / test.stem / "data")
            if sys.platform in ("win32", "darwin"):
                unique_name = Path(temp).name + "-" + test.stem
                config = (ROOT / "project.godot").read_text(encoding="utf-8")
                config = re.sub(r'^config/name=.*$', 'config/name="' + unique_name + '"', config, flags=re.MULTILINE)
                (project / "project.godot").write_text(config, encoding="utf-8")
                data_home = (Path(os.environ["APPDATA"]) if sys.platform == "win32"
                             else Path.home() / "Library" / "Application Support")
                external_user_dirs.append(data_home / "Godot" / "app_userdata" / unique_name)
            begin = time.monotonic()
            ok, output = run_checked(
                base + ["--script", str(project / "tests" / test.name)],
                test_env, args.timeout,
            )
            duration = round(time.monotonic() - begin, 2)
            (args.logs / f"{test.stem}.log").write_text(output, encoding="utf-8")
            results.append({"test": test.name, "passed": ok, "seconds": duration})
            print(f"{'PASS' if ok else 'FAIL'} {test.name} ({duration:.2f}s)", flush=True)
            if not ok:
                print("\n".join(output.splitlines()[-25:]))
        for directory in external_user_dirs:
            shutil.rmtree(directory, ignore_errors=True)
    (args.logs / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    passed = sum(result["passed"] for result in results)
    print(f"\n{passed}/{len(results)} tests passed. Logs: {args.logs}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
