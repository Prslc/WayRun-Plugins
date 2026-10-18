"""Every plugin's vendored framework stays identical to the root package."""

import filecmp
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "wayrun_plugin"
PLUGINS = [
    ROOT / "template",
    ROOT / "examples/python/github",
    ROOT / "examples/python/todo",
]


class VendoredCopyTest(unittest.TestCase):
    def test_every_plugin_copy_matches_the_source(self):
        source = sorted(path.name for path in SOURCE.glob("*.py"))
        for plugin in PLUGINS:
            copy = plugin / "wayrun_plugin"
            with self.subTest(plugin=plugin.relative_to(ROOT).as_posix()):
                self.assertTrue(copy.is_dir(), f"{copy} is missing")
                self.assertEqual(
                    source, sorted(path.name for path in copy.glob("*.py"))
                )
                for name in source:
                    self.assertTrue(
                        filecmp.cmp(SOURCE / name, copy / name, shallow=False),
                        f"{copy / name} is stale; run scripts/vendor.sh {plugin}",
                    )


if __name__ == "__main__":
    unittest.main()
