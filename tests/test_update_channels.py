"""Tests for scripts/update-dotnet-channels.py using a fixture releases-index."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "update_dotnet_channels", ROOT / "scripts" / "update-dotnet-channels.py"
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)

FIXTURE_INDEX = {
    "releases-index": [
        {"channel-version": "8.0", "release-type": "lts", "support-phase": "eol", "eol-date": "2026-11-10"},
        {"channel-version": "9.0", "release-type": "sts", "support-phase": "eol", "eol-date": "2026-11-10"},
        {"channel-version": "10.0", "release-type": "lts", "support-phase": "active", "eol-date": "2028-11-14"},
        {"channel-version": "11.0", "release-type": "sts", "support-phase": "active", "eol-date": "2028-11-14"},
        {"channel-version": "12.0", "release-type": "sts", "support-phase": "preview", "eol-date": ""},
    ]
}


def write_repo(tmp, channels="8.0 9.0 10.0"):
    (tmp / "dotnet-versions.env").write_text(
        '# comment stays\nDOTNET_CHANNELS="'
        + channels
        + '"\nDOTNET_QUALITY="GA"\n',
        encoding="utf-8",
    )
    (tmp / "README.md").write_text(
        "# Title\n\n| SDK channel | Why Dahlia needs it |\n| --- | --- |\n"
        "| 8.0 | Old reason stays. |\n"
        "| 9.0 | Main build. |\n"
        "| 10.0 | Kirie app. |\n\nMore text.\n",
        encoding="utf-8",
    )
    (tmp / "VERSION").write_text("1.0.1\n", encoding="utf-8")
    (tmp / "CHANGELOG.md").write_text("# Changelog\n\n## 1.0.1\n\n- Something.\n", encoding="utf-8")
    (tmp / "releases.json").write_text(json.dumps(FIXTURE_INDEX), encoding="utf-8")
    return tmp


class TestUpdater(unittest.TestCase):
    def test_fetch_supported_skips_eol_and_preview(self):
        with tempfile.TemporaryDirectory() as td:
            url = pathlib.Path(td, "releases.json").as_uri()
            pathlib.Path(td, "releases.json").write_text(json.dumps(FIXTURE_INDEX))
            supported = updater.fetch_supported(url)
            self.assertEqual([e["channel"] for e in supported], ["10.0", "11.0"])

    def test_apply_adds_only_supported_missing(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = write_repo(pathlib.Path(td))
            url = (tmp / "releases.json").as_uri()
            current, supported, new = updater.plan(url, tmp / "dotnet-versions.env")
            self.assertEqual(current, ["8.0", "9.0", "10.0"])
            self.assertEqual(new, ["11.0"])  # 12.0 preview skipped, 8.0/9.0 never removed

            updater.rewrite_env(sorted(set(current) | set(new), key=updater.version_key), tmp / "dotnet-versions.env")
            updater.update_readme(new, "2026-11-21", tmp / "README.md")
            old, new_version = updater.bump_patch_version(tmp / "VERSION")
            updater.prepend_changelog(old, new_version, new, "2026-11-21", tmp / "CHANGELOG.md")

            env = (tmp / "dotnet-versions.env").read_text(encoding="utf-8")
            self.assertIn('DOTNET_CHANNELS="8.0 9.0 10.0 11.0"', env)
            self.assertIn("# comment stays", env)

            readme = (tmp / "README.md").read_text(encoding="utf-8")
            self.assertIn("| 8.0 | Old reason stays. |", readme)
            self.assertIn("| 11.0 | New supported .NET major (auto-added 2026-11-21);", readme)
            # Table stays sorted.
            rows = [l for l in readme.splitlines() if l.startswith("| 1") or l.startswith("| 8") or l.startswith("| 9")]
            self.assertEqual([r.split("|")[1].strip() for r in rows], ["8.0", "9.0", "10.0", "11.0"])

            self.assertEqual((tmp / "VERSION").read_text().strip(), "1.0.2")
            changelog = (tmp / "CHANGELOG.md").read_text(encoding="utf-8")
            self.assertIn("## 1.0.2", changelog)
            self.assertIn("11.0", changelog)

    def test_no_changes_when_current(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = write_repo(pathlib.Path(td), channels="8.0 9.0 10.0 11.0")
            _, _, new = updater.plan((tmp / "releases.json").as_uri(), tmp / "dotnet-versions.env")
            self.assertEqual(new, [])


if __name__ == "__main__":
    unittest.main()
