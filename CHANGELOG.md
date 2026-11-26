## Changelog

### Unreleased

- change (kickstart): a migration asks everything, reviews it, then runs the steps of the script; nothing done before Start
- fix (web): the sockets of the pools given to the group Apache runs as (its envvars); PHP-FPM restarted when a pool changes
- fix (kickstart): a migration planned as root, like its import; a retry once its grid is written starts it; one switch for the setup's UI
- fix (simulator): what is missing named, a refusal said once in words, never field paths; a plan ends Nothing written. Add --apply.
- change (web): api --install writes the pools of the API and of the helpers through the engine; OPENSIM_SETUP_UI kept by sudo
- fix (kickstart): the setup asked as lines, like the rest of the run; a website seen done when its site quotes its grid
- fix (setup): the live line says each step as [k/n] step: item · time, no spinner, no stray ~; options one space apart
- change (setup): beside Apache, the line of the website in its sites asked in the review, before Start
- change (setup): the review changed line by line, then ? Start? [Y/n]; one question asked as one; the run as one live line
- change (kickstart): no Create them? for the SQL accounts; a rerun upgrades the packages of the suite alone
- change (kickstart): with Apache, the line of the website in its sites asked with the other questions; --edit-vhosts when nobody is there
- change (web): site --install beside Apache with the yes to one line in its sites (asked, or --edit-vhosts); site --vhosts
- change (status): a Robust whose services did not load since its start is not up, and its services are said
- fix (kickstart): a rerun of the fresh path installs a website a failure left, never sets up another grid
- new (web): GRID site --install puts the Quick Start website of a grid beside Caddy or Apache; api apache --install
- change (kickstart): the fresh path installs the website after the setup, then its summary; a rerun redoes a website step left
- fix (web): api caddy --install writes as root, its text made as the account of the instances; a write refused stops it
- fix (kickstart): local packages said in one line, dpkg-scanpackages in the log
- fix (web): api caddy --install checks the engine API answers, reloads without systemd too; api alone is for Caddy
- change (kickstart): a migration checks, asks everything, then one Start; name, website, 3D map; a short summary; a rerun resumes
- new (web): api caddy --install writes the pool and the local listener of the engine API, beside the sites; import --grid-name
- change (setup): the options on one line, kept with Enter; status without the 3D map advice; one summary, the setup's
- fix (setup): false and 0 of --config kept; start, stop, restart of a grid with its simulators (--robust alone)
- change (kickstart): questions always shown, one live line with counters, logs in a file; migrates instead of printing commands
- new (modules): opensim module enable|disable NAME; kickstart --with MODULE installs its package for each core, enabled
- new (import): --accounts puts each account in its groups, with a role; --create-groups makes the missing ones
- change (import): --accounts takes its format from the extension (.csv, .json, .yaml); each account told with its line
- new (status): the simulators left on the simple map, and what gives them the 3D one (Warp3D)
- new (setup): the fields of a form with choices and help, as a list of fields in dialog (the web services screen)
- new (web): opensim web GRID paths --outside /PREFIX, the addresses of the helpers outside the path of the mini site
- new (web): opensim web GRID snippet routes the addresses the grid names on its site wherever they are (the paths of an install of before)
- new (web): opensim web GRID snippet ... --prefix /PATH, the helpers under the path of a block of its own (the mini site under /opensim)
- doc (install): w4os-helpers comes with opensim-kit as a recommended package, not inside w4os-site
- fix (packaging): w4os-cli needs w4os-engine 3.0.0~beta.13+502 or later (the avatars of opensim status)
- new (status): the avatars in world, never a NPC: a column by instance that runs, the total in the last line
- fix (import): says the grid info values made ASCII (OpenSim sends no other), in place and migrated
- new (status): a Robust whose grid info the viewers refuse (not UTF-8, not well-formed XML) is said
- fix (kickstart): installs the .NET runtime the cores target (8 for 0.9.3), after them, never 10 alone
- new (status): an instance on a .NET major its core does not target is said, with its fix
- fix (install-dotnet): without MAJOR, installs the runtime each installed core targets
- fix (import): a switch names the instances still starting, not answering yet, and fails
- fix (status): a module installed but not configured (Gloebit without its key) is said, with the simulators it is off for
- fix (import): sudo opensim import --robust plans as root, as the apply moves its data
- fix (kickstart): --restart finds the old instances by their -inifile, quoted, relative or a link, resolved
- fix (import): a switch names each instance it did not start and why, and fails
- fix (kickstart): --in-place --restart stops a Robust by the file it runs (REST console, no screen) and checks the grid runs
- fix (web): web GRID api uses the port of the grid, ports lists it as local, never published nor opened
- new (import): --copy-data; a migration moves the data folders of the old install, named in the plan, run as root when needed
- new (region): region remove takes a region out of its stopped simulator, for --existing to give it to another
- fix (import): a switch alone says what it did, not the plan of the writing done before
- fix (import): a switch that changes the account of the instances ends with the service restarted, its grid under that account
- fix (kickstart): Debian 12 gets the website of a grid like the other systems (Grav 1.7 on PHP 8.2)
- fix (tests): a check keeps the brace glob flag out of the PHP code, which musl and Alpine lack
- fix (import): an install taken in place or migrated keeps its owner and web account; the service is made to run as them
- fix (status): a simulator that runs and does not answer is marked [not answering], counted in the summary
- new (setup): Show passwords in the review (a button in dialog, s in plain text), opensim setup --show-passwords
- fix (kickstart): the SQL accounts shown before anything changes (exists, made, left alone; where each password comes from, masked), --show-passwords
- new (kickstart): beside an install of before the kit, --in-place or --migrate is asked; its own start set aside, its grid registered in place, --restart
- fix (import): --core goes with --in-place too
- fix (kickstart): an SQL account of the name on any host is left as it is, never shadowed by one for localhost
- doc: the installer from charm-dev until the release; Debian 12 and 13, Ubuntu 24.04 and 26.04, the Debian 12 website worked on
- fix (kickstart): on Debian 12 (PHP 8.2) it says the website needs PHP 8.3 and installs the grid without it
- fix (kickstart): a package gone from the repository while it installs (404) is installed once more after apt-get update
- fix (kickstart): --cleanup takes out the web server links and imports of what it removes, before they stop the server
- fix (service): opensim.service runs the launch master, starts on install, and stops every instance in order
- fix (setup files): once written, the report says what started and what was loaded, and no empty Then:
- fix (setup files): the plan of region add, simulator add and import says its problems
- new (regions): setup, simulator add and region add take --oar FILE or --dump FILE, what the region is loaded with
- new (regions): setup, simulator add and region add take --existing, a region the grid has already taken over
- doc: the installer is fetched from the repository (raw.githubusercontent.com/way4os/w4os-cli/master/kickstart.sh), no site alias in the docs
- fix (kickstart): the APT sources are updated where they stand, commented or not, and added at the end only when missing: the order and the comments of the user stay
- update (kickstart): `charm stable` is always the source of the releases; `--unstable` adds the beta releases (charm unstable), `--testing` adds charm-tests and `--unstable`; one script, no kickstart-dev.sh
- new (address): the plan shows the addresses the databases keep, each column with its rows
- new (status): a running Robust that cannot read its database is marked [no database], and counted
- new (address): opensim address GRID --host HOST --port PORT --site URL changes the address of a grid in every file of it, through the engine (POST /grids/{grid}/address): each line that would change first, --apply writes them and says what to restart
- update (git): .gitignore is the projects' template (macOS, editors, AI files, config, generated content, data) with this project's own rules after it
- fix (packaging): the libraries and /usr/bin/opensim are links in the package whatever the machine that builds it has (nfpm took the mode of an existing target)
- update (rename): the command line is w4os-cli, its command still opensim: the package w4os-cli in /usr/share/w4os-cli (opensim-cli an empty package that brings it), on w4os-engine and its API command w4os-api, the config of the suite /etc/w4os/w4os.conf, the repository way4os/w4os-cli, the composer name w4os/w4os-cli
- feature (import): `opensim import --robust FILE --in-place` runs the grid of another install where it is, its section of the config of the suite written alone; `--forget` removes it
- doc: CONTAINERS.md, suggestions for Podman and Docker, not supported yet
- new: `opensim oar pack|info|check|unpack`, the archives of regions of the caller
- update: the bash completion knows every command, the grids, the disabled instances, the options of import, save, load, backup and oar
- new (settings): `opensim settings --set` says when the grid or the simulators must restart
- new: `opensim --version`, and with -v the versions of everything that matters on the machine
- feature (kickstart): `--testing` (the test builds), `--unstable` (the beta versions), `--tools` (the command line and the engine alone, light); the full install is opensim-kit, with the website of a grid
- change (packaging): dialog and podman-compose are recommended, not required: a light install of the tools (--no-install-recommends)
- feature (import): `opensim import --accounts FILE --robust ROBUST_INI` makes the accounts in a grid this install does not manage, as the caller
- feature (import): `opensim import --robust FILE [--simulator FILE...]` migrates the grid of another install, planned, applied disabled, then `--switch` once the old Robust is stopped
- feature (import): `opensim import --accounts FILE GRID` makes the accounts of a list (CSV, JSON, YAML), the result with the passwords made kept for the caller only
- feature (api): `opensim api [METHOD] PATH [name=value...]` asks the engine API of this machine, as the commands and the README said
- fix: the options after a command are its own (`opensim save iar -h URL -v`); `-v` and `-q` reach the engine; OPENSIM_IAR_PASSWORD, OPENSIM_CONF, DEBUG and QUIET go through sudo
- fix (packaging): rest-php comes from its package, not from the vendor folder; copyright of the package
- remove (kickstart): the start_setup that sourced a frontend no longer there
- feature (settings): `opensim settings GRID [PAGE] [--set NAME=VALUE]` shows and sets the settings pages of a grid
- feature (posts): `opensim posts GRID` and `opensim posts delete GRID ID` list and delete the posts of a grid
- fix (packaging): opensim-cli now conflicts with and replaces opensim-tools
- update (import): `--grid-settings` shows every file it lays, including OpenSim.ini and Gloebit.ini
- feature (import): `opensim import --grid-settings FILE GRID [--apply]` imports the option settings of another install's grid
- feature (api): `opensim api-key create LABEL | list | revoke LABEL|ID` manages the engine API keys
- feature (import): the plan shows the source backup and script state; `--no-scripts` skips scripts; `opensim backup --simulator FILE [GRID]` added
- feature (web): `opensim web GRID api caddy|nginx|apache` prints the config serving the engine API to local sites
- update (import): a replaced folder of the old install is shown with the folder that replaces it
- feature (import): `opensim import --simulator FILE --simulator FILE... GRID` plans several simulators into one grid, checked together
- feature (backup): `opensim restore FILE|ARCHIVE [--apply]` restores a backup through the engine, planned by default
- update (setup, regions, import): engine notices are shown by their detail
- feature (setup): `opensim simulator add --estate NAME` sets the estate a simulator's regions join
- fix (rest): `opensim rest` keeps `OPENSIM_REST_PASSWORD` as the system user; `opensim rest INSTANCE -- COMMAND` sends a console command
- feature (setup): `opensim simulator add --db-admin USER` creates the database with a database administrator account
- feature (regions): `opensim region set GRID REGION [--roles ROLE,...] [--owner UUID]` sets a region's roles and owner
- feature (setup): `opensim import FILE`, `opensim region add` and `opensim simulator add` apply setup files and add regions and simulators
- update (setup): the form footer says Enter goes to the next field and Tab reaches the buttons
- fix (setup): dialog no longer fails on an engine screen without a text
- feature (import): `opensim import --simulator FILE GRID [--name NAME] [--core DIR] [--apply]` imports a simulator from another install
- feature (web): `opensim web <grid> set helpers|search|profile|guide|welcome|status|directory URL` sets a page setting; `web show` lists page servers
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
