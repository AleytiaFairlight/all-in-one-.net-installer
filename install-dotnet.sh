#!/usr/bin/env bash
# All in One .NET Installer (Linux/macOS).
# Installs every .NET SDK Dahlia needs (see dotnet-versions.env) using
# Microsoft's dotnet-install.sh. Safe to re-run: it only installs channels
# whose major.minor SDK is missing (routine-friendly, like deploy/live/install.sh).
#
# Usage:
#   ./install-dotnet.sh [--install-dir DIR] [--channel 9.0] [--check] [--dry-run] [--yes] [-v]
#
#   --install-dir DIR  where to install (default: $DOTNET_INSTALL_DIR, else ~/.dotnet).
#                      Use /usr/share/dotnet for a system-wide install (run as root).
#   --channel X.Y      install only this channel (default: all in dotnet-versions.env).
#   --check            exit 0 when all requested SDKs are present, 1 otherwise (no network).
#   --dry-run          print what would be installed, install nothing.
#   --yes              never prompt (default: prompt only when adding to PATH interactively).
#   -v, --verbose      verbose output.
#
# Env:
#   DOTNET_INSTALL_DIR       same as --install-dir.
#   DOTNET_VERSIONS_FILE     path to dotnet-versions.env (default: next to this script).
#
# Routine use (weekly cron): /path/to/install-dotnet.sh --yes >> ~/.cache/all-in-one-dotnet-install.log 2>&1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="${DOTNET_VERSIONS_FILE:-$SCRIPT_DIR/dotnet-versions.env}"
INSTALLER_URL="https://dot.net/v1/dotnet-install.sh"

install_dir="${DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
only_channel=""
check_only=0
dry_run=0
assume_yes=0
verbose=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="${2:?--install-dir needs a value}"; shift 2 ;;
    --install-dir=*) install_dir="${1#*=}"; shift ;;
    --channel) only_channel="${2:?--channel needs a value like 9.0}"; shift 2 ;;
    --channel=*) only_channel="${1#*=}"; shift ;;
    --check) check_only=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --yes|-y) assume_yes=1; shift ;;
    -v|--verbose) verbose=1; shift ;;
    -h|--help) sed -n '2,/^#$/p' "$0" | sed 's/^# //;s/^#$//'; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

[[ -f "$VERSIONS_FILE" ]] || { echo "versions file not found: $VERSIONS_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$VERSIONS_FILE"
channels="${only_channel:-${DOTNET_CHANNELS:?DOTNET_CHANNELS empty in $VERSIONS_FILE}}"
quality="${DOTNET_QUALITY:-GA}"

vlog() { if [[ "$verbose" == "1" ]]; then echo "dotnet-installer: $*"; fi; }
say() { echo "dotnet-installer: $*"; }

dotnet_bin=""
if [[ -x "$install_dir/dotnet" ]]; then
  dotnet_bin="$install_dir/dotnet"
elif command -v dotnet >/dev/null 2>&1; then
  dotnet_bin="$(command -v dotnet)"
fi

sdk_present() {
  local major="$1" bin="$2"
  [[ -n "$bin" ]] || return 1
  "$bin" --list-sdks 2>/dev/null | grep -qE "^${major}\."
}

missing=()
for ch in $channels; do
  major="${ch%%.*}"
  if sdk_present "$major" "$dotnet_bin"; then
    vlog "SDK $ch present ($dotnet_bin)"
  else
    missing+=("$ch")
  fi
done

if [[ "$check_only" == "1" ]]; then
  if [[ "${#missing[@]}" == "0" ]]; then
    say "all requested SDKs present (${channels}) via ${dotnet_bin:-<none in PATH>}"
    exit 0
  else
    say "missing SDK channel(s): ${missing[*]} (install dir: $install_dir, dotnet: ${dotnet_bin:-none})" >&2
    exit 1
  fi
fi

if [[ "${#missing[@]}" == "0" ]]; then
  say "all requested SDKs present (${channels}) via ${dotnet_bin:-$install_dir/dotnet}"
  if [[ ":$PATH:" != *":$install_dir:"* && -x "$install_dir/dotnet" ]]; then
    say "add to PATH: export PATH=\"\$PATH:$install_dir\" (and DOTNET_ROOT=$install_dir)"
  fi
  "$dotnet_bin" --list-sdks
  exit 0
fi

if [[ "$dry_run" == "1" ]]; then
  say "would install SDK channel(s): ${missing[*]} into $install_dir"
  say "installer: $INSTALLER_URL (quality: $quality)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Download Microsoft's installer with curl, wget, or python3 (live hosts may have no curl).
if command -v curl >/dev/null 2>&1; then
  vlog "downloading $INSTALLER_URL (curl)"
  curl -fsSL -o "$tmp/dotnet-install.sh" "$INSTALLER_URL"
elif command -v wget >/dev/null 2>&1; then
  vlog "downloading $INSTALLER_URL (wget)"
  wget -qO "$tmp/dotnet-install.sh" "$INSTALLER_URL"
else
  vlog "downloading $INSTALLER_URL (python3)"
  python3 - "$INSTALLER_URL" "$tmp/dotnet-install.sh" <<'PY'
import sys, urllib.request
url, out = sys.argv[1:]
urllib.request.urlretrieve(url, out)
PY
fi
chmod +x "$tmp/dotnet-install.sh"

mkdir -p "$install_dir"
for ch in "${missing[@]}"; do
  say "installing .NET SDK channel $ch into $install_dir ..."
  bash "$tmp/dotnet-install.sh" --channel "$ch" --quality "$quality" --install-dir "$install_dir" ${verbose:+--verbose}
done

if [[ -x "$install_dir/dotnet" ]]; then dotnet_bin="$install_dir/dotnet"; fi

failed=()
for ch in $channels; do
  major="${ch%%.*}"
  sdk_present "$major" "$dotnet_bin" || failed+=("$ch")
done

if [[ "${#failed[@]}" != "0" ]]; then
  say "FAILED: SDK channel(s) still missing after install: ${failed[*]}" >&2
  if [[ -n "$dotnet_bin" ]]; then
    "$dotnet_bin" --list-sdks >&2 || true
  fi
  exit 1
fi

say "done. SDKs:"
"$dotnet_bin" --list-sdks
say "runtimes:"
"$dotnet_bin" --list-runtimes | sort
if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  say "add to PATH: export DOTNET_ROOT=\"$install_dir\"; export PATH=\"\$PATH:$install_dir\""
  if [[ "$assume_yes" != "1" && -t 0 ]]; then
    say "skipped automatic PATH change (re-run non-interactively with --yes and set PATH yourself)."
  fi
fi
