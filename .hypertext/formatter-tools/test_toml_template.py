import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("toml-template.py")
FORMATTER = [
    "node",
    str(SCRIPT.with_name("prettier.mjs")),
    "web/worker/wrangler.toml.example",
    "toml",
]


class TomlTemplateTests(unittest.TestCase):
    def test_authored_template_preserves_placeholder_and_formats_idempotently(self):
        path = ROOT / "web/worker/wrangler.toml.example"
        source = path.read_bytes()
        first = subprocess.run(
            [sys.executable, str(SCRIPT)] + FORMATTER,
            input=source,
            cwd=ROOT,
            capture_output=True,
        )
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        self.assertEqual(first.stdout.count(b"__CURFEW_LICENSE_WORKER_ROUTE__"), 1)
        second = subprocess.run(
            [sys.executable, str(SCRIPT)] + FORMATTER,
            input=first.stdout,
            cwd=ROOT,
            capture_output=True,
        )
        self.assertEqual(second.returncode, 0, second.stderr.decode())
        self.assertEqual(second.stdout, first.stdout)
        self.assertEqual(path.read_bytes(), source)

    def test_formatter_failure_emits_no_staged_replacement(self):
        source = (ROOT / "web/worker/wrangler.toml.example").read_bytes()
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                sys.executable,
                "-c",
                'import sys;sys.stdout.write("partial");sys.exit(2)',
            ],
            input=source,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
