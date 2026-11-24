# All in One .NET Installer

Installs every .NET SDK that [Dahlia](https://github.com/AleytiaFairlight/Dahlia) needs,
on Windows, Linux and macOS. It wraps Microsoft's official `dotnet-install`
scripts, so it always fetches supported builds from `dot.net`. Re-running it
is safe: channels that are already installed are skipped, which makes it
suitable as a routine (cron / scheduled task / `install.sh`-style provisioning).

Needed channels (in [`dotnet-versions.env`](dotnet-versions.env)):

| SDK channel | Why Dahlia needs it |
| --- | --- |
| 8.0 | `TwitchLib.Client` tests/benchmarks target `net8.0` (CI installs 8 + 9) |
| 9.0 | Main build: bot, coordinator, twitch, obs, dashboard, avatar, youtube, games, social, workflows (`net9.0`) |
| 10.0 | `avatar/apps/stage-tamagotchi-kirie` targets `net10.0`; TwitchLib multi-targets `net10.0` |
| 11.0 | New supported major (STS). Dahlia has no `net11.0` target yet; SDK 11 also builds older TFMs and covers Dahlia when it adopts `net11.0`. |

`netstandard2.0/2.1` needs no extra SDK. The `netframework4.8` example in
`lib/Dahlia-TwitchLib` is Windows-only, not in `DahliaBot.sln`, and is ignored.

## Quick start

Linux / macOS:

```sh
./install-dotnet.sh
./install-dotnet.sh --check    # routine check: exit 0 = all present, 1 = missing (no network)
./install-dotnet.sh --dry-run  # show what would happen
```

One-liner (pinned to this release):

```sh
curl -fsSL https://raw.githubusercontent.com/AleytiaFairlight/all-in-one-.net-installer/v1.0.1/install-dotnet.sh | bash
```

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File install-dotnet.ps1
powershell -ExecutionPolicy Bypass -File install-dotnet.ps1 -Check
powershell -ExecutionPolicy Bypass -File install-dotnet.ps1 -DryRun
```

One-liner:

```powershell
irm https://raw.githubusercontent.com/AleytiaFairlight/all-in-one-.net-installer/v1.0.1/install-dotnet.ps1 | iex
```

## Options

`install-dotnet.sh`:

```text
--install-dir DIR  default $DOTNET_INSTALL_DIR, else ~/.dotnet
                   (use /usr/share/dotnet for system-wide, as root)
--channel X.Y      install only this channel (default: all in dotnet-versions.env)
--check            exit 0/1 without touching the network
--dry-run          print the plan, install nothing
--yes              non-interactive (never prompt)
-v, --verbose
```

`install-dotnet.ps1`: `-InstallDir`, `-Channel 9.0`, `-Check`, `-DryRun`, `-Quality GA`.

After installing to a non-PATH folder, add it:

```sh
export DOTNET_ROOT="$HOME/.dotnet" PATH="$PATH:$HOME/.dotnet"
```

## Routine use

Weekly cron (Linux/macOS):

```cron
0 3 * * 0 /opt/all-in-one-.net-installer/install-dotnet.sh --yes >> ~/.cache/all-in-one-dotnet-install.log 2>&1
```

Windows Task Scheduler: run `install-dotnet.ps1` weekly with `-ExecutionPolicy Bypass`.

## Updating the channels

1. Edit `DOTNET_CHANNELS` in `dotnet-versions.env`.
2. Update the table above and `CHANGELOG.md`.
3. Bump `VERSION`, tag `v<VERSION>`, and publish a GitHub release (attaches both scripts).

## Verifying

```sh
dotnet --list-sdks       # expect 8.x, 9.x and 10.x lines
dotnet --list-runtimes   # expect Microsoft.NETCore.App + AspNetCore for 8, 9, 10
```

## License

MIT — see [LICENSE](LICENSE).
