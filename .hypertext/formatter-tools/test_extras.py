import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("extras.py")


class ExtraFormatterTests(unittest.TestCase):
    def test_ruby_stdin(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "ruby"], input=b"x=1\n", capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, b"x = 1\n")

    def test_pbxproj_keeps_references_and_comments(self):
        source = b"// !$*UTF8*$!\n{ archiveVersion=1; objects={ A /* comment */ = { isa=PBXGroup; children=(B /* ref */,); }; }; rootObject=A /* project */; }\n"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "pbxproj"], input=source, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn(b"/* comment */", result.stdout)
        self.assertIn(b"/* ref */", result.stdout)
        self.assertIn(b"rootObject = A /* project */;", result.stdout)


if __name__ == "__main__":
    unittest.main()
