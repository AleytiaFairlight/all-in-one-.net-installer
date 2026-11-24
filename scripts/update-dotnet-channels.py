#!/usr/bin/env python3
"""Monthly .NET channel updater for All in One .NET Installer.

Compares the channels in dotnet-versions.env against Microsoft's supported
.NET majors (https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json)
and adds any missing supported major (e.g. a newly released .NET).

Only ever adds channels; it never removes one (an EOL channel Dahlia still
targets must keep installing). EOL channels already in the file are reported
as warnings so a human can drop them deliberately.

Usage:
  scripts/update-dotnet-channels.py --check   # exit 0 if up to date, 1 if an update is pending
  scripts/update-dotnet-channels.py --apply   # update dotnet-versions.env, README.md, VERSION, CHANGELOG.md

Env:
  DOTNET_RELEASES_INDEX_URL  override the releases-index URL (tests use a file:// fixture).
"""
import datetime
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / "dotnet-versions.env"
README_FILE = ROOT / "README.md"
VERSION_FILE = ROOT / "VERSION"
CHANGELOG_FILE = ROOT / "CHANGELOG.md"
RELEASES_INDEX_URL = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json"
SUPPORTED_PHASES = {"active", "maintenance"}


def load_channels(path=ENV_FILE):
    text = path.read_text(encoding="utf-8")
    m = re.search(r'^DOTNET_CHANNELS\s*=\s*"?([^"\n]+)"?', text, re.M)
    if not m:
        raise SystemExit(f"DOTNET_CHANNELS not found in {path}")
    return m.group(1).split()


def version_key(v):
    return tuple(int(p) for p in v.split("."))


def fetch_supported(url=None):
    url = url or RELEASES_INDEX_URL
    with urllib.request.urlopen(url) as resp:
        data = json.load(resp)
    supported = []
    for entry in data.get("releases-index", []):
        phase = str(entry.get("support-phase", "")).lower()
        channel = entry.get("channel-version", "")
        if phase in SUPPORTED_PHASES and re.fullmatch(r"\d+\.\d+", channel):
            supported.append(
                {
                    "channel": channel,
                    "release-type": entry.get("release-type", ""),
                    "support-phase": phase,
                    "eol-date": entry.get("eol-date", ""),
                }
            )
    supported.sort(key=lambda e: version_key(e["channel"]))
    return supported


def eol_warnings(channels, supported):
    phase_by_channel = {e["channel"]: e for e in supported}
    warnings = []
    for ch in channels:
        entry = phase_by_channel.get(ch)
        if entry is None:
            warnings.append(f"{ch}: not in releases-index at all (EOL or unknown)")
        elif entry["support-phase"] not in SUPPORTED_PHASES:
            warnings.append(f"{ch}: support-phase={entry['support-phase']}, eol-date={entry['eol-date']}")
    return warnings


def rewrite_env(channels, path=ENV_FILE):
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out = []
    replaced = False
    for line in lines:
        if re.match(r"^DOTNET_CHANNELS\s*=", line):
            out.append(f'DOTNET_CHANNELS="{" ".join(channels)}"\n')
            replaced = True
        else:
            out.append(line)
    if not replaced:
        raise SystemExit(f"DOTNET_CHANNELS line not found in {path}")
    path.write_text("".join(out), encoding="utf-8")


def update_readme(new_channels, date, path=README_FILE):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    start = next(i for i, l in enumerate(lines) if re.match(r"^\| SDK channel \|", l))
    sep = start + 1
    assert re.match(r"^\| ---", lines[sep]), "README channel table separator not found"
    end = sep + 1
    rows = {}
    while end < len(lines) and re.match(r"^\| \d+\.\d+ \|", lines[end]):
        m = re.match(r"^\| (\d+\.\d+) \|(.*)\|\s*\n?$", lines[end])
        rows[m.group(1)] = lines[end]
        end += 1
    for ch in new_channels:
        rows.setdefault(
            ch,
            f"| {ch} | New supported .NET major (auto-added {date}); confirm which Dahlia "
            "TargetFramework needs it, then describe its use here. |\n",
        )
    ordered = [rows[ch] for ch in sorted(rows, key=version_key)]
    lines[start + 2 : end] = ordered
    path.write_text("".join(lines), encoding="utf-8")


def bump_patch_version(path=VERSION_FILE):
    version = path.read_text(encoding="utf-8").strip()
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not m:
        raise SystemExit(f"VERSION is not semver: {version!r}")
    major, minor, patch = map(int, m.groups())
    new_version = f"{major}.{minor}.{patch + 1}"
    path.write_text(new_version + "\n", encoding="utf-8")
    return version, new_version


def prepend_changelog(old_version, new_version, new_channels, date, path=CHANGELOG_FILE):
    text = path.read_text(encoding="utf-8")
    header = "# Changelog\n"
    assert text.startswith(header), "CHANGELOG header not found"
    entry = (
        f"\n## {new_version}\n\n- Add .NET channel(s) {', '.join(new_channels)} "
        f"(monthly update, {date}): newly supported major(s) per Microsoft's releases-index.\n"
        "- Channels are only ever added, never removed; drop EOL ones by hand if Dahlia no longer targets them.\n"
    )
    rest = text[len(header):].lstrip("\n")
    path.write_text(header + entry + "\n" + rest, encoding="utf-8")


def plan(url=None, channels_path=ENV_FILE):
    current = load_channels(channels_path)
    supported = fetch_supported(url)
    supported_channels = [e["channel"] for e in supported]
    new = [c for c in supported_channels if c not in current]
    return current, supported, new


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode not in ("--check", "--apply"):
        raise SystemExit(f"usage: {sys.argv[0]} [--check|--apply]")
    url = None
    if "--url" in argv:
        url = argv[argv.index("--url") + 1]
    import os

    url = url or os.environ.get("DOTNET_RELEASES_INDEX_URL")
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()

    current, supported, new = plan(url)
    print(f"current channels: {' '.join(current)}")
    print(f"supported majors: {' '.join(e['channel'] for e in supported)}")
    for w in eol_warnings(current, supported):
        print(f"eol warning: {w}")
    if not new:
        print("new-channels: none")
        print("channels are up to date")
        return 0

    print(f"new-channels: {' '.join(new)}")
    if mode == "--check":
        print(f"update pending: add {', '.join(new)}")
        return 1

    merged = sorted(set(current) | set(new), key=version_key)
    rewrite_env(merged)
    update_readme(new, today)
    old_version, new_version = bump_patch_version()
    prepend_changelog(old_version, new_version, new, today)
    print(f"applied: channels {' '.join(merged)}, version {old_version} -> {new_version}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
