"""Test runner failure detection without needing Godot."""
import importlib.util
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location("run_tests", Path(__file__).resolve().parents[1] / "tools" / "run_tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def run_code(self, code, timeout=5):
        return runner.run_checked([sys.executable, "-c", code], {}, timeout)

    def test_success(self):
        self.assertTrue(self.run_code("print('PASS: test')")[0])

    def test_nonzero_exit(self):
        self.assertFalse(self.run_code("raise SystemExit(1)")[0])

    def test_zero_exit_with_engine_error(self):
        for prefix in ["ERROR", "SCRIPT ERROR", "FAIL"]:
            with self.subTest(prefix=prefix):
                self.assertFalse(self.run_code(f"print('{prefix}: broken')")[0])

    def test_timeout(self):
        ok, log = self.run_code("import time; time.sleep(10)", timeout=0.1)
        self.assertFalse(ok)
        self.assertIn("timeout", log)

    def test_missing_executable(self):
        self.assertFalse(runner.run_checked(["/no-such-engine"], {}, 1)[0])


if __name__ == "__main__":
    unittest.main()
