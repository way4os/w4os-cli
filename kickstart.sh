#!/usr/bin/env bash

# OpenSim Install script: installs OpenSim and optionally starts `opensim setup`.
#
#   From the web (Debian or Ubuntu): download it, then run it with its options
#     curl -fsSL -O https://raw.githubusercontent.com/way4os/w4os-cli/charm-dev/kickstart.sh
#     chmod +x kickstart.sh && sudo ./kickstart.sh --setup
#   or in one line: curl -fsSL https://raw.githubusercontent.com/way4os/w4os-cli/charm-dev/kickstart.sh | sudo bash -s -- --setup
#
#   Or from a clone of the repository:
#     git clone https://github.com/way4os/w4os-cli.git && cd w4os-cli && ./kickstart.sh
#     ./kickstart.sh --remote root@server --setup
#     ./kickstart.sh --podman
#
#   Or with the packages only:  sudo apt install opensim-kit && opensim setup
#
# From a clone it runs the tools of the clone; its PHP libraries come from Composer.
#
# Setup is not started unless requested with --setup or RUN_SETUP=yes.
# Options:  -y, --yes             do not ask before installing
#           --edit-vhosts         with Apache, the line of the website may be added to the sites serving its host, unasked
#           --unstable            include the unstable (beta) versions of the packages
#           --testing             include the test builds (charm-tests), and --unstable
#           --tools               only the command line and the engine, light (no core, no database, no website): to work on
#                                 a grid installed otherwise (opensim import --accounts FILE --robust ROBUST_INI)
#           --cleanup             remove an existing OpenSim installation first (asks for confirmation)
#           --in-place            beside a pre-existing install (/opt/opensim): run its grids where they are, under the
#                                 opensim service; its own start (its cron) set aside, reversibly
#           --migrate             beside a pre-existing install: its grids migrated into the layout of w4os, its own start
#                                 set aside, the old install kept
#           --new                 beside a pre-existing install: a new grid, the old install left as it is
#           --restart             with --in-place: stop its running instances and start them again under the service
#           --show-passwords      show the passwords of the database users in the review (masked by default)
#           --setup               run `opensim setup` after the full or OpenSim install
#           --dependencies        install quick-install's own dependencies
#           --mariadb | --mysql   install/configure the requested database server
#           --dotnet              install the .NET runtime the installed cores target (and libgdiplus)
#           --opensim             install OpenSimulator and its management packages (or prepare the clone)
#           --with MODULE         an OpenSimulator module w4os does not install (gloebit): its package for each core, enabled
#           --remote SSH_TARGET   run this installation on a server over SSH
#           --podman              install in a persistent Podman container
#           --connection NAME     use a configured Podman connection; local|none forces local Podman
#           --image IMAGE         container image (default: $OPENSIM_CONTAINER_IMAGE or Ubuntu 26.04)
#           --config FILE         quick setup answers in JSON
#           --region-config FILE  stage an existing region from its Region.ini
# Environment: APT_SOURCE_DIR=folder         install local packages (*.deb) from a folder
#             APT_SOURCE=...                  complete primary APT source line (default: charm stable)
#             APT_SOURCE_TESTS=...            optional additional APT source line
#             OPENSIM_KIT_APT_DIST=...         legacy distribution override (charm-tests: as --testing)
#             UNSTABLE=yes                     as --unstable
#             OPENSIM_KIT_APT_COMPONENT=...    legacy component override
#             OPENSIM_CONTAINER_IMAGE=IMAGE    default image for --podman (Ubuntu 26.04)

set -euo pipefail

apt_source_uri_index() {
	local source=$1 index
	local -a fields
	read -r -a fields <<<"$source"
	for ((index = 1; index < ${#fields[@]}; index++)); do
		case "${fields[$index]}" in
		http://* | https://* | ftp://* | file:* | cdrom:*)
			printf '%s\n' "$index"
			return 0
			;;
		esac
	done
	return 1
}

# How the setup asks its questions: its panels of dialog at a terminal when dialog is installed, else lines (OPENSIM_SETUP_UI=plain
# or dialog chooses); the run itself, and these first questions, are always lines
SETUP_UI=${OPENSIM_SETUP_UI:-}

INSTALLER_HOME=${HOME:-/root}
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && command -v getent >/dev/null 2>&1; then
	INSTALLER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
OPENSIM_RC_PATH=${OPENSIM_RC:-$INSTALLER_HOME/.opensimrc}
OPENSIM_KIT_APT_DIST_WAS_SET=${OPENSIM_KIT_APT_DIST+x}
OPENSIM_KIT_APT_DIST_FROM_ENV=${OPENSIM_KIT_APT_DIST:-}
OPENSIM_KIT_APT_COMPONENT_WAS_SET=${OPENSIM_KIT_APT_COMPONENT+x}
OPENSIM_KIT_APT_COMPONENT_FROM_ENV=${OPENSIM_KIT_APT_COMPONENT:-}
APT_SOURCE_WAS_SET=${APT_SOURCE+x}
APT_SOURCE_FROM_ENV=${APT_SOURCE:-}
APT_SOURCE_TESTS_WAS_SET=${APT_SOURCE_TESTS+x}
APT_SOURCE_TESTS_FROM_ENV=${APT_SOURCE_TESTS:-}
APT_SOURCE_DIR_WAS_SET=${APT_SOURCE_DIR+x}
APT_SOURCE_DIR_FROM_ENV=${APT_SOURCE_DIR:-}
CONTAINER_CONNECTION_WAS_SET=${CONTAINER_CONNECTION+x}
CONTAINER_CONNECTION_FROM_ENV=${CONTAINER_CONNECTION:-}
CONTAINER_HOST_WAS_SET=${CONTAINER_HOST+x}
CONTAINER_HOST_FROM_ENV=${CONTAINER_HOST:-}
OPENSIM_CONTAINER_IMAGE_WAS_SET=${OPENSIM_CONTAINER_IMAGE+x}
OPENSIM_CONTAINER_IMAGE_FROM_ENV=${OPENSIM_CONTAINER_IMAGE:-}

SCRIPT_DIR=
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
	SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
for file in "$SCRIPT_DIR/.env" "$OPENSIM_RC_PATH"; do
	# shellcheck disable=SC1090
	[[ -n "$file" && -r "$file" ]] && source "$file"
done
# Podman installs are also used by the compatibility suite. Let its ignored
# config add test repositories, with explicit caller environment taking priority.
if [[ " ${*:-} " == *" --podman "* && -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/tests/.env" ]]; then
	# shellcheck disable=SC1090
	source "$SCRIPT_DIR/tests/.env"
fi
if [[ "$CONTAINER_CONNECTION_WAS_SET" == x ]]; then CONTAINER_CONNECTION=$CONTAINER_CONNECTION_FROM_ENV; fi
if [[ "$CONTAINER_HOST_WAS_SET" == x ]]; then CONTAINER_HOST=$CONTAINER_HOST_FROM_ENV; fi
if [[ "$OPENSIM_CONTAINER_IMAGE_WAS_SET" == x ]]; then OPENSIM_CONTAINER_IMAGE=$OPENSIM_CONTAINER_IMAGE_FROM_ENV; fi
unset CONTAINER_CONNECTION_WAS_SET CONTAINER_CONNECTION_FROM_ENV CONTAINER_HOST_WAS_SET CONTAINER_HOST_FROM_ENV
unset OPENSIM_CONTAINER_IMAGE_WAS_SET OPENSIM_CONTAINER_IMAGE_FROM_ENV
[[ ! ${CONTAINER_CONNECTION+x} ]] || export CONTAINER_CONNECTION
[[ ! ${CONTAINER_HOST+x} ]] || export CONTAINER_HOST

if [[ "$OPENSIM_KIT_APT_DIST_WAS_SET" == x ]]; then
	OPENSIM_KIT_APT_DIST=$OPENSIM_KIT_APT_DIST_FROM_ENV
fi
if [[ "$OPENSIM_KIT_APT_COMPONENT_WAS_SET" == x ]]; then
	OPENSIM_KIT_APT_COMPONENT=$OPENSIM_KIT_APT_COMPONENT_FROM_ENV
fi
if [[ "$APT_SOURCE_WAS_SET" == x ]]; then APT_SOURCE=$APT_SOURCE_FROM_ENV; fi
if [[ "$APT_SOURCE_TESTS_WAS_SET" == x ]]; then APT_SOURCE_TESTS=$APT_SOURCE_TESTS_FROM_ENV; fi
if [[ "$APT_SOURCE_DIR_WAS_SET" == x ]]; then APT_SOURCE_DIR=$APT_SOURCE_DIR_FROM_ENV; fi
unset OPENSIM_KIT_APT_DIST_WAS_SET OPENSIM_KIT_APT_DIST_FROM_ENV
unset OPENSIM_KIT_APT_COMPONENT_WAS_SET OPENSIM_KIT_APT_COMPONENT_FROM_ENV
unset APT_SOURCE_WAS_SET APT_SOURCE_FROM_ENV APT_SOURCE_TESTS_WAS_SET APT_SOURCE_TESTS_FROM_ENV
unset APT_SOURCE_DIR_WAS_SET APT_SOURCE_DIR_FROM_ENV

MAGIIIC_KEY=https://apt.magiiic.com/magiiic-packaging.asc
APT_SOURCE_FILE=${APT_SOURCE_FILE:-/etc/apt/sources.list.d/magiiic.list}
OPENSIM_KIT_APT_DIST=${OPENSIM_KIT_APT_DIST:-charm}
UNSTABLE=${UNSTABLE:-}
# The sources and the packages, from the distribution and the options (run again once the options are read: --testing)
plan_packages() {
# The test builds are on top of the unstable versions
[[ "$OPENSIM_KIT_APT_DIST" == charm-tests ]] && UNSTABLE=yes
if [[ -z "${OPENSIM_KIT_APT_COMPONENT:-}" ]]; then
	if [[ "$OPENSIM_KIT_APT_DIST" == charm-tests ]]; then
		OPENSIM_KIT_APT_COMPONENT=dev
	else
		OPENSIM_KIT_APT_COMPONENT=stable
	fi
fi
APT_REPOSITORIES=()

if [[ -n "${APT_SOURCE:-}" ]]; then
	APT_REPOSITORIES+=("$APT_SOURCE")
	if [[ -n "${APT_SOURCE_TESTS:-}" ]]; then APT_REPOSITORIES+=("$APT_SOURCE_TESTS"); fi
else
	# The releases are always there; the other channels come on top of them
	if [[ "$OPENSIM_KIT_APT_DIST" == charm-tests ]]; then
		APT_REPOSITORIES+=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable${UNSTABLE:+ unstable}")
		APT_REPOSITORIES+=("deb [trusted=yes] https://apt.magiiic.com charm-tests $OPENSIM_KIT_APT_COMPONENT")
	else
		APT_REPOSITORIES+=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com $OPENSIM_KIT_APT_DIST $OPENSIM_KIT_APT_COMPONENT${UNSTABLE:+ unstable}")
	fi
fi
for repository in "${APT_REPOSITORIES[@]}"; do
	read -r -a fields <<<"$repository"
	if [[ "${fields[0]:-}" != deb && "${fields[0]:-}" != deb-src ]] || ! uri_index=$(apt_source_uri_index "$repository") || ((${#fields[@]} <= uri_index + 1)); then
		printf 'quick-install: [ERROR] invalid APT source line: %s\n' "$repository" >&2
		exit 1
	fi
done
# What the tools need on a machine that does not have the packages (a clone): the dependencies of the package w4os-cli
PHP_PACKAGES=(php-cli php-curl php-intl php-mbstring php-mysql php-xml)
# opensim-kit: the command line, the engine, the website of a grid (w4os-site), its helpers (w4os-helpers, recommended: installed
# here, as nothing below leaves the recommends out), the latest core and its essential modules, a database server
OPENSIM_PACKAGES=(
	opensim-kit
	libsqlite3-0 mariadb-server
	php-cli php-curl php-intl php-mbstring php-mysql php-xml
	composer git unzip screen
	openssh-server
	libgdiplus
)
}
plan_packages

APT_SOURCE_DIR=${APT_SOURCE_DIR:-}
ASSUME_YES=${ASSUME_YES:-}
RUN_SETUP=${RUN_SETUP:-}
SHOW_PASSWORDS=${SHOW_PASSWORDS:-}
LEGACY_MODE=${LEGACY_MODE:-}
LEGACY_RESTART=${LEGACY_RESTART:-}
# The log of the long steps (install_log())
INSTALL_LOG=${INSTALL_LOG:-}
# An install of before the kit (opensim-debian): its folder, and the cron that starts its instances
LEGACY_ROOT=${LEGACY_ROOT:-/opt/opensim}
LEGACY_CRON=${LEGACY_CRON:-/etc/cron.hourly/opensim}
DPKG_CONFIGURED=no
APT_UPDATED=no
PACKAGE_SOURCES_READY=no
INSTALL_PHASE=all
DATABASE_CHOICE=mariadb
PHASE_SELECTED=no
RUN_CLEANUP=no
REMOTE_TARGET=
REMOTE_ARGS=()
PODMAN_MODE=no
PODMAN_CONNECTION=
PODMAN_CONNECTION_SELECTED=no
PODMAN_FORCE_LOCAL=no
PODMAN_IMAGE=${OPENSIM_CONTAINER_IMAGE:-docker.io/library/ubuntu:26.04}
PODMAN_IMAGE_SELECTED=no
PODMAN_INSTALL_ARGS=()
# The modules asked with --with (gloebit): installed for each core with the kit, enabled for the install
WITH_MODULES=()
# Where the packages put the cores
OPENSIM_CORES_ROOT=${OPENSIM_CORES_ROOT:-/usr/share/opensim}
CONTAINER_TOOLS_CLI_SELECTED=
SETUP_CLI_SELECTED=
SETUP_CONFIG_FILE=${OPENSIM_SETUP_CONFIG_FILE:-${OPENSIM_SETUP_CONFIG:-}}
REGION_CONFIG_FILE=
SETUP_CONFIG_TEMP=
SETUP_PREFILL_TEMP=
SETUP_RC_TEMP=
PODMAN_CONTAINER_NAME=

# === Define helper functions first ===

say() {
	live_clear
	printf '%s\n' "$*"
}
log() {
	[ -n "${DEBUG}" ] || return 0
	[ "$DEBUG" = "yes" ] || return 0
	say "$PGM: [DEBUG] $*" >&2
}
error() {
	say "$PGM: [ERROR] $*" >&2
}
die() {
	error "$*"
	exit 1
}

# Where the person answers and sees the questions: the terminal (KICKSTART_TTY_IN and KICKSTART_TTY_OUT for the tests)
TTY_IN=${KICKSTART_TTY_IN:-/dev/tty}
TTY_OUT=${KICKSTART_TTY_OUT:-/dev/tty}

# Whether a person can answer at the terminal (not --yes, a terminal that opens: none for ssh without a tty, cron, a pipe alone)
person_here() {
	[[ -z "$ASSUME_YES" ]] || return 1
	{ : <"$TTY_IN" >>"$TTY_OUT"; } 2>/dev/null
}

# The live line, cleared before anything else is written (defined before say(), which uses it)
LIVE=
[[ -t 1 ]] && LIVE=yes
live() {
	[[ -z "$LIVE" ]] || printf '\r\033[K» %s' "$*"
}
live_clear() {
	[[ -z "$LIVE" ]] || printf '\r\033[K'
}

# A question with its letters, the default first (its letter in capitals in the prompt): the letter answered in CHOICE, the default
# when Enter is pressed or nobody can answer. The prompt is written to the terminal, always shown
choose() { # "question (M/i/n/a):" letters
	local question=$1 letters default answer
	letters=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
	default=${letters:0:1}
	CHOICE=$default
	person_here || return 0
	live_clear
	# Opened once: the answers follow each other (a file of answers in the tests)
	[[ -n "${TTY_OPEN:-}" ]] || { exec 8<"$TTY_IN" && TTY_OPEN=yes; }
	while :; do
		printf '? %s ' "$question" >>"$TTY_OUT"
		IFS= read -r -u 8 answer || return 0
		answer=$(printf '%s' "${answer:0:1}" | tr '[:upper:]' '[:lower:]')
		[[ -n "$answer" ]] || answer=$default
		[[ "$letters" == *"$answer"* ]] && CHOICE=$answer && return 0
	done
}

# A question answered yes or no, yes by default (ask) or no by default (ask_no)
ask() { # "question"
	choose "$1 [Y/n]" yn
	[[ "$CHOICE" == y ]]
}
ask_no() { # "question": no by default
	choose "$1 [y/N]" ny
	[[ "$CHOICE" == y ]]
}

done_line() {
	live_clear
	say "✓ $*"
}
failed_line() {
	live_clear
	say "✗ $*"
}

# The time since a moment (SECONDS), as m:ss
elapsed() { # started
	local seconds=$((SECONDS - $1))
	printf '%d:%02d' $((seconds / 60)) $((seconds % 60))
}

# Where the long steps write what they say (apt, dotnet, the import), shown on an error: made once by the main shell (called there
# without $(...), which would keep it), in /var/log/opensim as root, else in the temporary folder of the person
install_log() {
	if [[ -z "$INSTALL_LOG" ]]; then
		local folder=${TMPDIR:-/tmp}
		[[ $(id -u) -ne 0 ]] || { mkdir -p /var/log/opensim 2>/dev/null && folder=/var/log/opensim; }
		INSTALL_LOG=$folder/install-$(date +%Y%m%d-%H%M%S).log
		{ : >>"$INSTALL_LOG" && chmod 600 "$INSTALL_LOG"; } 2>/dev/null || INSTALL_LOG=$(mktemp)
	fi
	printf '%s\n' "$INSTALL_LOG"
}

# A long step: the command writes into the log while the live line says the step, what it is at (COUNTER, a function that prints
# it: 12/27 opensim-0.9.3.0) and the time; a failure says the log and asks to retry or to stop
run_step() { # label counter|- command... (RUN_STEP_SKIP: the step can be skipped)
	local label=$1 counter=$2 started pid status at log
	shift 2
	log=$(install_log)
	while :; do
		started=$SECONDS
		"$@" >>"$log" 2>&1 &
		pid=$!
		while kill -0 "$pid" 2>/dev/null; do
			at=
			[[ "$counter" == - ]] || at=$("$counter" 2>/dev/null) || at=
			# The time spent shows it goes on; a counter, when there is one, says how far
			live "$label${at:+${label:+: }$at} · $(elapsed "$started")"
			sleep 0.5
		done
		status=0
		wait "$pid" || status=$?
		((status != 0)) || return 0
		failed_line "${label:-$at}"
		say "  Log: $log"
		person_here || return "$status"
		# A step the run can go on without (RUN_STEP_SKIP): skipped, or the run stopped
		if [[ -n "${RUN_STEP_SKIP:-}" ]]; then
			choose "[R]etry  [S]kip  [A]bort (R/s/a):" rsa
		else
			choose "[R]etry  [A]bort (R/a):" ra
		fi
		[[ "$CHOICE" == r ]] || return "$status"
	done
}

as_root() {
	if [[ $(id -u) -eq 0 ]]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo --preserve-env=${PRESERVE_ENV:-} "$@"
	else
		die "this needs administrator rights: run it as root, or install sudo"
	fi
}

run_remote_install() (
	local target=$1 source_script=${BASH_SOURCE[0]} remote_dir remote_script command quoted argument
	local -a arguments=()
	shift
	[[ "$target" != -* ]] || die "--remote requires an SSH target, not another option"
	[[ -f "$source_script" ]] || die "--remote requires kickstart.sh to be run from a local file"
	command -v scp >/dev/null 2>&1 || die "scp is required for --remote"
	command -v ssh >/dev/null 2>&1 || die "ssh is required for --remote"
	[[ -z "$SETUP_CONFIG_FILE" || -r "$SETUP_CONFIG_FILE" ]] || die "cannot read setup config: $SETUP_CONFIG_FILE"
	[[ -z "$REGION_CONFIG_FILE" || -r "$REGION_CONFIG_FILE" ]] || die "cannot read region config: $REGION_CONFIG_FILE"
	source_script=$(cd -- "$(dirname -- "$source_script")" && pwd)/$(basename -- "$source_script")
	remote_dir=$(ssh "$target" 'umask 077; mktemp -d /tmp/quick-install.XXXXXXXX') || die "could not create a private installation directory on $target"
	[[ "$remote_dir" =~ ^/tmp/quick-install\.[a-zA-Z0-9.-]+$ ]] || die "invalid remote installation directory"
	trap 'ssh "$target" "rm -rf -- $remote_dir" >/dev/null 2>&1 || true' EXIT
	remote_script=$remote_dir/kickstart.sh
	scp -- "$source_script" "$target:$remote_script" || die "could not copy kickstart.sh to $target"
	while (($#)); do
		argument=$1
		shift
		case "$argument" in
		--config | --region-config) shift ;;
		--config=* | --region-config=*) ;;
		*) arguments+=("$argument") ;;
		esac
	done
	if [[ -n "$SETUP_CONFIG_FILE" ]]; then
		scp -- "$SETUP_CONFIG_FILE" "$target:$remote_dir/setup.json" || die "could not copy setup config to $target"
		arguments+=(--config "$remote_dir/setup.json")
	fi
	if [[ -n "$REGION_CONFIG_FILE" ]]; then
		scp -- "$REGION_CONFIG_FILE" "$target:$remote_dir/Region.ini" || die "could not copy region config to $target"
		arguments+=(--region-config "$remote_dir/Region.ini")
	fi
	printf -v command 'env APT_SOURCE=%q APT_SOURCE_TESTS=%q bash %q' "${APT_SOURCE:-}" "${APT_SOURCE_TESTS:-}" "$remote_script"
	for quoted in "${arguments[@]}"; do
		printf -v quoted ' %q' "$quoted"
		command+=$quoted
	done
	ssh -t "$target" "$command"
)

write_systemd_context() {
	local directory=$1 base=$2
	printf 'FROM %s\n' "$base" >"$directory/Containerfile"
	cat >>"$directory/Containerfile" <<-'CONTAINERFILE'
		COPY setup-system.sh /usr/local/sbin/setup-system
		RUN chmod 755 /usr/local/sbin/setup-system && /usr/local/sbin/setup-system
		COPY ssh-host-keys.service /etc/systemd/system/ssh-host-keys.service
		RUN systemctl enable ssh-host-keys.service ssh.service
		STOPSIGNAL SIGRTMIN+3
		CMD ["/sbin/init"]
	CONTAINERFILE
	cat >"$directory/setup-system.sh" <<-'SETUP_SYSTEM'
		#!/usr/bin/env bash
		set -euo pipefail

		export DEBIAN_FRONTEND=noninteractive

		apt-get update
		apt-get install -y --no-install-recommends \
			systemd \
			systemd-sysv \
			dbus \
			openssh-server \
			curl \
			wget \
			ca-certificates \
			iproute2 \
			iputils-ping \
			procps
		apt-get clean
		# Do not keep build-time APT indexes in the reusable image.
		rm -rf /var/lib/apt/lists/*

		# These identities must be created independently when each container boots.
		rm -f /etc/machine-id /var/lib/dbus/machine-id /etc/ssh/ssh_host_*
		touch /etc/machine-id
	SETUP_SYSTEM
	cat >"$directory/ssh-host-keys.service" <<-'SERVICE'
		[Unit]
		Description=Generate SSH host keys
		Before=ssh.service
		[Service]
		Type=oneshot
		ExecStart=/usr/bin/ssh-keygen -A
		RemainAfterExit=yes
		[Install]
		WantedBy=multi-user.target
	SERVICE
}

build_systemd_image() (
	local base=$1 context image checksum slug
	context=$(mktemp -d) || return 1
	trap 'rm -rf "$context"' EXIT
	write_systemd_context "$context" "$base" || return $?
	checksum=$(systemd_image_checksum "$context") || return $?
	slug=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_.-]+/-/g')
	image="localhost/opensim-server:${slug:0:80}-$checksum"
	run_container_tool build --file "$context/Containerfile" --tag "$image" "$context" >&2 || return $?
	printf '%s\n' "$image"
)

systemd_image_checksum() {
	cksum "$1/Containerfile" "$1/setup-system.sh" "$1/ssh-host-keys.service" | cksum | awk '{print $1}'
}

run_podman_install() {
	local source_script=${BASH_SOURCE[0]} source_dir output name server_image status=0 debs_in_container= mapping mapping_output
	local -a environment=() publish_options=() mappings=()
	bootstrap_podman_manager || die "could not install the local OpenSim manager"
	if [[ -n "${CONTAINER_TOOLS_CLI:-}" ]]; then
		CONTAINER_TOOLS_CLI_SELECTED=$CONTAINER_TOOLS_CLI
	else
		source_dir=$(cd -- "$(dirname -- "$source_script")" && pwd)
		if [[ -x "$source_dir/vendor/bin/container-tools" ]]; then
			CONTAINER_TOOLS_CLI_SELECTED=$source_dir/vendor/bin/container-tools
		elif [[ -x /usr/share/w4os-cli/vendor/bin/container-tools ]]; then
			CONTAINER_TOOLS_CLI_SELECTED=/usr/share/w4os-cli/vendor/bin/container-tools
		elif command -v container-tools >/dev/null 2>&1; then
			CONTAINER_TOOLS_CLI_SELECTED=$(command -v container-tools)
		else
			die "container-tools is required for --podman"
		fi
	fi
	[[ -x "$CONTAINER_TOOLS_CLI_SELECTED" ]] || die "container-tools is not executable: $CONTAINER_TOOLS_CLI_SELECTED"
	prepare_podman_setup_config
	[[ -f "$source_script" ]] || die "--podman requires kickstart.sh to be run from a local file"
	server_image=$(build_systemd_image "$PODMAN_IMAGE") || die "could not build the systemd server image"
	validate_prepared_podman_ports "$SETUP_CONFIG_FILE"
	mapping_output=$(prepared_podman_publish_mappings "$SETUP_CONFIG_FILE") || die "the engine did not provide valid port bindings for the prepared setup"
	mapfile -t mappings <<<"$mapping_output"
	((${#mappings[@]} > 0)) || die "the engine did not provide port bindings for the prepared setup"
	for mapping in "${mappings[@]}"; do
		publish_options+=(--publish "$mapping")
	done
	output=$(run_container_tool create --name "$PODMAN_CONTAINER_NAME" --image "$server_image" --no-publish-defaults "${publish_options[@]}") || status=$?
	printf '%s\n' "$output"
	((status == 0)) || die "could not create the Podman container"
	name=$(sed -n 's/^Name: //p' <<<"$output" | tail -n 1)
	[[ -n "$name" ]] || die "container-tools did not report the created container name"
	run_container_tool wait-ready "$name" -- sh -c 'test "$(cat /proc/1/comm)" = systemd && systemctl is-active multi-user.target && systemctl is-active ssh.service' || die "systemd services did not become ready in container $name"
	say "Install OpenSim in container $name"
	run_container_tool cp "$source_script" "$name:/tmp/kickstart.sh" || die "could not copy kickstart.sh to container $name"
	run_container_tool cp "$SETUP_CONFIG_FILE" "$name:/tmp/opensim-setup.json" || die "could not copy setup config to container $name"
	SETUP_RC_TEMP=$(mktemp "$TMP.rc.XXXXXXXX") || die "could not create a private database configuration"
	jq -r '.answers | {
		OPENSIM_DB_HOST: .database_host,
		OPENSIM_DB_USER: .database_user,
		OPENSIM_DB_PASS: .database_password,
		OPENSIM_DB_ADMIN_USER: .admin_user,
		OPENSIM_DB_ADMIN_PASS: .admin_password
	} | to_entries[] | select(.value != null and .value != "") | "export \(.key)=\(.value | @sh)"' "$SETUP_CONFIG_FILE" >"$SETUP_RC_TEMP" || die "could not prepare database credentials"
	run_container_tool cp "$SETUP_RC_TEMP" "$name:/root/.opensimrc" || die "could not copy database credentials to container $name"
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		[[ -d "$APT_SOURCE_DIR" ]] || die "APT_SOURCE_DIR must be a local directory when installing in a container"
		debs_in_container=/tmp/opensim-kit-debs
		run_container_tool cp "$APT_SOURCE_DIR" "$name:$debs_in_container" || die "could not copy local packages to container $name"
		environment+=(APT_SOURCE_DIR="$debs_in_container")
	fi
	environment+=(OPENSIM_KIT_APT_DIST="$OPENSIM_KIT_APT_DIST" OPENSIM_KIT_APT_COMPONENT="$OPENSIM_KIT_APT_COMPONENT")
	environment+=(APT_SOURCE="${APT_SOURCE:-}" APT_SOURCE_TESTS="${APT_SOURCE_TESTS:-}")
	environment+=(OPENSIM_SETUP_CONFIG_FILE=/tmp/opensim-setup.json)
	[[ -z "$ASSUME_YES" ]] || environment+=(ASSUME_YES="$ASSUME_YES")
	[[ -z "$RUN_SETUP" ]] || environment+=(RUN_SETUP="$RUN_SETUP")
	[[ -z "$DEBUG" ]] || environment+=(DEBUG="$DEBUG")
	run_container_tool exec "$name" -- env "${environment[@]}" bash /tmp/kickstart.sh "$@" || status=$?
	return "$status"
}

prepared_podman_publish_mappings() {
	local config=$1
	jq -e '
		(.port_bindings | type == "array" and length > 0)
		and all(.port_bindings[];
			(.port as $port | ($port | type) == "number" and $port == ($port | floor) and $port >= 1 and $port <= 65535)
			and (.protocol == "tcp" or .protocol == "udp")
			and (.use == "public" or .use == "private" or .use == "console")
			and has("host_ip")
			and (.host_ip == null or (.host_ip | type) == "string")
		)
	' "$config" >/dev/null || return 1
	jq -r '
		.port_bindings[]
		| if .host_ip == null or .host_ip == "" then "\(.port):\(.port)/\(.protocol)"
		  else "\(.host_ip):\(.port):\(.port)/\(.protocol)"
		  end
	' "$config"
}

validate_prepared_podman_ports() {
	local config=$1 occupied_ports conflicts
	occupied_ports=$(run_container_tool host-ports | jq -cer 'select(type == "array" and all(.[]; type == "number" and floor == . and . >= 1 and . <= 65535))') || die "could not recheck ports on the selected Podman host before launch"
	conflicts=$(jq -er --argjson occupied_ports "$occupied_ports" '
		[(if .answers.type == "simulator" then empty else .setup.grid.public_port, .setup.grid.private_port, .setup.grid.console_port end),
		 (.setup.simulators[]? | .http_port, .console_port, (.regions[]?.port))]
		| map(select(type == "number" and . >= 1 and . <= 65535))
		| unique
		| map(select(. as $port | $occupied_ports | index($port) != null))
		| join(", ")
	' "$config") || die "could not validate the prepared ports"
	[[ -z "$conflicts" ]] || die "ports already occupied on the selected Podman host: $conflicts; rerun setup and choose different ports"
}

bootstrap_podman_manager() {
	if [[ -n "$clone" ]]; then
		if [[ ! -f "$clone/vendor/autoload.php" ]]; then
			phase_dependencies || return $?
		fi
		SETUP_CLI_SELECTED=$clone/bin/opensim
	else
		configure_package_sources || return $?
		# The controller needs the engine and CLI, without a local SQL server or OpenSimulator core.
		install_packages --no-install-recommends w4os-cli container-tools || return $?
		SETUP_CLI_SELECTED=/usr/share/w4os-cli/bin/opensim
	fi
}

prepare_podman_setup_config() {
	local hostname= occupied_ports
	local -a arguments=(setup)
	command -v jq >/dev/null 2>&1 || die "jq is required by the OpenSim manager"
	if [[ "$PODMAN_FORCE_LOCAL" == yes ]]; then
		hostname=$(hostname -f 2>/dev/null || hostname) || die "could not read the local host name"
	else
		hostname=$(run_container_tool info | jq -er '.Name | select(type == "string" and length > 0)') || die "could not read the selected Podman server hostname"
	fi
	say "Find available ports on $hostname"
	occupied_ports=$(run_container_tool host-ports | jq -cer 'select(type == "array" and all(.[]; type == "number" and floor == . and . >= 1 and . <= 65535))') || die "could not inspect ports on $hostname"
	SETUP_PREFILL_TEMP=$(mktemp "$TMP.prefill.XXXXXXXX") || die "could not create a private setup prefill"
	jq --argjson occupied_ports "$occupied_ports" --arg hostname "$hostname" '.occupied_ports = $occupied_ports | if (.answers | type) == "object" then (if $hostname == "" then . else .answers.hostname //= $hostname end) else (if $hostname == "" then . else .hostname //= $hostname end) end' "${SETUP_CONFIG_FILE:-/dev/stdin}" >"$SETUP_PREFILL_TEMP" <<<'{}' || die "could not prepare the selected host setup context"
	arguments+=(--config "$SETUP_PREFILL_TEMP")
	[[ -z "$REGION_CONFIG_FILE" ]] || arguments+=(--region-config "$REGION_CONFIG_FILE")
	SETUP_CONFIG_TEMP=$(mktemp "$TMP.setup.XXXXXXXX") || die "could not create a private setup file"
	arguments+=(--prepare "$SETUP_CONFIG_TEMP")
	"$SETUP_CLI_SELECTED" "${arguments[@]}" || die "setup preparation failed; no container created"
	jq --arg external_host "$hostname" '
		if ($external_host | length) > 0 then
		.setup.simulators = ((.setup.simulators // []) | map(
				if ((.external_host // "") | ascii_downcase) == "" or ((.external_host // "") | ascii_downcase) == "systemip"
				then .external_host = $external_host
				else .
				end
			))
		else . end
	' "$SETUP_CONFIG_TEMP" >"$SETUP_PREFILL_TEMP" || die "could not set the region's externally reachable address"
	mv "$SETUP_PREFILL_TEMP" "$SETUP_CONFIG_TEMP" || die "could not save the region's externally reachable address"
	PODMAN_CONTAINER_NAME=$(jq -er '.identity | select(type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"))' "$SETUP_CONFIG_TEMP") || die "invalid setup config: the engine did not provide an instance identity"
	SETUP_CONFIG_FILE=$SETUP_CONFIG_TEMP
}

run_container_tool() {
	if [[ "$PODMAN_FORCE_LOCAL" == yes ]]; then
		env -u CONTAINER_CONNECTION -u CONTAINER_HOST "$CONTAINER_TOOLS_CLI_SELECTED" "$@"
	elif [[ "$PODMAN_CONNECTION_SELECTED" == yes ]]; then
		"$CONTAINER_TOOLS_CLI_SELECTED" --connection "$PODMAN_CONNECTION" "$@"
	else
		"$CONTAINER_TOOLS_CLI_SELECTED" "$@"
	fi
}

# A package configuration an earlier run left unfinished, completed (nothing to say when there was none)
recover_dpkg_configuration() {
	if [[ "$DPKG_CONFIGURED" != yes ]]; then
		as_root dpkg --configure -a >>"$(install_log)" 2>&1 || return $?
		DPKG_CONFIGURED=yes
	fi
	return 0
}

apt_update() {
	if [[ "$APT_UPDATED" != yes ]]; then
		run_step "Package lists" - as_root apt-get update -qq || return $?
		APT_UPDATED=yes
	fi
}

# The .NET majors the cores installed (under /usr/share/opensim, or the folder given) target, from their runtimeconfig.json: a
# core runs on that major, never a newer one
dotnet_target_majors() {
	local config
	for config in "${1:-/usr/share/opensim}"/*/bin/OpenSim.runtimeconfig.json; do
		[[ -f "$config" ]] || continue
		tr -d '\n' <"$config" | grep -Eo '"Microsoft\.NETCore\.App"[^}]*"version"[^"]*"[0-9]+' | grep -Eo '[0-9]+$'
	done | sort -un
}

# The system package of the runtime of a major, when the package manager has it
dotnet_runtime_package() {
	local package="dotnet-runtime-$1.0"
	LC_ALL=C apt-cache policy "$package" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" { found = 1 } END { exit !found }' || return 1
	printf '%s\n' "$package"
}

# Whether the runtime of a major is installed
dotnet_runtime_installed() {
	command -v dotnet >/dev/null 2>&1 &&
		dotnet --list-runtimes 2>/dev/null | grep -Eq "Microsoft\.NETCore\.App $1\."
}

# The packages of an install in progress, from what dpkg wrote in the log since it started: 12/27 opensim-0.9.3.0
PACKAGES_TOTAL=0
PACKAGES_FROM=0
packages_counter() {
	local said
	said=$(tail -c +$((PACKAGES_FROM + 1)) "$INSTALL_LOG" 2>/dev/null | grep -E '^(Unpacking|Setting up) ')
	# Nothing unpacked yet: apt is downloading them
	[[ -n "$said" ]] || { printf '0/%s downloading' "$PACKAGES_TOTAL"; return 0; }
	printf '%s/%s %s' "$(grep -c '^Setting up ' <<<"$said")" "$PACKAGES_TOTAL" "$(tail -n 1 <<<"$said" | awk '{ name = $1 == "Setting" ? $3 : $2; sub(/:.*/, "", name); print name }')"
}

# Packages installed behind the live line (PACKAGES_LABEL names them, Packages by default), what apt says in the log; nothing said
# when they are all there
install_packages() {
	local label=${PACKAGES_LABEL:-Packages} log
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu"
	export DEBIAN_FRONTEND=noninteractive
	recover_dpkg_configuration || return $?
	apt_update || return $?
	log=$(install_log)
	PACKAGES_TOTAL=$(LC_ALL=C apt-get -s install "$@" 2>/dev/null | grep -c '^Inst ') || PACKAGES_TOTAL=0
	((PACKAGES_TOTAL > 0)) || return 0
	PACKAGES_FROM=$(wc -c <"$log" | tr -d ' ')
	run_step "$label" packages_counter apt_install "$@" || return $?
	done_line "$label ($PACKAGES_TOTAL)"
}

# apt-get install, once more after the package lists are read again when a package it was to fetch is gone (Failed to fetch, a
# 404: a newer build was published meanwhile, the one the lists named was removed)
apt_install() {
	local said status=0
	said=$(mktemp) || return $?
	as_root env LC_ALL=C apt-get install -y -qq "$@" 2>&1 | tee "$said" || status=${PIPESTATUS[0]}
	if ((status != 0)) && grep -qE '^E: Failed to fetch .* 404' "$said"; then
		say "A package changed in the repository while it was installed: the package lists are read again, and it is installed once more"
		as_root apt-get update -qq && status=0 && { as_root env LC_ALL=C apt-get install -y -qq "$@" || status=$?; }
	fi
	rm -f "$said"
	return "$status"
}

database_server_installed() {
	local package
	for package in mariadb-server mysql-server mysql-server-8.0 mysql-community-server default-mysql-server percona-server-server percona-server-server-8.0; do
		if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
			return 0
		fi
	done
	return 1
}

apt_accessible_local_repository() {
	local source=$1 mirror_root=/var/cache/w4os-cli/local-repositories mirror_key mirror
	local -a packages
	if command -v runuser >/dev/null 2>&1 && as_root runuser -u _apt -- test -r "$source/Packages.gz"; then
		printf '%s\n' "$source"
		return 0
	fi

	mirror_key=$(printf '%s' "$source" | cksum | awk '{print $1}') || return $?
	mirror=$mirror_root/$mirror_key
	if ! cmp -s "$source/Packages.gz" "$mirror/Packages.gz"; then
		packages=("$source"/*.deb)
		[[ -e "${packages[0]}" ]] || die "no .deb packages found in $source"
		as_root install -d -m 755 "$mirror" || return $?
		as_root find "$mirror" -mindepth 1 -maxdepth 1 -type f -name '*.deb' -delete || return $?
		as_root cp -f "${packages[@]}" "$mirror/" || return $?
		as_root cp -f "$source/Packages.gz" "$mirror/Packages.gz" || return $?
		as_root chmod 644 "$mirror"/*.deb "$mirror/Packages.gz" || return $?
	fi
	if command -v runuser >/dev/null 2>&1 && ! as_root runuser -u _apt -- test -r "$mirror/Packages.gz"; then
		die "could not make the local package cache readable by APT"
	fi
	printf '%s\n' "$mirror"
}

# Write the sources file: each wanted repository (APT_REPOSITORIES) updates its own line where it stands, commented or not,
# with the components it already has plus the wanted ones; a repository not in the file yet is added at the end. Other lines
# keep their place. Old Magiiic distributions (main, stable, unstable, tests) are dropped.
write_apt_repositories() {
	local source_file=$1 temporary_file=$2 wanted_file=$2.wanted
	printf '%s\n' "${APT_REPOSITORIES[@]}" >"$wanted_file" || return $?
	local input=/dev/null
	[[ -r "$source_file" ]] && input=$source_file
	awk '
		# Fields of a sources line, commented or not: sets kind, options, uri, dist, comps; returns 0 for any other line
		function parse(line,    n, f, i, start) {
			sub(/^[ \t]*(#[ \t]*)*/, "", line)
			n = split(line, f, /[ \t]+/)
			if (f[1] != "deb" && f[1] != "deb-src") return 0
			kind = f[1]; options = ""; start = 2
			if (f[2] ~ /^\[/) {
				for (i = 2; i <= n; i++) {
					options = options (options == "" ? "" : " ") f[i]
					if (f[i] ~ /\]$/) break
				}
				start = i + 1
			}
			uri = f[start]; dist = f[start + 1]; comps = ""
			if (uri !~ /^[a-z+]+:/ || dist == "") return 0
			for (i = start + 2; i <= n; i++) comps = comps (comps == "" ? "" : " ") f[i]
			return 1
		}
		function merge(have, add,    n, i, m, j, out, seen, parts) {
			out = ""
			n = split(have " " add, parts, /[ \t]+/)
			for (i = 1; i <= n; i++) {
				if (parts[i] == "" || (parts[i] in seen)) continue
				seen[parts[i]] = 1
				out = out (out == "" ? "" : " ") parts[i]
			}
			return out
		}
		function line_of(k, comps) {
			return W_kind[k] " " (W_options[k] == "" ? "" : W_options[k] " ") W_uri[k] " " W_dist[k] " " comps
		}
		NR == FNR {
			if (parse($0)) {
				wanted++
				W_kind[wanted] = kind; W_options[wanted] = options; W_uri[wanted] = uri; W_dist[wanted] = dist; W_comps[wanted] = comps
			}
			next
		}
		{
			total++
			text[total] = $0
			isrepo[total] = 0
			if (!parse($0)) next
			isrepo[total] = 1
			commented[total] = ($0 ~ /^[ \t]*#/)
			R_uri[total] = uri; R_dist[total] = dist; R_comps[total] = comps
		}
		END {
			# The line of each wanted repository: the first active one, else the first commented one
			for (k = 1; k <= wanted; k++) {
				target[k] = 0
				for (pass = 0; pass <= 1 && !target[k]; pass++)
					for (i = 1; i <= total && !target[k]; i++)
						if (isrepo[i] && R_uri[i] == W_uri[k] && R_dist[i] == W_dist[k] && commented[i] == pass) target[k] = i
				merged[k] = W_comps[k]
				for (i = 1; i <= total; i++)
					if (isrepo[i] && !commented[i] && R_uri[i] == W_uri[k] && R_dist[i] == W_dist[k]) merged[k] = merge(R_comps[i], merged[k])
			}
			for (i = 1; i <= total; i++) {
				if (!isrepo[i]) { print text[i]; continue }
				if (R_uri[i] ~ /^file:/ && !commented[i]) continue
				done = 0
				for (k = 1; k <= wanted && !done; k++) {
					if (R_uri[i] != W_uri[k] || R_dist[i] != W_dist[k]) continue
					done = 1
					if (target[k] == i) print line_of(k, merged[k])
					else if (commented[i]) print text[i]
				}
				if (done) continue
				if (R_uri[i] == "https://apt.magiiic.com" && !commented[i] && (R_dist[i] == "main" || R_dist[i] == "stable" || R_dist[i] == "unstable" || R_dist[i] == "tests")) continue
				print text[i]
			}
			for (k = 1; k <= wanted; k++) if (!target[k]) print line_of(k, merged[k])
		}
	' "$wanted_file" "$input" >"$temporary_file" || return $?
	rm -f "$wanted_file"
	[[ -z "${apt_debs:-}" ]] || printf 'deb [trusted=yes] file:%s ./\n' "$apt_debs" >>"$temporary_file"
	as_root install -m 644 "$temporary_file" "$source_file"
}

configure_package_sources() {
	[[ "$PACKAGE_SOURCES_READY" == yes ]] && return 0
	[[ $(uname -s) == Linux ]] || die "packages are for Debian and Ubuntu"
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu"
	local source_file=$APT_SOURCE_FILE
	local -a bootstrap_packages=(ca-certificates curl gpg openssl)
	local package local_debs= refresh_local_index=no
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		local_debs=$(cd "$APT_SOURCE_DIR" && pwd) || die "$APT_SOURCE_DIR is not a folder"
		if [[ ! -s "$local_debs/Packages.gz" ]] || [[ $(ls -rt "$local_debs"/*.deb "$local_debs/Packages.gz" 2>/dev/null | tail -n 1) != "$local_debs/Packages.gz" ]]; then
			refresh_local_index=yes
			command -v dpkg-scanpackages >/dev/null 2>&1 || bootstrap_packages+=(dpkg-dev)
		fi
	fi
	local -a missing_bootstrap_packages=()
	for package in "${bootstrap_packages[@]}"; do
		dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed || missing_bootstrap_packages+=("$package")
	done
	if ((${#missing_bootstrap_packages[@]})); then
		# Old repository entries can make the bootstrap apt update fail before
		# this script has a chance to replace them. Hide this file only while
		# installing tools from the distribution repositories, then restore it.
		local source_backup=$TMP.magiiic.list source_saved=no bootstrap_status=0
		if [[ -e "$source_file" ]]; then
			as_root cp -f "$source_file" "$source_backup" || return $?
			as_root rm -f "$source_file" || return $?
			source_saved=yes
		fi
		PACKAGES_LABEL="Tools" install_packages "${missing_bootstrap_packages[@]}" || bootstrap_status=$?
		if [[ "$source_saved" == yes ]]; then
			as_root mv -f "$source_backup" "$source_file" || return $?
		fi
		((bootstrap_status == 0)) || return "$bootstrap_status"
	fi

	local apt_debs=
	[[ "$OPENSIM_KIT_APT_DIST" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid OPENSIM_KIT_APT_DIST: $OPENSIM_KIT_APT_DIST"
	[[ "$OPENSIM_KIT_APT_COMPONENT" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid OPENSIM_KIT_APT_COMPONENT: $OPENSIM_KIT_APT_COMPONENT"
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		if [[ "$refresh_local_index" == yes ]]; then
			(cd "$local_debs" && dpkg-scanpackages --multiversion . /dev/null 2>>"$INSTALL_LOG" | gzip -9c >Packages.gz) || die "local package index refresh failed (log: $INSTALL_LOG)"
		fi
		done_line "Local packages: $local_debs ($(ls "$local_debs"/*.deb 2>/dev/null | wc -l | tr -d ' '))"
		apt_debs=$(apt_accessible_local_repository "$local_debs") || return $?
	fi
	local needs_magiiic_key=no
	for repository in "${APT_REPOSITORIES[@]}"; do
		[[ "$repository" == *https://apt.magiiic.com* ]] && needs_magiiic_key=yes
	done
	if [[ "$needs_magiiic_key" == yes && ! -s /usr/share/keyrings/magiiic-packaging.gpg ]]; then
		curl -fsSL "$MAGIIIC_KEY" | as_root gpg --dearmor --yes -o /usr/share/keyrings/magiiic-packaging.gpg || return $?
	fi
	write_apt_repositories "$source_file" "$TMP.magiiic.sources" || return $?
	APT_UPDATED=no
	apt_update || return $?
	PACKAGE_SOURCES_READY=yes
}

phase_dependencies() {
	if [[ -n "$clone" ]]; then
		local missing=() tool
		if [[ $(uname -s) == Darwin ]]; then
			# Nothing installed by itself on macOS: what is missing is named
			for tool in php composer screen jq curl tar; do
				command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
			done
			((${#missing[@]} == 0)) || die "missing on this Mac: ${missing[*]}. Install them (with Homebrew for instance: brew install ${missing[*]}), then run this again"
		else
			command -v php >/dev/null 2>&1 || missing+=("${PHP_PACKAGES[@]}")
			# The engine draws with ImageMagick: not a dependency of php itself
			php -m 2>/dev/null | grep -qi '^imagick$' || missing+=(php-imagick)
			command -v composer >/dev/null 2>&1 || missing+=(composer)
			for tool in curl git unzip screen jq sudo; do
				command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
			done
			command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 ||
				missing+=(default-mysql-client)
			if ((${#missing[@]})); then
				PACKAGES_LABEL="Tools" install_packages "${missing[@]}" || return $?
			fi
		fi
		php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' || die "PHP 8.2 or newer is needed (this is $(php -r 'echo PHP_VERSION;'))"
		if composer_needed; then
			# A clone in development mode takes its libraries from its neighbours: said when they are not beside it
			local neighbour absent=()
			while IFS= read -r neighbour; do
				[[ -z "$neighbour" || -d "$clone/$neighbour" ]] || absent+=("$neighbour")
			done < <(jq -r '.repositories[]? | select(.type == "path") | .url' "$clone/composer.json" 2>/dev/null)
			((${#absent[@]} == 0)) || die "this clone takes its libraries from the clones beside it, and these are missing: ${absent[*]} (from $clone). Clone them there, or install from a release"
			run_step "PHP libraries (composer)" - bash -c 'cd "$1" && composer install --no-dev --no-interaction --prefer-dist' composer "$clone" || die "composer install failed: its output is in $(install_log)"
			done_line "PHP libraries (composer)"
		fi
	else
		configure_package_sources || return $?
	fi
}

# The server started without systemd (a container) is left running: never on the terminal, which it would keep open after the run
# (the prompt would not come back): in a session of its own, without the terminal of the questions (fd 8), its input /dev/null, its
# outputs the log
start_sql_server() {
	local detach=()
	command -v setsid >/dev/null 2>&1 && detach=(setsid -w)
	if as_root "${detach[@]}" service mariadb start </dev/null >>"$(install_log)" 2>&1 8<&- || as_root "${detach[@]}" service mysql start </dev/null >>"$(install_log)" 2>&1 8<&-; then
		return 0
	fi
	as_root mysqladmin ping --silent >/dev/null 2>&1 && return 0

	# Rootless containers cannot always let the init script drop privileges from
	# namespace-root to mysql. Run MariaDB as mysql directly in that case.
	if [[ ! -f /run/.containerenv && ! -f /.dockerenv ]]; then
		return 1
	fi
	command -v mariadbd >/dev/null 2>&1 || return 1
	command -v mariadb-install-db >/dev/null 2>&1 || return 1
	command -v mariadbd-safe >/dev/null 2>&1 || return 1
	command -v runuser >/dev/null 2>&1 || return 1
	command -v start-stop-daemon >/dev/null 2>&1 || return 1
	local datadir log_file
	datadir=$(mariadbd --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')
	[[ -n "$datadir" ]] || return 1
	if [[ ! -d "$datadir/mysql" ]]; then
		as_root runuser -u mysql -- mariadb-install-db --datadir="$datadir" --basedir=/usr --auth-root-authentication-method=normal || return 1
	fi
	log_file=${TMP:-/tmp/quick-install}.mariadb.log
	log 'Starting MariaDB as its service user in the container'
	as_root "${detach[@]}" start-stop-daemon --start --background --chuid mysql \
		--exec "$(command -v mariadbd-safe)" -- --datadir="$datadir" </dev/null >>"$log_file" 2>&1 8<&- || return 1
	local attempt
	for attempt in {1..30}; do
		as_root mysqladmin ping --silent >/dev/null 2>&1 && return 0
		sleep 1
	done
	tail -n 20 "$log_file"
	return 1
}

phase_database() {
	[[ $(uname -s) == Linux ]] || die "The database server installs on Debian and Ubuntu"
	# The sources of our packages are not for a clone, which installs none of them
	[[ -n "${clone:-}" && -z "${APT_SOURCE_DIR:-}" ]] || configure_package_sources || return $?
	if database_server_installed; then
		done_line "Database server (kept)"
	else
		local server_package
		case "$DATABASE_CHOICE" in
		mariadb) server_package=mariadb-server ;;
		mysql) server_package=mysql-server ;;
		esac
		PACKAGES_LABEL="Database server" install_packages "$server_package" || die "could not install $server_package"
	fi
	start_sql_server || die "could not start the database server"
	command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || die "The database client is unavailable after the server installation"

	# Its users are the setup's: the DB admin user asked first, the one of a grid once its name is known
}

# Installation completed: the grids of an install of before migrated or run in place, else the assistant (opensim setup) in the same
# A file of answers of the setup: the ones of a file given (its answers, or the object itself), these over them, and the ones of
# these flags set to yes (name, variable); a file of its own, the one given never changed
answers_with() { # file, JSON object, [name variable]...
	local file=$1 more=$2 out
	shift 2
	while (($# > 1)); do
		[[ "${!2:-}" != yes ]] || more=$(jq -c --arg k "$1" '.[$k] = "yes"' <<<"$more")
		shift 2
	done
	out=$(mktemp) && chmod 644 "$out"
	if [[ -n "$file" && -r "$file" ]]; then
		jq --argjson more "$more" 'if (.answers | type) == "object" then .answers += $more else . + $more end' "$file" >"$out"
	else
		jq -n --argjson more "$more" '{answers: $more}' >"$out"
	fi
	printf '%s' "$out"
}

# The summary of the setup, its line of the passwords before why the website is not there, which ends it (and the log)
setup_summary() { # file of the summary
	local said
	said=$(cat "$1" 2>/dev/null)
	rm -f "$1"
	[[ -n "$said" ]] || return 0
	{
		grep -v '^Website    not installed' <<<"$said"
		! as_root test -f "$OPENSIM_RC_PATH" || printf 'Passwords  %s (root only)\n' "$OPENSIM_RC_PATH"
		grep '^Website    not installed' <<<"$said" || true
	} | tee -a "$(install_log)"
}

# run when somebody is there to answer (or RUN_SETUP=yes)
end_installation() {
	local basedir opensim_path setup_config=${OPENSIM_SETUP_CONFIG_FILE:-$SETUP_CONFIG_FILE} setup_config_path= setup_option=--config
	local -a setup_arguments=(setup)
	# An install of before the kit, migrated or run in place: the scenario of the engine, as root (its steps of root are the command
	# line's)
	if [[ "$LEGACY_MODE" == scenario ]]; then
		local said status=0 end
		local -a legacy=(setup --legacy)
		cli=${clone:+$clone/bin/opensim}
		[[ -n "$cli" ]] || cli=/usr/share/w4os-cli/bin/opensim
		# The summary kept to be said last: its line of the passwords before why the website is not there, which ends it
		end=$(mktemp) && chmod 666 "$end"
		say ""
		if [[ "${LEGACY_INTERACTIVE:-}" == yes ]]; then
			# The terminal of the questions (fd 8) kept from what it starts: the setup opens its own
			as_root env OPENSIM_RC="$OPENSIM_RC_PATH" OPENSIM_SETUP_UI="$SETUP_UI" OPENSIM_SETUP_END="$end" "$cli" "${legacy[@]}" 8<&- || status=$?
		else
			# Nobody there (or --yes): every answer at once, the ones of --config, the defaults of the scenario for the others; each
			# line of its run in the log too
			legacy+=(--unattended --config "$(answers_with "$setup_config" "{\"existing\":\"${LEGACY_CHOICE:-migrate}\"}" restart LEGACY_RESTART vhosts EDIT_VHOSTS)")
			{ as_root env OPENSIM_RC="$OPENSIM_RC_PATH" OPENSIM_SETUP_UI=lines OPENSIM_SETUP_END="$end" "$cli" "${legacy[@]}" </dev/null 2>&1 8<&-; echo "status $?" >"$end.status"; } | tee -a "$(install_log)"
			status=$(sed -n 's/^status //p' "$end.status" 2>/dev/null)
			rm -f "$end.status"
		fi
		setup_summary "$end"
		# Stopped at the person's request (4): said by the setup, not an error
		((status != 4)) || exit 0
		exit "$status"
	fi

	if [ -n "${clone:-}" ]; then
		basedir=$clone
	else
		opensim_path=$(command -v opensim) || die "opensim is not available after installation"
		basedir=$(cd "$(dirname "$(realpath "$opensim_path")")/.." && pwd) || die "could not locate the opensim installation"
	fi
	# The line of the website in the sites of Apache given (--edit-vhosts): an answer of the setup, asked else
	[[ -z "${EDIT_VHOSTS:-}" ]] || setup_config=$(answers_with "$setup_config" '{}' vhosts EDIT_VHOSTS)
	if [[ -n "$setup_config" && -r "$setup_config" ]]; then
		if [[ -z "$REGION_CONFIG_FILE" ]] && jq -e ' .version == 1 and (.answers | type == "object") and (.setup | type == "object")' "$setup_config" >/dev/null 2>&1; then
			setup_option=--apply
		fi
		# Kept for the account of the suite when root installs; a person's own config stays where it is, theirs to read
		if [[ $(uname -s) == Linux && $(id -u) -eq 0 ]]; then
			as_root mkdir -p /etc/opensim || die "could not create /etc/opensim"
			as_root install -m 600 "$setup_config" /etc/opensim/setup.json || die "could not install the setup config"
			if getent passwd opensim >/dev/null 2>&1; then
				as_root chown opensim:opensim /etc/opensim/setup.json || die "could not assign the setup config to opensim"
			fi
			setup_config_path=/etc/opensim/setup.json
		else
			setup_config_path=$setup_config
		fi
	fi
	[[ -z "$setup_config_path" ]] || setup_arguments+=("$setup_option" "$setup_config_path")
	[[ -z "$REGION_CONFIG_FILE" ]] || setup_arguments+=(--region-config "$REGION_CONFIG_FILE")
	[[ -z "$SHOW_PASSWORDS" ]] || setup_arguments+=(--show-passwords)
	if [[ "${RUN_SETUP:-}" =~ ^(yes|true|1)$ ]] || person_here; then
		say ""
		local end
		# The summary of the setup said last, with the line of the passwords; its website is its last step (as root, by its name)
		end=$(mktemp) && chmod 666 "$end"
		local status=0
		OPENSIM_RC=$OPENSIM_RC_PATH OPENSIM_SETUP_UI=$SETUP_UI OPENSIM_SETUP_END=$end "$basedir/bin/opensim" "${setup_arguments[@]}" 8<&- || status=$?
		# Stopped at the person's request (4): said by the setup, not an error
		((status != 4)) || exit 0
		((status == 0)) || die "the setup stopped (error $status)"
		done_line "Done"
		say ""
		setup_summary "$end"
	else
		done_line "Installed"
	fi
	exit 0
}

phase_dotnet() {
	[[ $(uname -s) == Linux ]] || {
		say ".NET installation is only run on Linux"
		return 0
	}
	recover_dpkg_configuration || die "could not complete package configuration"
	apt_update || die "could not refresh package lists"
	local majors=() major runtime_package support_packages=() missing=()
	mapfile -t majors < <(dotnet_target_majors)
	for major in "${majors[@]}"; do
		dotnet_runtime_installed "$major" && continue
		if runtime_package=$(dotnet_runtime_package "$major"); then
			support_packages+=("$runtime_package")
		else
			missing+=("$major")
		fi
	done
	if ! ldconfig -p 2>/dev/null | grep -q 'libgdiplus\.so'; then
		support_packages+=(libgdiplus)
	fi
	if ((${#support_packages[@]})); then
		PACKAGES_LABEL=".NET runtime" install_packages "${support_packages[@]}" || die "could not install .NET runtime packages"
	fi
	((${#missing[@]})) || return 0

	# No system package of the runtime of a major: Microsoft's installer, its output in the log
	if ! command -v curl >/dev/null 2>&1 || ! dpkg-query -W -f='${db:Status-Status}' ca-certificates 2>/dev/null | grep -qx installed; then
		PACKAGES_LABEL="Tools" install_packages ca-certificates curl || die "could not install curl for the .NET installer"
	fi
	if ! ldconfig -p 2>/dev/null | grep -q 'libicuuc\.so'; then
		local icu_package
		icu_package=$(apt-cache pkgnames libicu 2>/dev/null | grep -E '^libicu[0-9]+(t64)?$' | sort -V | tail -n 1)
		[[ -z "$icu_package" ]] || PACKAGES_LABEL=".NET runtime" install_packages "$icu_package" || die "could not install $icu_package"
	fi
	local install_script
	install_script=$(mktemp "${TMPDIR:-/tmp}/dotnet-install.XXXXXX") || return $?
	if ! curl -fsSL https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.sh -o "$install_script"; then
		rm -f "$install_script"
		die "could not download dotnet-install.sh"
	fi
	# Each beside the others, in the same folder: dotnet runs each core on the major it targets
	for major in "${missing[@]}"; do
		run_step ".NET $major runtime" - as_root bash "$install_script" --runtime dotnet --channel "$major.0" \
			--azure-feed https://builds.dotnet.microsoft.com/dotnet \
			--install-dir /usr/local/share/dotnet || {
			rm -f "$install_script"
			die "could not install the .NET $major runtime"
		}
		done_line ".NET $major runtime"
	done
	rm -f "$install_script"
	as_root ln -sf /usr/local/share/dotnet/dotnet /usr/local/bin/dotnet || die "could not link dotnet into /usr/local/bin"
	for major in "${missing[@]}"; do
		dotnet_runtime_installed "$major" || die "the .NET $major runtime is not available after installation"
	done
}

# The machine in one line: its system, its memory, the free space of its disk
system_line() {
	local name memory free
	name=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-$NAME}")
	memory=$(awk '/^MemTotal:/ { printf "%.0f GB RAM", $2 / 1048576 }' /proc/meminfo 2>/dev/null)
	free=$(df -Pk / 2>/dev/null | awk 'NR == 2 { printf "%.0f GB free", $4 / 1048576 }')
	printf '%s' "${name:-Linux}${memory:+, $memory}${free:+, $free}"
}

# Whether the PHP libraries of a clone are to be installed or upgraded (composer)
composer_needed() {
	[[ ! -f "$clone/vendor/autoload.php" || "$clone/composer.lock" -nt "$clone/vendor/composer/installed.json" ]]
}

# The one question before the setup: the installer's own libraries from a clone, else the packages it needs
opening_question() {
	if [[ -n "$clone" && -z "$APT_SOURCE_DIR" ]]; then
		# A clone carries the install by itself: its libraries by composer, the one thing asked; nothing when they are there
		composer_needed || return 0
		say "Composer dependencies upgrade is needed by the installer."
		ask "Execute composer install?"
	else
		say "This will install the packages required by the installer."
		ask "Install w4os-engine?"
	fi
}

# The install of before the kit on this machine (opensim-debian, in /opt/opensim): its folder, nothing when there is none
legacy_install() {
	if [[ -f "$LEGACY_ROOT/lib/os-helpers" ]] || { [[ -f "$LEGACY_CRON" ]] && grep -q "$LEGACY_ROOT" "$LEGACY_CRON" 2>/dev/null; }; then
		printf '%s\n' "$LEGACY_ROOT"
	fi
}

# What starts the instances of the install of before the kit by itself: its hourly cron, and a unit of its own named opensim
# (which would hide the one of the kit)
legacy_starters() {
	[[ ! -f "$LEGACY_CRON" ]] || printf '%s\n' "$LEGACY_CRON"
	local unit
	for unit in ${LEGACY_UNITS:-/etc/systemd/system/opensim.service /etc/init.d/opensim}; do
		[[ -f "$unit" && ! -L "$unit" ]] && ! grep -q "opensim service" "$unit" 2>/dev/null && printf '%s\n' "$unit"
	done
	return 0
}

# The install of before the kit, in one line: its folder, its grid, its simulators
legacy_summary() { # root
	local nick count robust
	robust=$(legacy_configs robust | head -n 1)
	[[ -z "$robust" ]] || nick=$(legacy_nick "$robust")
	count=$(legacy_configs simulator | grep -c .) || count=0
	printf 'Found an existing install in %s%s.' "$1" "${nick:+: grid $nick, $count simulator$( ((count == 1)) || printf s)}"
}

# Before anything is installed, beside an install of before the kit: the consent to install the kit, the choice being the scenario's
# (or given: --migrate, --in-place, --new). Before the kit, only a unit of its own named opensim is set aside (renamed
# *.w4os-disabled), which would hide the kit's; migrated or run in place, the scenario sets the rest aside in its run
legacy_gate() {
	local root
	root=$(legacy_install)
	[[ -n "$root" ]] || return 0
	# The choice is the engine's scenario (opensim setup --legacy, once the kit is installed); only a run without anybody gives it here
	if [[ -z "$LEGACY_MODE" ]] && person_here; then
		# The install found is listed by the first screen of the setup
		LEGACY_MODE=scenario LEGACY_INTERACTIVE=yes
		legacy_set_aside
		return 0
	fi
	if [[ -z "$LEGACY_MODE" ]]; then
		say "  $(legacy_summary "$root")"
		die "nobody to choose: give --migrate (--yes, its answers with --config), --in-place or --new"
	fi
	# Migrated or run in place, it is the scenario's too, its answers given (--config), the defaults else; it sets the old install
	# aside in its run, after Start (Stop); before it, only a unit named opensim, which would hide the kit's (a new grid beside it too)
	if [[ "$LEGACY_MODE" == migrate || "$LEGACY_MODE" == in-place ]]; then
		LEGACY_CHOICE=$LEGACY_MODE LEGACY_MODE=scenario
		[[ -n "$ASSUME_YES" ]] || ! person_here || LEGACY_INTERACTIVE=yes
	fi
	legacy_set_aside
}

# The units of the install of before the kit named opensim set aside (renamed *.w4os-disabled): they would hide the kit's; its cron
# and its other units are the scenario's, set aside in its run
legacy_set_aside() {
	local starter
	while IFS= read -r starter; do
		[[ "$starter" == */opensim.service || "$starter" == */init.d/opensim ]] || continue
		as_root mv -- "$starter" "$starter.w4os-disabled" || die "could not set aside $starter"
	done < <(legacy_starters)
	[[ ! -d /run/systemd/system ]] || as_root systemctl daemon-reload || true
}

# The configs of the install of before the kit: its Robusts, its simulators (one a line, by kind)
legacy_configs() { # robust|simulator
	local folder=robust.d
	[[ "$1" == robust ]] || folder=opensim.d
	find "$(legacy_install)/etc/$folder" -maxdepth 1 -name "*.ini" 2>/dev/null | sort
}

# The nick the kit gives a grid in place: the gridnick of its Robust config, in the small letters of a nick
legacy_nick() { # robust config
	sed -nE 's/^[[:space:]]*gridnick[[:space:]]*=[[:space:]]*"?([^";]*)"?.*/\1/p' "$1" | head -1 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-'
}

# The web server configs that use files of the folders a cleanup removes, one a line: "link PATH" (a link to one of them, in the
# folders a web server reads) or "line FILE:NUMBER" (an import, Include or include of one of them). Left there, they would stop
# the web server, and all its sites with it. WEB_CONFIG_DIRS: where the configs are (the tests).
web_references() { # folder...
	local file target line number pattern= folder
	for folder in "$@"; do pattern+="${pattern:+|}$(printf '%s' "$folder" | sed 's|[][\.*^$+?(){}]|\\&|g')"; done
	[[ -n "$pattern" ]] || return 0
	while IFS= read -r -d '' file; do
		if [[ -L "$file" ]]; then
			target=$(readlink -f -- "$file" 2>/dev/null || readlink -- "$file")
			[[ "$target" =~ ^($pattern)(/|$) ]] && printf 'link %s\n' "$file"
			continue
		fi
		number=0
		while IFS= read -r line || [[ -n "$line" ]]; do
			number=$((number + 1))
			[[ "$line" =~ ^[[:space:]]*(import|Include|IncludeOptional|include)[[:space:]]+\"?($pattern)(/|\"|;|[[:space:]]|$) ]] && printf 'line %s:%s\n' "$file" "$number"
		done <"$file"
	done < <(find ${WEB_CONFIG_DIRS:-/etc/caddy /etc/apache2 /etc/nginx} \( -type f -o -type l \) -print0 2>/dev/null)
	return 0
}

# What web_references found, taken out: the links removed, the lines commented
remove_web_references() { # references (the lines of web_references)
	local kind place file number
	while read -r kind place; do
		case "$kind" in
		link) as_root rm -f -- "$place" && say "Removed the link $place" ;;
		line)
			file=${place%:*} number=${place##*:}
			as_root sed -i "${number}s/^/# Removed by the OpenSim cleanup: /" "$file" && say "Commented line $number of $file"
			;;
		esac
	done <<<"$1"
}

# The web servers that run, reloaded once their configs changed
reload_web_servers() {
	local service
	[[ -d /run/systemd/system ]] || return 0
	for service in caddy apache2 nginx; do
		systemctl --quiet is-active "$service" 2>/dev/null || continue
		as_root systemctl reload "$service" || say "Could not reload $service: systemctl status $service"
	done
}

phase_cleanup() {
	local -a packages=() folders=() databases=() duplicate_debs=() groups=() group_debs=()
	local path sql_client db escaped_db answer prefix package_rows database_rows status package dist_folder archive_folder deb group seen i web kind place

	package_rows=$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' opensim 'opensim-*' 2>/dev/null) || package_rows=
	while read -r status package; do
		if [[ "$status" == ii* ]]; then packages+=("$package"); fi
	done <<<"$package_rows"
	dist_folder=${DIST_FOLDER:-/opt/opensim/dist}
	archive_folder=${ARCHIVE_FOLDER:-$dist_folder/archive}
	if [[ -d "$dist_folder" ]]; then
		while IFS= read -r -d '' deb; do
			group=$(basename "$deb" | sed -E 's#(\.[0-9]+(\+g[a-f0-9]+|\+e[a-f0-9]+(-[0-9]+)?|\+git[a-f0-9\.-]+))?(_[a-z0-9]+)?\.deb##')
			seen=no
			for package in "${groups[@]}"; do
				if [[ "$package" == "$group" ]]; then
					seen=yes
					break
				fi
			done
			[[ "$seen" == yes ]] || groups+=("$group")
		done < <(find "$dist_folder" -maxdepth 1 -type f -name '*.deb' -print0)
		for group in "${groups[@]}"; do
			group_debs=()
			while IFS= read -r deb; do group_debs+=("$deb"); done < <(ls -t -- "$dist_folder/$group"*.deb 2>/dev/null || true)
			for ((i = 1; i < ${#group_debs[@]}; i++)); do duplicate_debs+=("${group_debs[i]}"); done
		done
	fi
	for path in /etc/opensim /var/lib/opensim /usr/share/opensim*; do
		if [[ -e "$path" || -L "$path" ]]; then folders+=("$path"); fi
	done
	if database_server_installed; then
		sql_client=$(command -v mariadb || command -v mysql) || die "The database client is unavailable; cannot inspect OpenSim databases"
		prefix=$(hostname -s)
		database_rows=$(as_root "$sql_client" -Nse 'SHOW DATABASES' 2>/dev/null) || die "cannot inspect the databases for cleanup"
		while IFS= read -r db; do
			if [[ "$db" == "$prefix"* ]]; then databases+=("$db"); fi
		done <<<"$database_rows"
	fi
	web=$(web_references "${folders[@]}")
	if ((${#packages[@]} + ${#folders[@]} + ${#databases[@]} + ${#duplicate_debs[@]} == 0)); then
		say "No existing OpenSim packages, folders, or databases to clean up"
		return 0
	fi
	say "Cleanup will remove:"
	for package in "${packages[@]}"; do say "  package $package"; done
	for path in "${folders[@]}"; do say "  folder $path ($(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ') files)"; done
	for db in "${databases[@]}"; do say "  database $db"; done
	for deb in "${duplicate_debs[@]}"; do say "  archive duplicate package $deb -> $archive_folder/"; done
	[[ -z "$web" ]] || while read -r kind place; do say "  web server $kind $place (it uses a file removed here)"; done <<<"$web"
	if [[ "$ASSUME_YES" != yes ]]; then
		[[ -r /dev/tty ]] || die "--cleanup needs an interactive confirmation (or pass --yes)"
		read -r -p 'Proceed with this cleanup? [y/N] ' answer </dev/tty || die 'cleanup cancelled'
		[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cleanup cancelled'
	fi
	if ((${#duplicate_debs[@]})); then
		mkdir -p "$archive_folder" || die "could not create package archive $archive_folder"
		for deb in "${duplicate_debs[@]}"; do mv -v -- "$deb" "$archive_folder/" || die "could not archive duplicate package $deb"; done
	fi
	if ((${#packages[@]})); then as_root apt-get remove --purge -y "${packages[@]}" || die "could not remove existing OpenSim packages"; fi
	[[ -z "$web" ]] || { remove_web_references "$web"; reload_web_servers; }
	if ((${#folders[@]})); then as_root rm -rf -- "${folders[@]}" || die "could not remove existing OpenSim folders"; fi
	for db in "${databases[@]}"; do
		escaped_db=${db//\`/\`\`}
		as_root "$sql_client" -e "DROP DATABASE \`$escaped_db\`" || die "could not drop database $db"
	done
}

# What the full install installs: the kit, its website with it on every supported system; the modules asked with --with
install_opensim_packages() {
	apt_update || return $?
	install_packages "${OPENSIM_PACKAGES[@]}" || return $?
	upgrade_suite || return $?
	install_with_modules
}

# The packages of the suite installed, upgraded to the versions of their repository: a rerun is how a fix comes, the other packages of
# the system are never touched
upgrade_suite() {
	local -a ours=()
	mapfile -t ours < <(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1 == "ii" { print $2 }' |
		grep -E '^(opensim-kit|w4os-(cli|engine|site|helpers)|opensim-rest-php|opensim|opensim-[0-9][0-9.]*(-[a-z0-9-]+)?)$')
	((${#ours[@]})) || return 0
	PACKAGES_TOTAL=$(LC_ALL=C apt-get -s install --only-upgrade "${ours[@]}" 2>/dev/null | grep -c '^Inst ') || PACKAGES_TOTAL=0
	((PACKAGES_TOTAL > 0)) || return 0
	PACKAGES_FROM=$(wc -c <"$(install_log)" | tr -d ' ')
	run_step "Suite" packages_counter apt_install --only-upgrade "${ours[@]}" || return $?
	done_line "Suite upgraded ($PACKAGES_TOTAL)"
}

# The modules asked with --with: their package for each core installed, enabled for the install (EnabledModules of w4os.conf)
install_with_modules() {
	local module core packages=()
	((${#WITH_MODULES[@]})) || return 0
	for module in "${WITH_MODULES[@]}"; do
		[[ "$module" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "--with $module: not the name of a module"
		for core in "$OPENSIM_CORES_ROOT"/*/bin; do
			[[ -e "$core/OpenSim.dll" || -e "$core/OpenSim.exe" ]] || continue
			packages+=("opensim-$(basename "$(dirname "$core")")-$module")
		done
	done
	((${#packages[@]})) || die "--with: no core installed to install ${WITH_MODULES[*]} for"
	PACKAGES_LABEL="Modules" install_packages "${packages[@]}" || return $?
	for module in "${WITH_MODULES[@]}"; do
		as_root php /usr/share/w4os-engine/bin/opensim-profiles.php --enable-module "$module" || return $?
	done
}

phase_opensim() {
	if [[ -n "$clone" && -z "$APT_SOURCE_DIR" ]]; then
		# A clone carries the install by itself, no package of ours: the core and the .NET runtime it targets are steps of the setup
		php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' || die "PHP 8.2 or newer is needed"
		done_line "w4os from the clone $clone"
		end_installation
		return 0
	fi
	configure_package_sources || return $?
	install_opensim_packages || die "could not install OpenSim packages"
	# The runtime the cores installed target
	[[ $(uname -s) != Linux ]] || phase_dotnet || die ".NET phase failed"
	end_installation
}

# The command line and the engine alone, without what they recommend: no core, no database server, no website
phase_tools() {
	configure_package_sources || return $?
	install_packages --no-install-recommends w4os-cli || die "could not install the tools"
	done_line "The opensim command and the engine"
}

# === Actual business logic starts here ===

# Tests source this file to exercise the pure APT helpers without installing
# packages or changing the host.
if [[ "${QUICK_INSTALL_LIBRARY_ONLY:-}" == yes ]]; then
	return 0 2>/dev/null || exit 0
fi

PGM=$(basename "$0")
TMP=/tmp/$PGM.$$
DEBUG=${DEBUG:-}
trap 'rm -rf "$TMP" "$TMP.$$"; [[ -z "$SETUP_CONFIG_TEMP" ]] || rm -f "$SETUP_CONFIG_TEMP"; [[ -z "$SETUP_RC_TEMP" ]] || rm -f "$SETUP_RC_TEMP"; [[ -z "$SETUP_PREFILL_TEMP" ]] || rm -f "$SETUP_PREFILL_TEMP"' EXIT

while (($#)); do
	argument=$1
	shift
	if [[ "$argument" != --remote && "$argument" != --remote=* ]]; then
		REMOTE_ARGS+=("$argument")
	fi
	case "$argument" in
	--remote)
		[[ -z "$REMOTE_TARGET" ]] || die "--remote can be specified only once"
		(($#)) || die "--remote requires an SSH target"
		REMOTE_TARGET=$1
		shift
		;;
	--remote=*)
		[[ -z "$REMOTE_TARGET" ]] || die "--remote can be specified only once"
		REMOTE_TARGET=${argument#*=}
		[[ -n "$REMOTE_TARGET" ]] || die "--remote requires an SSH target"
		;;
	--podman) PODMAN_MODE=yes ;;
	--with)
		(($#)) && [[ "$1" != -* ]] || die "--with requires a module (gloebit)"
		WITH_MODULES+=("$1")
		REMOTE_ARGS+=("$1")
		PODMAN_INSTALL_ARGS+=("$argument" "$1")
		shift
		;;
	--with=*)
		[[ -n "${argument#*=}" ]] || die "--with requires a module (gloebit)"
		WITH_MODULES+=("${argument#*=}")
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--connection)
		(($#)) || die "--connection requires a name (or local|none)"
		[[ "$1" != -* ]] || die "--connection requires a name (or local|none)"
		[[ "$PODMAN_CONNECTION_SELECTED" == no ]] || die "--connection can be specified only once"
		PODMAN_CONNECTION=$1
		REMOTE_ARGS+=("$1")
		shift
		PODMAN_CONNECTION_SELECTED=yes
		case "$PODMAN_CONNECTION" in local | none) PODMAN_FORCE_LOCAL=yes ;; esac
		;;
	--connection=*)
		[[ "$PODMAN_CONNECTION_SELECTED" == no ]] || die "--connection can be specified only once"
		PODMAN_CONNECTION=${argument#*=}
		[[ -n "$PODMAN_CONNECTION" ]] || die "--connection requires a name (or local|none)"
		PODMAN_CONNECTION_SELECTED=yes
		case "$PODMAN_CONNECTION" in local | none) PODMAN_FORCE_LOCAL=yes ;; esac
		;;
	--image)
		(($#)) || die "--image requires an image name"
		[[ "$1" != -* ]] || die "--image requires an image name"
		PODMAN_IMAGE=$1
		PODMAN_IMAGE_SELECTED=yes
		REMOTE_ARGS+=("$1")
		shift
		;;
	--image=*)
		PODMAN_IMAGE=${argument#*=}
		[[ -n "$PODMAN_IMAGE" ]] || die "--image requires an image name"
		PODMAN_IMAGE_SELECTED=yes
		;;
	-y | --yes)
		ASSUME_YES=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--edit-vhosts)
		EDIT_VHOSTS=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--testing)
		OPENSIM_KIT_APT_DIST=charm-tests
		OPENSIM_KIT_APT_COMPONENT=
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--unstable)
		UNSTABLE=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--tools)
		[[ "$PHASE_SELECTED" == no ]] || die "choose only one installation phase"
		PHASE_SELECTED=yes
		INSTALL_PHASE=tools
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--cleanup)
		RUN_CLEANUP=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--in-place | --migrate | --new)
		[[ -z "$LEGACY_MODE" || "$LEGACY_MODE" == "${argument#--}" ]] || die "choose one of --migrate, --in-place, --new"
		LEGACY_MODE=${argument#--}
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--restart)
		LEGACY_RESTART=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--show-passwords)
		SHOW_PASSWORDS=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--setup)
		RUN_SETUP=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		;;
	--config)
		(($#)) || die "--config requires a JSON setup file"
		[[ "$1" != -* ]] || die "--config requires a JSON setup file"
		SETUP_CONFIG_FILE=$1
		REMOTE_ARGS+=("$1")
		shift
		;;
	--config=*)
		SETUP_CONFIG_FILE=${argument#*=}
		[[ -n "$SETUP_CONFIG_FILE" ]] || die "--config requires a JSON setup file"
		;;
	--region-config)
		(($#)) || die "--region-config requires a Region.ini file"
		[[ "$1" != -* ]] || die "--region-config requires a Region.ini file"
		REGION_CONFIG_FILE=$1
		REMOTE_ARGS+=("$1")
		shift
		;;
	--region-config=*)
		REGION_CONFIG_FILE=${argument#*=}
		[[ -n "$REGION_CONFIG_FILE" ]] || die "--region-config requires a Region.ini file"
		;;
	--dependencies | --mariadb | --mysql | --dotnet | --opensim)
		[[ "$PHASE_SELECTED" == no ]] || die "choose only one installation phase"
		PHASE_SELECTED=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		case "$argument" in
		--dependencies) INSTALL_PHASE=dependencies ;;
		--mariadb)
			INSTALL_PHASE=mariadb
			DATABASE_CHOICE=mariadb
			;;
		--mysql)
			INSTALL_PHASE=mysql
			DATABASE_CHOICE=mysql
			;;
		--dotnet) INSTALL_PHASE=dotnet ;;
		--opensim) INSTALL_PHASE=opensim ;;
		esac
		;;
	-h | --help)
		sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-d | --debug | -v | --verbose)
		DEBUG=yes
		;;
	*)
		error "unknown option $argument (see --help)" >&2
		exit 2
		;;
	esac
done
case "$INSTALL_PHASE" in
all | dependencies | mariadb | mysql | dotnet | opensim | tools) ;;
*) die "invalid installation phase $INSTALL_PHASE" ;;
esac
[[ "$INSTALL_PHASE" == all || "$INSTALL_PHASE" == opensim ]] || [[ -z "$RUN_SETUP" ]] || die "--setup is only valid for the full install or --opensim"
# The sources and the packages again, with the options read (--testing, --unstable)
plan_packages
[[ "$PODMAN_CONNECTION_SELECTED" == no || "$PODMAN_MODE" == yes ]] || die "--connection requires --podman"
[[ "$PODMAN_IMAGE_SELECTED" == no || "$PODMAN_MODE" == yes ]] || die "--image requires --podman"

if [[ -n "$REMOTE_TARGET" ]]; then
	run_remote_install "$REMOTE_TARGET" "${REMOTE_ARGS[@]}"
	exit $?
fi

# Check if in a clone of the repository
here=
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
	here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
log here $here
clone=
[[ -n "$here" && -x "$here/bin/opensim" && -f "$here/composer.json" ]] && clone=$here
log clone $clone

if [[ "$PODMAN_MODE" == yes ]]; then
	run_podman_install "${PODMAN_INSTALL_ARGS[@]}"
	exit $?
fi

case "$(uname -s)" in Linux | Darwin) ;; *) die "unsupported system $(uname -s)" ;; esac

if [[ "$RUN_CLEANUP" == yes ]]; then
	[[ $(uname -s) == Linux ]] || die "cleanup is available on Debian and Ubuntu only"
	phase_cleanup
fi
say "w4os installer"
install_log >/dev/null
[[ $(uname -s) != Linux ]] || done_line "System: $(system_line)"
# Without apt (not Debian or Ubuntu): from a clone of the repository only
[[ -n "$clone" ]] || command -v apt-get >/dev/null 2>&1 ||
	die "w4os installs on Debian and Ubuntu; elsewhere, from a clone of its repository: git clone https://github.com/way4os/w4os-cli.git"
# The one question before the setup, whose scenario says what is here and asks the rest
if [[ "$INSTALL_PHASE" == all ]] && ! opening_question; then
	say "Stopped at your request: nothing changed."
	exit 0
fi
# A pre-existing install: never beside it silently (both would read /etc/opensim and start the same grids); its choice is the setup's
if [[ $(uname -s) == Linux && "$RUN_CLEANUP" != yes && -n "$(legacy_install)" ]]; then
	legacy_gate
fi

case "$INSTALL_PHASE" in
all)
	phase_dependencies || die "quick-install dependencies failed"
	if [[ $(uname -s) == Linux ]]; then
		phase_database || die "database phase failed"
	fi
	phase_opensim
	;;
dependencies) phase_dependencies || die "quick-install dependencies failed" ;;
mariadb | mysql) phase_database || die "database phase failed" ;;
dotnet) phase_dotnet || die ".NET phase failed" ;;
opensim) phase_opensim ;;
tools) phase_tools ;;
esac
