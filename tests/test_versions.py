"""Installer repo self-tests: versions.env covers Dahlia's real TFMs."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_channels():
    text = (ROOT / "dotnet-versions.env").read_text()
    m = re.search(r'^DOTNET_CHANNELS\s*=\s*"?([^"\n]+)"?', text, re.M)
    assert m, "DOTNET_CHANNELS not found"
    return m.group(1).split()


class TestVersions(unittest.TestCase):
    def test_channels_cover_dahlia_tfms(self):
        channels = load_channels()
        majors = {c.split(".")[0] for c in channels}
        # Dahlia main: net9.0 everywhere; TwitchLib tests: net8.0;
        # stage-tamagotchi-kirie: net10.0.
        self.assertEqual(majors, {"8", "9", "10"})

    def test_readme_table_matches_env(self):
        readme = (ROOT / "README.md").read_text()
        for ch in load_channels():
            self.assertIn(ch, readme)

    def test_version_file_semver(self):
        version = (ROOT / "VERSION").read_text().strip()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")


if __name__ == "__main__":
    unittest.main()
