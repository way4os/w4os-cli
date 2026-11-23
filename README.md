# w4os CLI

![Stable](https://img.shields.io/github/release/way4os/w4os-cli?label=stable&color=green&include_prerelease) ![GitHub Tag](https://img.shields.io/github/tag/way4os/w4os-cli?label=latest&include_prereleases) ![GitHub commits since latest release](https://img.shields.io/github/commits-since/way4os/w4os-cli/latest?label=dev) ![PHP](https://img.shields.io/badge/PHP-8.2+-7884bf) ![Bash](https://img.shields.io/badge/bash-5+) [![License](https://img.shields.io/badge/license-AGPL--3.0-552b55)](LICENSE) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/way4os/w4os-cli/total) [![Donate](https://img.shields.io/badge/-Donate-yellow)](https://magiiic.org/donate/)

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [w4os engine](https://github.com/way4os/w4os-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** The quick setup asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. Besides it: status, ports, start, stop, restart, console and install-dotnet. `dev/build.sh` makes the Debian package and the zip into `dist/`. The package installs the bash completion (`share/bash-completion/opensim`).

## Quick install

This will install OpenSimulator, OpenSim Engine and all required packages from official apt repository.

```bash
curl -fsSL -O https://raw.githubusercontent.com/way4os/w4os-cli/master/kickstart.sh
chmod +x kickstart.sh
sudo ./kickstart.sh --setup
```

See `./kickstart.sh --help` for other options:

- `--unstable` includes the unstable (beta) versions of the packages; `--testing` includes the test builds (charm-tests) and `--unstable`, for whoever tries what comes next.
- `--tools` installs only the command line and the engine, light (no OpenSimulator, no database server, no website), to work on a grid installed otherwise, for instance to import the accounts of a list into it.

The release source (`charm stable`) is always there, whatever the options. For instance, the tools alone from the test builds:

```bash
curl -fsSL -O https://raw.githubusercontent.com/way4os/w4os-cli/master/kickstart.sh
chmod +x kickstart.sh
sudo ./kickstart.sh --testing --tools
```

See our [wiki](https://github.com/way4os/w4os-cli/wiki) for detailed instructions.

To run the installer on an SSH server, download it locally first, then run `./kickstart.sh --remote root@server --setup`.

Containers (Podman, Docker) are not supported yet: [CONTAINERS.md](CONTAINERS.md) has suggestions from the tests so far.

## Requirements

- Bash 5+ (standard on Linux, `brew install bash` on macOS)
- PHP CLI 8.2+ with cURL, intl, mbstring, MySQL and XML extensions
- `jq`
- MySQL or MariaDB server and client
- Root access or `sudo`
- `ssh` and `scp` (SSH installs)
- `dialog` (optional; plain prompts are supported)

Fully tested on:

- Ubuntu 24.04 and 26.04
- Debian 13
- Debian 12: the grid packages (engine, helpers, simulators) only. The website of a grid (w4os-site, Grav) needs PHP 8.3 or newer, which Debian 12 does not have: on Debian 12, kickstart says so and installs the grid without its website. The website needs Debian 13, or Ubuntu 24.04 or newer, with the PHP of the distribution.
- macOS 13.7.8 and later

## Features

### First installation: `kickstart.sh`

- [x] apt official repo (linux, stable by default)
- [x] from local git clone
- [x] from local deb packages
- [x] remote shortcut to install on a distant server
- [x] test builds (`--testing`), the tools alone (`--tools`)
- [ ] advanced/expert install
- [ ] support Homebrew (macos)

### Command-line interface (CLI): `bin/opensim`

#### Commands

- [x] status
- [x] start [--simulators] [target...]
- [x] stop|restart [--simulators] [now] [target...]
- [x] enable|disable <instance...>
- [x] enable|disable <grid> search [<url prefix>]
- [x] enable|disable <grid> economy [beta|gloebit] [<url prefix>]
- [x] enable|disable <grid> profiles
- [x] console|screen <instance>
- [ ] command <instance> <text>|- (not planned: `opensim rest`, the shortcuts such as `save oar` and `opensim console` do it)
- [x] ports [instance...] [--ufw] [--private-address ADDRESS]

`opensim ports` lists configured listeners and their TCP/UDP protocol. `--ufw` prints public firewall rules and comments for private/console ports.

#### Grids

- [x] setup

`opensim setup --prepare setup.json` collects answers without applying the setup and saves them in a private file. Use `--config setup.json` to prefill a later setup or `--apply setup.json` to apply the confirmed configuration without further questions. Preparation and application require an engine that supports these modes.

To stage an existing region without a replacement region or database:

```bash
opensim setup --region-config /path/to/Region.ini --prepare setup.json
opensim setup --apply setup.json
```

This preserves the region's UUID and original settings and leaves the simulator disabled. Database/file restoration and source shutdown come before enabling it.

`opensim import --simulator FILE GRID [--apply]` brings a simulator of another install (its OpenSim.ini, or its file of `opensim.d` in the layout of opensim-debian, with the regions it names) into the grid GRID of this machine. Its database is kept as it is (the new config uses the same one, nothing is copied), its regions are copied with their UUID and their place, its ports and its own settings are kept. Without `--apply` it says what would be written and where, and writes nothing; with it, the simulator is written disabled: stop the old one, then `opensim enable` and `opensim start` the new one. `--name` and `--core` give its name in the grid and the core it runs with, when they are not the ones of its config and of the grid. Several `--simulator` are planned together and checked between them (no two with one port, one region name or UUID, one place of the map), then written in their order; the plan also says the settings of the original that are not kept, and why.

```bash
opensim import --simulator /opt/opensim/etc/opensim.d/redoutable.ini speculoos
opensim import --simulator /opt/opensim/etc/opensim.d/redoutable.ini speculoos --apply
```

`opensim import --grid-settings FILE GRID [--apply]` brings the settings of a grid of another install (its OpenSim.ini, with the files it includes, as OpenSimulator reads them) into the OpenSim.ini of the grid GRID of this machine: the ones of its options (search and data services, economy and Gloebit, offline messages, profiles, groups), what GRID says already being kept, a folder of a simulator and the money of DTL/NSL left out. The plan masks the secrets (keys, passwords, connection strings). The repair of the options then lays them in the simulators of the grid, at the next upgrade of the packages or with `opensim api POST /grids/GRID/options/repair mode=apply`: nobody edits a file.

```bash
opensim import --grid-settings /opt/opensim/etc/grids/Speculoos/OpenSim.ini speculoos
opensim import --grid-settings /opt/opensim/etc/grids/Speculoos/OpenSim.ini speculoos --apply
```

`opensim import --robust FILE [--nick NICK] [--core DIR] [--simulator FILE...] [--apply] [--switch]` migrates the grid of another install into this one: the same grid, its database kept as it is (so its accounts and its regions), its Robust config made the way this install makes one with the settings of the old one put back, the places of its data kept where they are, its simulators with it (`--simulator`, their OpenSim.ini). The old install is never changed. Without `--apply` it says what it would write; `--apply` writes it disabled, after a backup of its database and its files; once the old Robust is stopped (and kept from starting again), `--switch` enables and starts the grid and its simulators here.

```bash
opensim import --robust /opt/opensim/bin/Robust.HG.ini --simulator /opt/opensim/bin/OpenSim.ini
opensim import --robust /opt/opensim/bin/Robust.HG.ini --simulator /opt/opensim/bin/OpenSim.ini --apply
opensim import --robust /opt/opensim/bin/Robust.HG.ini --switch
```

`opensim import --robust FILE --in-place [--simulator FILE...] [--name NAME] [--nick NICK] [--apply]` runs the grid of another install where it is, not migrated: only its section of the config of the suite (`[Grid <nick>]` of `/etc/w4os/w4os.conf`: its Robust config, its core, its simulators) is written, disabled; the install is never changed, and the suite runs it from its own files as any of its grids (`opensim enable`, `opensim start`), the settings of its helpers kept in that section. `--forget --apply` removes the section: the install is as it was.

```bash
opensim import --robust /opt/opensim/bin/Robust.HG.ini --in-place --simulator /opt/opensim/bin/OpenSim.ini --name welcome --apply
opensim enable oldgrid && opensim start oldgrid
opensim import --robust /opt/opensim/bin/Robust.HG.ini --forget --apply
```

`opensim import --accounts FILE GRID [--format csv|json|yaml] [--keep-going] [--result FILE] [--apply]` makes the accounts of a list in the grid GRID: CSV (first, last, email, password, with or without a header line), JSON or YAML (a list of objects with the same keys). The names the grid has are skipped, a line that cannot be used is told and left out, an account given no password gets one, and the first failure stops the others unless `--keep-going`. Without `--apply` it says what it would make. Once applied, the result (each account, and the passwords made here, never shown) is written for the caller only, mode 600: `--result FILE`, else `accounts-result-<date>.csv` in the current folder.

```bash
opensim import --accounts members.csv demo
opensim import --accounts members.csv demo --apply --result members-made.csv
```

The grid may be one this install does not manage: `--robust ROBUST_INI` instead of GRID names it by its Robust config, where it is (its databases are the ones it names; nothing is registered nor written but the accounts). It runs as the caller, who reads that config, and needs only the engine and this command line.

```bash
opensim import --accounts members.csv --robust /opt/opensim/bin/Robust.HG.ini --apply
```

`opensim import FILE [--apply]` applies a setup file (JSON or YAML, the format of the setup files) to the grid of this machine it names: its simulators are made with their regions, or given its regions when the grid has them. `opensim region add GRID SIMULATOR --name NAME [--location X,Y] [--size METERS] [--roles ROLE,...] [--port PORT] [--apply]` gives one region to a simulator, `opensim simulator add GRID NAME --region NAME [--size METERS] [--roles ...] [--http-port PORT] [--owner 'First Last'] [--apply]` makes a simulator with its first region (its database from `OPENSIM_DB_HOST`, `OPENSIM_DB_USER`, `OPENSIM_DB_PASS`, made when missing). What is not given is proposed by the engine (ports, the nearest free place); without `--apply` they say what would be written and where; nothing is started. Both, and `opensim setup`, take `--existing` (the region of that name the grid has already, restored or moved here: its UUID, place, size and owner kept) and `--oar FILE` (its archive, loaded once it runs) or `--dump FILE` (the dump of the database of the old simulator, which makes the database of a new one): see [First setup](docs/First-Setup.md#a-region-the-grid-has-already).

```bash
opensim region add speculoos welcome --name "Welcome Two" --size 512 --roles FallbackRegion
opensim simulator add speculoos north --region "North Shore" --owner "Gudule Lapointe" --apply
opensim simulator add speculoos moved --region "Welcome" --existing --oar Welcome.oar --apply
```

- [x] import --simulator FILE [--simulator FILE...] GRID [--apply]: several simulators planned together, checked between them
- [x] import FILE [--apply] (a setup file), region add, simulator add
- [x] web [grid] [show|check]
- [x] web [grid] snippet <caddy|nginx|apache>
- [x] next <grid> location [X,Y] [COUNT] [-e X,Y]
- [x] ban [grid] <name|uuid>... [--output DIR]
- [x] settings GRID [PAGE] [--set NAME=VALUE...]: the settings pages of a grid (models, economy, search, guide, offline, assets), a secret masked, a database by its parts (`--set searchDatabase.host=...`); a change says when the grid or the simulators must restart
- [x] posts GRID [--author UUID] [--search WORDS] [--page N], posts delete GRID ID: the posts of the avatars of a grid (Flux)

#### Archives and backups

- [x] save iar [GRID [SIM]] [options] [--keep N] FIRST LAST PATH [PASSWORD] [FILE]
- [x] load iar [GRID [SIM]] [-m|--merge] FIRST LAST PATH [PASSWORD] [FILE]
- [x] save oar [GRID [REGION|SIM]] [options] [--keep N] [FILE]
- [x] load oar [GRID [SIM|REGION]] [--merge] [options] [FILE]
- [x] backup [GRID [SIM]] [--logs] [--archives] [--output DIR] [--keep N]
- [x] restore FILE|ARCHIVE [--apply]: a backup put back on this machine (planned; --apply writes, nothing here replaced)
- [x] api [METHOD] PATH [name=value...] [--data=JSON|@FILE|-] [--grid=NICK]: asks the engine API of this machine as the user of the instances, the answer in JSON
- [x] api-key create LABEL | list | revoke LABEL|ID: the keys of the engine API, run as the user of the instances; a key is shown once

#### This machine

- [x] next port [-e PORT] [MIN] [COUNT]
- [ ] profile list|add|default|remove
- [x] oar pack DIR [FILE] | info FILE | check FILE | unpack FILE [DIR]: the archives of regions, the files of the caller
- [x] rest --url http://HOST:PORT --user USER (-- <command> | - | --repl)
- [x] install-dotnet install the .NET runtime OpenSim needs (as root)

### Builds

- [x] apt .deb package (tested on debian 13, ubuntu 24.04 and 26.04, and debian 12 without the website; should work on other debian variants)
- [x] zip (universal)
- [ ] homebrew

## Usage

```bash
bin/opensim setup
```

```
Type: Grid | Standalone | Speculoos (soon) | OSGrid (soon)
```

then one form with every question, the engine's proposals filled in (Enter moves to the next field, the last one leads to OK):

```
Grid name        Amy
Login URI        Amy.local:8002
Avatar name
Password
Password again
Email
```

For a standalone the first field is `Region name`: the region is the simulator and the grid. What the engine refuses comes back with the form, answers kept (`Error: Email invalid`). Then the options, as check boxes (Hypergrid, checked; search, currency, OSSL will join it). Back goes one step back, Quit leaves. The setup the answers stand for is listed, every value the engine defines, by section:

```
* Grid name: Amy (amy)
* Login URI: http://Amy.local:8002
* Hypergrid: yes
...

* Simulator: Welcome (amy.welcome)
...
```

Without a terminal (a script) the questions are plain lines, a number edits an answer (`:back`, `:quit`).

## Settings

`~/.opensimrc` is read first, it is a bash file: it can set the `PATH` (which `php`, which tools) or anything the tools need. The `.env` of this project is read by bash-tools.

## User permissions

The files of the grids belong to the user the instances run as (`SystemUser` of `w4os.conf`). When it is not you, every command runs as that user with `sudo -u`, checked before the first question: you need to be allowed to.
