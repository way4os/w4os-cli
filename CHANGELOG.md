## Changelog

### Unreleased

- feature (import): the plan says the backup of the source it makes first and where the state of the scripts goes; `--no-scripts` leaves the scripts out; `opensim backup --simulator FILE [GRID]` makes that backup of a simulator of another install alone (its databases, its config, its includes, its regions); the CLI needs the engine of 3.0.0~beta.13.493 and later
- feature (web): `opensim web GRID api caddy|nginx|apache [--socket PATH] [--port N] [--web-group GROUP]` prints what serves the engine API to the sites of this machine as the user of the instances: a PHP-FPM pool of its own and a listener on 127.0.0.1 for the paths of the API only (the site then uses engine remote with a key); the CLI needs the engine of 3.0.0~beta.13.486 and later
- update (import): a folder of the old install the new simulator replaces is shown with the folder it has instead
- feature (import): `opensim import --simulator FILE --simulator FILE... GRID` plans several simulators into one grid together, checked between them (ports, region names and UUIDs, places), written in their order, refused when something is wrong between them; the plan says the settings of the original that are not kept, counted by why, and lists the ones the new config writes its own way; the CLI needs the engine of 3.0.0~beta.13.482 and later
- feature (backup): `opensim restore FILE|ARCHIVE [--apply]` puts a backup back on this machine through the engine (`POST /setups/restores`): planned by default, written with --apply, the databases first, nothing this machine has replaced
- update (setup, regions, import): the reminders and the notes the engine gives as notices (code, params, detail) are shown by their detail, the older strings as they are
- feature (setup): `opensim simulator add --estate NAME`, the estate its regions join (made when none has that name); by default the estate of --owner; the plan says the estate of a new simulator
- fix (rest): `opensim rest --url ... --user ...` keeps OPENSIM_REST_PASSWORD when it runs as the system user; `opensim rest INSTANCE -- COMMAND` sends a command to the remote console of an instance, at the address and with the account of its config, its secrets masked
- feature (setup): `opensim simulator add --db-admin USER` (or OPENSIM_DB_ADMIN_USER) makes the database with an administrator of the database server, its password from OPENSIM_DB_ADMIN_PASS or asked, never on the command line; the plan of a setup file says its notes (a plan reserves nothing); the CLI needs the engine of 3.0.0~beta.13.478 and later
- feature (regions): `opensim region set GRID REGION [--roles ROLE,...] [--owner UUID]` gives a region these roles and only them, or another owner (the owner of its estate), through the engine, and says what is left to do (restart Robust)
- feature (setup): `opensim import FILE [--apply]` applies a setup file to a grid of this machine, `opensim region add GRID SIMULATOR --name NAME [...]` gives a region to a simulator (`--size`, `--roles`, `--location`, `--port`), `opensim simulator add GRID NAME --region NAME [...]` makes a simulator with its first region, all through the engine (`POST /setups/files`): planned, written with --apply, nothing started
- update (setup): the bottom of a form in dialog says that Enter goes to the next field and Tab reaches the buttons
- fix (setup): a screen of the engine without a text (the form of a simulator joining a grid) can be answered in dialog: dialog refuses an empty text above a form, a checklist or a menu at once (status 255, taken as Quit), a space is given instead
- feature (import): `opensim import --simulator FILE GRID [--name NAME] [--core DIR] [--apply]`, a simulator of another install joins a grid of this machine through the engine (`POST /setups/imports`): planned, written with --apply only
- feature (web): `opensim web <grid> set helpers|search|profile|guide|welcome|status|directory URL` sets the one setting of a page (and says when Robust must restart); `web show` lists each page with who serves it, the helpers under their base or the site (engine SitePages)
- fix: duplicate build-tools package in require and require-dev

### 3.0.0-beta.4

- magicoli/container-tools => ^0.1.0@alpha
- magicoli/opensim-engine => ^3.0@beta
- magicoli/bash-tools => ^1.0
- magicoli/build-tools => ^0.1.11

### 3.0.0-beta.2

- fix (containers): map OpenSim user to bind mount owner
- fix (install): request all OpenSim packages on every install
- feature (cli): restore console, grid, web and archive commands
- feature (cli): add backups and reviewable user ban plans
- magicoli/build-tools 0.1.9 => 0.1.11
- magicoli/container-tools dev-master 0ed55d9 => 0.1.0-alpha.2

### 3.0.0-beta.1

- feature (install): apply confirmed setup and transfer private inputs
- feature (setup): accept existing region files through the cli
- feature (setup): apply a private prepared configuration from the cli
- feature (install): prepare setup through the local engine before podman creation
- feature (setup): save collected answers before provisioning
- feature (cli): restore instance port reports
- feature (installer): configure apt sources
- feature (installer): prefill Podman setup from config
- feature (installer): install OpenSim in Podman
- feature (installer): support SSH installs
- fix (install): retain prepared database credentials through container setup
- fix (tests): report Podman connection failures in deployment checks
- fix (tests): validate persistent deployments across platforms
- fix (tests): load environment with project overrides
- doc: record validated setup port selection
- doc: track validated existing region staging and remaining migration work
- doc: record validated region move planning
- doc: extend container plan for existing regions and sqlite
- doc: record staged container setup plan
- doc (installer): document SSH installation
- doc (readme): list administrator access requirement
- doc (readme): simplify runtime requirements
- doc (contributing): add repository agent instructions
- doc (readme): update current features and install instructions
- refactor (tests): route container tests through container-tools
- test (install): prepare podman setup through the real engine
- test: isolate cli checks from the installed system layout
- test (tests): clarify command failure reporting
- update (installer): default Podman image to Ubuntu 26.04
- update (packaging): require podman-compose for cli
- dev swith to dev mode (sibling packkages from local sources, not suitable for release)

### 3.0.0-dev.1

Complete rewrite of opensim terminal tools, using new opensim-engine 3.x API

- new kickstart.sh: allow simple download and install all required packages
    - configurable sources : from git repo, local .deb package or official projet apt repo
    - configurable mode: full install or separate main packages, dotnet, opensim engine...
- rewrite opensim CLI, wrapper for all OpenSim controls:
    - status
    - start|stop|restart
    - console|screen
    - setup
- enhance opensim CLI: no more duplicate features, act as a wrapper, all features are provided globally by opensim-engine API, in a standadized way for all the apps of the ecosystem
- new extensive test suite
- work in progress, see README for upcoming features

**Enabled features**:

- `kickstart.sh`: automated installation script
    - apt official repo (linux, stable by default)
    - from local git clone
    - from local deb packages
    - multi-platform testing on podman containers
    - apt .deb package (tested on debian 12 and 13, ubuntu 24.04 and 26.04, should work on other debian variants)
    - zip (universal)
- status
- start [--simulators] [target...]
- stop|restart [--simulators] [now] [target...]
- console|screen <instance>
- setup
- install-dotnet install the .NET runtime OpenSim needs (as root)
