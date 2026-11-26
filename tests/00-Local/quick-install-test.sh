#!/usr/bin/env bash

QUICK_INSTALL_SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/kickstart.sh
QUICK_INSTALL_LIBRARY_LOADED=no

function quick_install_load_library() {
	if [[ "$QUICK_INSTALL_LIBRARY_LOADED" == yes ]]; then return 0; fi
	if ! bash -n "$QUICK_INSTALL"; then
		bashunit::skip 'quick-install syntax check failed'
		return 1
	fi
	# Nobody at a terminal: the questions take their default, the choices that need a person are refused
	KICKSTART_TTY_IN=$WORK/no-terminal KICKSTART_TTY_OUT=$WORK/no-terminal QUICK_INSTALL_LIBRARY_ONLY=yes OPENSIM_RC=/dev/null source "$QUICK_INSTALL"
	QUICK_INSTALL_LIBRARY_LOADED=yes
	# write_apt_repositories normally installs the generated file as root.
	as_root() { "$@"; }
}

function set_up() {
	WORK=$(mktemp -d)
	QUICK_INSTALL=$WORK/project/kickstart.sh
	mkdir -p "$WORK/project/bin" "$WORK/project/vendor"
	cp "$QUICK_INSTALL_SOURCE" "$QUICK_INSTALL"
	printf '{}\n' >"$WORK/project/composer.json"
	: >"$WORK/project/vendor/autoload.php"
	cat >"$WORK/project/bin/opensim" <<'SETUP'
#!/usr/bin/env bash
printf 'setup' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
shift
while (($#)); do
    case "$1" in
        --prepare) destination=$2; shift 2 ;;
        --config) config=$2; shift 2 ;;
        --region-config) region=$2; shift 2 ;;
        --apply) exit 0 ;;
        *) exit 2 ;;
    esac
done
[[ -n "${destination:-}" ]] || exit 0
if [[ -n "${config:-}" ]]; then
    [[ -z "${CAPTURED_SETUP:-}" ]] || cp "$config" "$CAPTURED_SETUP"
    if jq -e 'keys == ["hostname","occupied_ports"] or keys == ["occupied_ports"]' "$config" >/dev/null; then
        printf '{"identity":"test_grid","answers":{"type":"grid","name":"Test Grid"},"setup":{"grid":{"public_port":8012,"private_port":8013,"console_port":8014},"simulators":[{"http_port":9010,"console":"rest","console_port":9014,"regions":[{"port":9011}]}]},"port_bindings":[{"port":8012,"protocol":"tcp","use":"public","host_ip":null},{"port":8013,"protocol":"tcp","use":"private","host_ip":"127.0.0.1"},{"port":8014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"},{"port":9010,"protocol":"tcp","use":"public","host_ip":null},{"port":9011,"protocol":"udp","use":"public","host_ip":null},{"port":9014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"}]}\n' >"$destination"
    else
        jq -e '.identity' "$config" >/dev/null || { echo 'invalid setup config' >&2; exit 1; }
        jq '.port_bindings //= [{"port":8012,"protocol":"tcp","use":"public","host_ip":null}]' "$config" >"$destination"
    fi
else
    printf '{"identity":"test_grid","answers":{"type":"grid","name":"Test Grid"},"setup":{"grid":{"public_port":8012,"private_port":8013,"console_port":8014},"simulators":[{"http_port":9010,"console":"rest","console_port":9014,"regions":[{"port":9011}]}]},"port_bindings":[{"port":8012,"protocol":"tcp","use":"public","host_ip":null},{"port":8013,"protocol":"tcp","use":"private","host_ip":"127.0.0.1"},{"port":8014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"},{"port":9010,"protocol":"tcp","use":"public","host_ip":null},{"port":9011,"protocol":"udp","use":"public","host_ip":null},{"port":9014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"}]}\n' >"$destination"
fi
chmod 600 "$destination"
SETUP
	chmod +x "$WORK/project/bin/opensim"
	APT_SOURCE_FILE=$WORK/magiiic.list
	TMP=$WORK/quick-install
}

function tear_down() {
	rm -rf "$WORK"
}

function test_00_quick_install_has_valid_bash_syntax() {
	assert_exec "bash -n '$QUICK_INSTALL'"
}

function test_remote_install_copies_script_and_forwards_install_options() {
	quick_install_load_library || return
	local fake_bin=$WORK/bin calls=$WORK/remote-calls
	mkdir -p "$fake_bin"
	cat >"$fake_bin/scp" <<'SCP'
#!/usr/bin/env bash
printf 'scp' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
SCP
	cat >"$fake_bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf 'ssh' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [[ "$*" == *mktemp* ]]; then printf '/tmp/quick-install.test-session\n'; fi
SSH
	chmod +x "$fake_bin/scp" "$fake_bin/ssh"

	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' APT_SOURCE='deb https://packages.example.test/debian bookworm main' APT_SOURCE_TESTS='deb https://test.example.test/debian bookworm main' bash '$QUICK_INSTALL' --remote root@example.test --cleanup --opensim"
	local config="$WORK/Setup Answers.json" region="$WORK/Existing Region.ini"
	printf '{"type":"simulator"}\n' >"$config"
	printf '[Existing Region]\n' >"$region"
	: >"$calls"
	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' APT_SOURCE='deb https://packages.example.test/debian bookworm main' APT_SOURCE_TESTS='deb https://test.example.test/debian bookworm main' bash '$QUICK_INSTALL' --remote root@example.test --config '$config' --region-config='$region' --cleanup --opensim"
	assert_contains '<'"$config"'> <root@example.test:/tmp/quick-install.test-session/setup.json>' "$(cat "$calls")"
	assert_contains '<'"$region"'> <root@example.test:/tmp/quick-install.test-session/Region.ini>' "$(cat "$calls")"
	assert_contains '--config /tmp/quick-install.test-session/setup.json' "$(cat "$calls")"
	assert_contains '--region-config /tmp/quick-install.test-session/Region.ini' "$(cat "$calls")"
	assert_contains 'root@example.test' "$(cat "$calls")"
	assert_contains '--cleanup --opensim' "$(cat "$calls")"
	assert_contains 'APT_SOURCE=deb' "$(cat "$calls")"
	assert_contains 'packages.example.test/debian' "$(cat "$calls")"
	assert_contains 'APT_SOURCE_TESTS=deb' "$(cat "$calls")"
	assert_contains 'test.example.test/debian' "$(cat "$calls")"
	assert_contains 'scp' "$(cat "$calls")"
	assert_equals 3 "$(grep -c '^ssh ' "$calls")"
}

function test_confirmed_setup_is_applied_after_installation() {
	quick_install_load_library || return
	local calls=$WORK/apply-calls config="$WORK/Confirmed Setup.json"
	printf '{"version":1,"identity":"test_grid","answers":{},"setup":{}}\n' >"$config"
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	export CALL_LOG=$calls
	(end_installation) >/dev/null
	assert_contains '<setup> <--apply> <'"$config"'>' "$(cat "$calls")"
}

function test_unconfirmed_answers_keep_interactive_setup() {
	quick_install_load_library || return
	local calls=$WORK/prefill-calls config="$WORK/Setup Answers.json"
	printf '{"type":"grid"}\n' >"$config"
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	export CALL_LOG=$calls
	(end_installation) >/dev/null
	assert_contains '<setup> <--config> <'"$config"'>' "$(cat "$calls")"
}

function test_default_source_replaces_old_magiiic_distributions_and_preserves_other_sources() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$APT_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com unstable main
deb [trusted=yes] https://apt.magiiic.com tests main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com main stable
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable
deb [trusted=yes] https://apt.magiiic.com charm-tests dev
deb https://archive.ubuntu.com/ubuntu resolute main
SOURCES

	OPENSIM_KIT_APT_DIST=charm
	OPENSIM_KIT_APT_COMPONENT=stable
	APT_REPOSITORIES=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"

	assert_contains 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "$(cat "$APT_SOURCE_FILE")"
	assert_contains 'deb [trusted=yes] https://apt.magiiic.com charm-tests dev' "$(cat "$APT_SOURCE_FILE")"
	assert_contains 'deb https://archive.ubuntu.com/ubuntu resolute main' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com stable ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com unstable ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com tests ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com main ' "$(cat "$APT_SOURCE_FILE")"
}

function test_existing_components_are_merged_without_duplicates() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$APT_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable
SOURCES
	APT_REPOSITORIES=('deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable')
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"

	assert_equals 1 "$(grep -Fc 'https://apt.magiiic.com charm stable unstable' "$APT_SOURCE_FILE")"
}

function test_sources_are_updated_where_they_stand_and_added_only_when_missing() {
	quick_install_load_library || return
	local stable='deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable'
	local tests='deb [trusted=yes] https://apt.magiiic.com charm-tests dev'
	printf '%s\n' "$tests" "deb https://archive.ubuntu.com/ubuntu resolute main" "$stable" >"$APT_SOURCE_FILE"

	# What the user ordered stays: the test builds above, unchanged, nothing added
	APT_REPOSITORIES=("$stable")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "$tests"$'\n'"deb https://archive.ubuntu.com/ubuntu resolute main"$'\n'"$stable" "$(cat "$APT_SOURCE_FILE")"

	# A commented repository stays commented and in place until it is wanted, then it is enabled where it is
	printf '%s\n' "$stable" "# $tests" "deb https://archive.ubuntu.com/ubuntu resolute main" >"$APT_SOURCE_FILE"
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "$stable"$'\n'"# $tests"$'\n'"deb https://archive.ubuntu.com/ubuntu resolute main" "$(cat "$APT_SOURCE_FILE")"
	APT_REPOSITORIES=("$stable unstable" "$tests")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "$stable unstable"$'\n'"$tests"$'\n'"deb https://archive.ubuntu.com/ubuntu resolute main" "$(cat "$APT_SOURCE_FILE")"

	# A repository missing from the file is added at the end, once
	printf '%s\n' "deb https://archive.ubuntu.com/ubuntu resolute main" >"$APT_SOURCE_FILE"
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "deb https://archive.ubuntu.com/ubuntu resolute main"$'\n'"$stable unstable"$'\n'"$tests" "$(cat "$APT_SOURCE_FILE")"
}

function test_default_apt_repository_is_charm_stable() {
	local APT_SOURCE= APT_SOURCE_TESTS=
	QUICK_INSTALL_LIBRARY_LOADED=no
	quick_install_load_library || return
	assert_equals 1 "${#APT_REPOSITORIES[@]}"
	assert_equals 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "${APT_REPOSITORIES[0]}"
}

function test_unstable_adds_the_betas_and_testing_adds_the_test_builds_and_unstable() {
	local APT_SOURCE= APT_SOURCE_TESTS=
	QUICK_INSTALL_LIBRARY_LOADED=no
	quick_install_load_library || return
	local stable='deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable'
	local tests='deb [trusted=yes] https://apt.magiiic.com charm-tests dev'

	OPENSIM_KIT_APT_DIST=charm OPENSIM_KIT_APT_COMPONENT= UNSTABLE=
	plan_packages
	assert_equals 1 "${#APT_REPOSITORIES[@]}"
	assert_equals "$stable" "${APT_REPOSITORIES[0]}"

	UNSTABLE=yes
	plan_packages
	assert_equals 1 "${#APT_REPOSITORIES[@]}"
	assert_equals "$stable unstable" "${APT_REPOSITORIES[0]}"

	OPENSIM_KIT_APT_DIST=charm-tests OPENSIM_KIT_APT_COMPONENT= UNSTABLE=
	plan_packages
	assert_equals "$stable unstable" "${APT_REPOSITORIES[0]}"
	assert_equals "$tests" "${APT_REPOSITORIES[1]}"
}

function test_tools_install_the_command_line_alone_without_what_it_recommends() {
	quick_install_load_library || return
	local calls=$WORK/install-calls
	configure_package_sources() { return 0; }
	install_packages() { printf '%s\n' "$*" >>"$calls"; }
	opensim() { return 0; }
	phase_tools >/dev/null
	assert_equals '--no-install-recommends w4os-cli' "$(cat "$calls")"
}

function test_with_installs_the_package_of_a_module_for_each_core_and_enables_it() {
	quick_install_load_library || return
	local calls=$WORK/install-calls
	OPENSIM_CORES_ROOT=$WORK/cores
	mkdir -p "$OPENSIM_CORES_ROOT/0.9.3.0/bin" "$OPENSIM_CORES_ROOT/empty/bin" "$OPENSIM_CORES_ROOT/unstable/bin"
	touch "$OPENSIM_CORES_ROOT/0.9.3.0/bin/OpenSim.dll" "$OPENSIM_CORES_ROOT/unstable/bin/OpenSim.dll"
	install_packages() { printf 'install %s\n' "$*" >>"$calls"; }
	as_root() { printf 'root %s\n' "$*" >>"$calls"; }
	WITH_MODULES=(gloebit)
	install_with_modules
	assert_equals "install opensim-0.9.3.0-gloebit opensim-unstable-gloebit
root php /usr/share/w4os-engine/bin/opensim-profiles.php --enable-module gloebit" "$(cat "$calls")"
}

function test_without_with_the_kit_installs_no_module_of_its_own() {
	quick_install_load_library || return
	local calls=$WORK/install-calls
	install_packages() { printf 'install %s\n' "$*" >>"$calls"; }
	as_root() { printf 'root %s\n' "$*" >>"$calls"; }
	WITH_MODULES=()
	install_with_modules
	assert_file_not_exists "$calls"
}

function test_apt_source_parser_accepts_multiword_options() {
	quick_install_load_library || return
	local source='deb [arch=amd64 signed-by=/usr/share/keyrings/example.gpg] https://packages.example.test/debian bookworm main'
	assert_equals 3 "$(apt_source_uri_index "$source")"
	APT_REPOSITORIES=("$source")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "$source" "$(cat "$APT_SOURCE_FILE")"
}

function test_custom_apt_source_does_not_fetch_magiiic_signing_key() {
	quick_install_load_library || return
	local key_downloaded=no
	APT_REPOSITORIES=('deb https://packages.example.test/debian bookworm main')
	APT_SOURCE_FILE=$WORK/custom.list
	PACKAGE_SOURCES_READY=no
	apt-get() { return 0; }
	dpkg-query() { printf 'installed\n'; }
	apt_update() { return 0; }
	as_root() { return 0; }
	uname() { printf 'Linux\n'; }
	curl() {
		key_downloaded=yes
		return 1
	}
	configure_package_sources
	unset -f apt-get dpkg-query apt_update as_root uname curl
	assert_equals no "$key_downloaded"
}

function test_database_passwords_are_quoted_as_sql_literals() {
	quick_install_load_library || return
	local sql=$WORK/accounts.sql
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	mariadb() {
		if [[ "${1:-}" == -Nse ]]; then return 0; else cat >"$sql"; fi
	}
	OPENSIM_DB_ADMIN_USER=example_admin OPENSIM_DB_ADMIN_PASS="ad'min"
	OPENSIM_DB_USER=example_user OPENSIM_DB_PASS="p'ass\\word"
	phase_database
	assert_contains "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';" "$(cat "$sql")"
	assert_contains "IDENTIFIED BY 'ad''min';" "$(cat "$sql")"
	assert_contains "IDENTIFIED BY 'p''ass\\word';" "$(cat "$sql")"
}

function test_dotnet_phase_requests_libgdiplus_directly_from_apt_when_missing() {
	quick_install_load_library || return
	recover_dpkg_configuration() { return 0; }
	apt_update() { return 0; }
	uname() { printf 'Linux\n'; }
	ldconfig() { return 1; }
	dotnet_target_majors() { printf '8\n'; }
	dotnet_runtime_package() { printf 'dotnet-runtime-%s.0\n' "$1"; }
	dotnet_runtime_installed() { return 1; }
	local installed_packages
	install_packages() { installed_packages="$*"; }
	phase_dotnet
	unset -f recover_dpkg_configuration apt_update uname ldconfig dotnet_target_majors dotnet_runtime_package dotnet_runtime_installed install_packages
	assert_contains 'dotnet-runtime-8.0' "$installed_packages"
	assert_contains 'libgdiplus' "$installed_packages"
}

function test_dotnet_target_majors_are_the_ones_the_cores_target() {
	quick_install_load_library || return
	mkdir -p "$WORK/cores/0.9.3.0/bin" "$WORK/cores/0.9.3.1/bin" "$WORK/cores/0.9.2.2/bin"
	printf '{\n  "runtimeOptions": {\n    "tfm": "net8.0",\n    "framework": {\n      "name": "Microsoft.NETCore.App",\n      "version": "8.0.0"\n    }\n  }\n}\n' >"$WORK/cores/0.9.3.0/bin/OpenSim.runtimeconfig.json"
	cp "$WORK/cores/0.9.3.0/bin/OpenSim.runtimeconfig.json" "$WORK/cores/0.9.3.1/bin/"
	assert_equals '8' "$(dotnet_target_majors "$WORK/cores")"
}

function test_dotnet_runtime_detection_accepts_apt_candidate_with_pipefail() {
	quick_install_load_library || return
	local line
	apt-cache() {
		printf 'dotnet-runtime-8.0:\n  Installed: (none)\n  Candidate: 8.0.34-0ubuntu1~26.04.1\n  Version table:\n'
		for ((line = 0; line < 4096; line++)); do printf '    available version %s\n' "$line"; done
	}
	assert_exec 'dotnet_runtime_package 8' --stdout 'dotnet-runtime-8.0'
	unset -f apt-cache
}

function test_clone_install_requests_all_packages_when_cli_and_engine_are_installed() {
	quick_install_load_library || return
	local calls=$WORK/install-calls
	clone=$WORK/project
	APT_SOURCE_DIR=
	OPENSIM_KIT_APT_DIST=charm
	uname() { printf 'Linux\n'; }
	dpkg-query() {
		case "$*" in
		*w4os-cli* | *w4os-engine*) printf 'installed\n' ;;
		*) return 1 ;;
		esac
	}
	configure_package_sources() { return 0; }
	install_packages() { printf '%s\n' "$*" >>"$calls"; }
	apt_update() { return 0; }
	end_installation() { return 0; }
	phase_dotnet() { return 0; }
	phase_opensim
	installed="$(cat "$calls")"
	# The kit: the command line, the engine, the website of a grid, the latest core and its modules
	assert_contains 'opensim-kit' "$installed"
	assert_not_contains 'opensim-unstable' "$installed"
	assert_contains 'libsqlite3-0' "$installed"
	assert_contains 'mariadb-server' "$installed"
	assert_contains 'php-cli' "$installed"
	assert_contains 'php-curl' "$installed"
	assert_contains 'php-intl' "$installed"
	assert_contains 'php-mbstring' "$installed"
	assert_contains 'php-mysql' "$installed"
	assert_contains 'php-xml' "$installed"
	assert_contains 'composer' "$installed"
	assert_contains 'git' "$installed"
	assert_contains 'unzip' "$installed"
	# assert_contains 'screen' "$installed"
	assert_contains 'openssh-server' "$installed"
	assert_contains 'libgdiplus' "$installed"
}

function test_dotnet_installer_installs_the_major_the_cores_target_beside_a_newer_one() {
	quick_install_load_library || return
	PGM=quick-install
	local calls=$WORK/dotnet-installer-calls runtime_checks=0
	recover_dpkg_configuration() { return 0; }
	apt_update() { return 0; }
	uname() { printf 'Linux\n'; }
	dotnet_target_majors() { printf '8\n'; }
	dotnet_runtime_package() { return 1; }
	ldconfig() { printf 'libicuuc.so.76\nlibgdiplus.so.0\n'; }
	dpkg-query() { printf 'installed\n'; }
	# .NET 10 only at first: never taken for 8
	dotnet_runtime_installed() {
		((runtime_checks += 1))
		((runtime_checks >= 2))
	}
	curl() {
		local output
		while (($#)); do
			if [[ "$1" == -o ]]; then
				output=$2
				shift 2
			else shift; fi
		done
		printf '#!/usr/bin/env bash\nexit 0\n' >"$output"
	}
	as_root() {
		printf '%q ' "$@" >>"$calls"
		printf '\n' >>"$calls"
		[[ "$1" != bash ]] || "$@"
	}
	phase_dotnet
	local output
	output=$(cat "$calls")
	unset -f recover_dpkg_configuration apt_update uname dotnet_target_majors dotnet_runtime_package ldconfig dpkg-query dotnet_runtime_installed curl as_root
	assert_contains '--channel 8.0' "$output"
	assert_contains '--install-dir /usr/local/share/dotnet' "$output"
	assert_contains '--azure-feed https://builds.dotnet.microsoft.com/dotnet' "$output"
}

function test_confirmed_setup_ends_with_the_summary_of_the_setup_alone() {
	quick_install_load_library || return
	local config="$WORK/Confirmed Setup.json"
	cat >"$config" <<'JSON'
{"version":1,"identity":"test_grid","answers":{"type":"grid","name":"Test Grid","avatar":"Ada Resident"},"setup":{"grid":{"name":"Test Grid","hostname":"grid.example.test","public_port":8123},"simulators":[]}}
JSON
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	local said
	said=$( (end_installation) 2>&1)
	assert_not_contains "Setup summary" "$said"
	assert_not_contains "Installation completed" "$said"
}

function test_cleanup_takes_out_the_web_server_configs_that_use_the_files_it_removes() {
	quick_install_load_library || return 0
	local root=$WORK/machine
	mkdir -p "$root/etc/opensim/grids/vonda/web" "$root/etc/caddy/sites" "$root/etc/apache2/sites-enabled" "$root/other"
	: >"$root/etc/opensim/grids/vonda/web/vonda.caddyfile"
	ln -s "$root/etc/opensim/grids/vonda/web/vonda.caddyfile" "$root/etc/caddy/sites/vonda.caddyfile"
	ln -s "$root/other/site.caddyfile" "$root/etc/caddy/sites/other.caddyfile"
	printf 'example.org {\n\troot * /srv\n}\nimport %s/etc/opensim/grids/vonda/web/vonda.caddyfile\n' "$root" >"$root/etc/caddy/Caddyfile"
	printf '<VirtualHost *:80>\n\tInclude %s/other/site.conf\n</VirtualHost>\n' "$root" >"$root/etc/apache2/sites-enabled/site.conf"

	local found
	found=$(WEB_CONFIG_DIRS="$root/etc/caddy $root/etc/apache2" web_references "$root/etc/opensim" "$root/var/lib/opensim")
	remove_web_references "$found" >/dev/null

	assert_same "$(printf 'line %s/etc/caddy/Caddyfile:4\nlink %s/etc/caddy/sites/vonda.caddyfile' "$root" "$root")" "$(sort <<<"$found")"
	assert_file_not_exists "$root/etc/caddy/sites/vonda.caddyfile"
	assert_contains "# Removed by the OpenSim cleanup: import $root/etc/opensim" "$(cat "$root/etc/caddy/Caddyfile")"
	# What uses other files stays as it is
	assert_same "$root/other/site.caddyfile" "$(readlink "$root/etc/caddy/sites/other.caddyfile")"
	assert_contains "Include $root/other/site.conf" "$(cat "$root/etc/apache2/sites-enabled/site.conf")"
}

function test_a_package_gone_while_it_is_installed_is_installed_once_more_after_the_lists_are_read_again() {
	quick_install_load_library || return 0
	local calls=$WORK/apt-calls
	as_root() {
		printf '%s\n' "$*" >>"$calls"
		if [[ "$*" == *"apt-get install"* && $(grep -c 'apt-get install' "$calls") -eq 1 ]]; then
			echo "E: Failed to fetch https://apt.example.org/pool/w4os-engine_3.0.0~beta.13+459.g58a36c1_all.deb  404  Not Found [IP: 192.0.2.1 443]"
			return 100
		fi
	}
	APT_UPDATED=yes DEBUG=

	local said status=0
	said=$(apt_install w4os-cli 2>&1) || status=$?

	assert_same 0 "$status"
	assert_same "$(printf 'env LC_ALL=C apt-get install -y -qq w4os-cli\napt-get update -qq\nenv LC_ALL=C apt-get install -y -qq w4os-cli')" "$(cat "$calls")"
	assert_contains "the package lists are read again" "$said"
}

function test_an_install_that_fails_otherwise_is_not_tried_again() {
	quick_install_load_library || return 0
	local calls=$WORK/apt-calls
	as_root() {
		printf '%s\n' "$*" >>"$calls"
		echo "E: Unable to locate package w4os-nothing"
		return 100
	}

	local status=0
	apt_install w4os-nothing >/dev/null 2>&1 || status=$?

	assert_same 100 "$status"
	assert_same "env LC_ALL=C apt-get install -y -qq w4os-nothing" "$(cat "$calls")"
}

function test_the_sql_account_of_an_existing_grid_is_never_shadowed_by_one_for_localhost() {
	quick_install_load_library || return
	local sql=$WORK/accounts.sql
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	# The grid of another install logs in as 'opensim'@'%'
	mariadb() {
		if [[ "${1:-}" == -Nse ]]; then
			[[ "$2" != *"User='opensim'"* ]] || printf '%%\n'
			return 0
		fi
		cat >"$sql"
	}
	unset OPENSIM_DB_USER OPENSIM_DB_PASS OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS

	local said
	said=$(phase_database; printf 'user=%s\n' "$OPENSIM_DB_USER")

	assert_not_contains "CREATE USER 'opensim'@" "$(cat "$sql")"
	assert_contains "CREATE USER 'opensim_w4os'@'localhost'" "$(cat "$sql")"
	assert_contains "user=opensim_w4os" "$said"
	assert_contains "SQL account opensim exists (another install's): the kit uses opensim_w4os" "$said"
}

function test_an_account_name_asked_for_that_exists_needs_its_password() {
	quick_install_load_library || return
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	mariadb() { [[ "${1:-}" == -Nse && "$2" == *"User='grid_user'"* ]] && printf '%%\n'; return 0; }
	unset OPENSIM_DB_PASS OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS
	OPENSIM_DB_USER=grid_user PGM=kickstart.sh

	local said status=0
	said=$(phase_database 2>&1) || status=$?

	assert_same 1 "$status"
	assert_contains "SQL account grid_user already exists; set OPENSIM_DB_PASS" "$said"
}

# An install of before the kit in a temporary folder: its helpers, its cron, a unit of its own, a Robust and a simulator
function legacy_fixture() {
	LEGACY_ROOT=$WORK/opt/opensim LEGACY_CRON=$WORK/cron.hourly/opensim LEGACY_UNITS="$WORK/systemd/opensim.service"
	mkdir -p "$LEGACY_ROOT/lib" "$LEGACY_ROOT/etc/robust.d" "$LEGACY_ROOT/etc/opensim.d" "$WORK/cron.hourly" "$WORK/systemd"
	: >"$LEGACY_ROOT/lib/os-helpers"
	printf '#!/bin/sh\n%s/bin/opensim start\n' "$LEGACY_ROOT" >"$LEGACY_CRON"
	printf '[Service]\nExecStart=%s/bin/opensim start\n' "$LEGACY_ROOT" >"$WORK/systemd/opensim.service"
	printf '[GridInfoService]\n    gridnick = "W4osDemoGrid"\n' >"$LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini"
	: >"$LEGACY_ROOT/etc/opensim.d/w4osdemogrid_welcome.ini"
	PGM=kickstart.sh LEGACY_RESTART= clone=
}

function test_beside_an_install_of_before_the_kit_nothing_happens_without_a_choice() {
	quick_install_load_library || return
	legacy_fixture
	LEGACY_MODE=

	local said status=0
	said=$(legacy_gate 2>&1) || status=$?

	assert_same 1 "$status"
	assert_contains "Found an existing install in $LEGACY_ROOT: grid w4osdemogrid, 1 simulator." "$said"
	assert_contains "--migrate, --in-place or --new" "$said"
	assert_file_exists "$LEGACY_CRON"
}

function test_in_place_sets_its_own_start_aside_and_registers_its_grid() {
	quick_install_load_library || return
	legacy_fixture
	LEGACY_MODE=in-place
	as_root() { "$@"; }
	local calls=$WORK/opensim-calls
	clone=$WORK/kit
	mkdir -p "$clone/bin"
	printf '#!/bin/sh\necho "$*" >>%s\n' "$calls" >"$clone/bin/opensim"
	chmod +x "$clone/bin/opensim"

	local said
	said=$(legacy_gate && legacy_after_install)

	assert_file_not_exists "$LEGACY_CRON"
	assert_file_exists "$LEGACY_CRON.w4os-disabled"
	assert_file_exists "$WORK/systemd/opensim.service.w4os-disabled"
	assert_contains "✓ Old install: its start at boot set aside" "$said"
	assert_same "$(printf 'import --robust %s --in-place --simulator %s --apply\nenable w4osdemogrid' "$LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini" "$LEGACY_ROOT/etc/opensim.d/w4osdemogrid_welcome.ini")" "$(cat "$calls")"
	assert_contains "✓ In place: w4osdemogrid" "$said"
}

function test_no_install_of_before_the_kit_changes_nothing() {
	quick_install_load_library || return
	LEGACY_ROOT=$WORK/none LEGACY_CRON=$WORK/none/cron LEGACY_MODE=

	assert_same "" "$(legacy_install)"
	legacy_gate
}

function test_the_sql_accounts_are_shown_before_anything_is_changed_their_passwords_masked() {
	quick_install_load_library || return
	local sql=$WORK/accounts.sql
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	mariadb() {
		if [[ "${1:-}" == -Nse ]]; then
			[[ "$2" != *"User='opensim'"* ]] || printf '%%\n'
			return 0
		fi
		cat >"$sql"
	}
	unset OPENSIM_DB_USER OPENSIM_DB_PASS OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS
	OPENSIM_RC_PATH=$WORK/no-rc SHOW_PASSWORDS=

	local said shown
	said=$(phase_database)
	shown=$(SHOW_PASSWORDS=yes OPENSIM_DB_PASS=visible-secret OPENSIM_DB_USER=kit_user phase_database)

	assert_contains "SQL accounts: opensim_admin, opensim_w4os (passwords generated)" "$said"
	assert_contains "SQL account opensim exists (another install's): the kit uses opensim_w4os" "$said"
	assert_not_contains "visible-secret" "$said"
	assert_contains "kit_user: visible-secret" "$shown"
}

function test_an_existing_sql_account_is_used_only_with_its_own_password() {
	quick_install_load_library || return
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	# The account opensim exists; its own password is grid-secret
	mariadb() {
		if [[ "${1:-}" == -Nse ]]; then [[ "$2" != *"User='opensim'"* ]] || printf '%%\n'; return 0; fi
		if [[ "${1:-}" == -u ]]; then [[ "${MYSQL_PWD:-}" == grid-secret ]]; return; fi
		cat >/dev/null
	}
	unset OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS
	OPENSIM_RC_PATH=$WORK/no-rc PGM=kickstart.sh OPENSIM_DB_USER=opensim

	local refused status=0
	refused=$(OPENSIM_DB_PASS=wrong phase_database 2>&1) || status=$?

	assert_same 1 "$status"
	assert_contains "SQL account opensim: its password (given (environment)) is refused" "$refused"
	assert_successful_code "$(OPENSIM_DB_PASS=grid-secret phase_database >/dev/null 2>&1; echo $?)"
}

function test_in_place_restart_stops_the_old_robust_by_the_file_it_runs_and_says_what_does_not_run() {
	quick_install_load_library || return
	# The processes are read in /proc: Linux
	[[ -d /proc/self ]] || return 0
	legacy_fixture
	LEGACY_MODE=in-place LEGACY_RESTART=yes
	as_root() { "$@"; }
	systemctl() { echo "systemctl $*" >>"$WORK/opensim-calls"; }
	# robust.d names the file of its grid by a link; the old Robust runs that file, with a REST console (no screen)
	mkdir -p "$LEGACY_ROOT/etc/grids/W4osDemoGrid"
	mv "$LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini" "$LEGACY_ROOT/etc/grids/W4osDemoGrid/Robust.HG.ini"
	ln -s "$LEGACY_ROOT/etc/grids/W4osDemoGrid/Robust.HG.ini" "$LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini"
	# As opensim-debian runs it (a command built then run through eval): the link of robust.d, in quotes that stay in the argument
	perl -e 'sleep 300' -- "-inifile='$LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini'" -console rest >/dev/null 2>&1 &
	local old=$!
	# A simulator given its config relative to its folder
	(cd "$LEGACY_ROOT/etc/opensim.d" && exec perl -e 'sleep 300' -- -inifile w4osdemogrid_welcome.ini >/dev/null 2>&1) &
	local sim=$!
	clone=$WORK/kit
	mkdir -p "$clone/bin"
	# What the suite says of its instances once restarted: its Robust down
	cat >"$clone/bin/opensim" <<-STATUS
	#!/bin/sh
	echo "\$*" >>$WORK/opensim-calls
	[ "\$1" = status ] && printf 'INSTANCE TYPE PID\nw4osdemogrid robust [down]\nw4osdemogrid.welcome opensim 42\n'
	exit 0
	STATUS
	chmod +x "$clone/bin/opensim"
	local said status=0
	said=$(legacy_gate && legacy_after_install 2>&1) || status=$?
	local alive=no
	if kill -0 "$old" 2>/dev/null || kill -0 "$sim" 2>/dev/null; then alive=yes; fi
	kill "$old" "$sim" 2>/dev/null || true

	assert_same no "$alive"
	assert_same 1 "$status"
	assert_contains "not started under the kit: w4osdemogrid" "$said"
	assert_not_contains "runs under the kit" "$said"
}

function test_a_question_is_always_shown_takes_its_default_on_enter_and_asks_again_a_wrong_letter() {
	quick_install_load_library || return
	local answers=$WORK/answers screen=$WORK/screen first=0 second=0
	printf '\nx\nn\n' >"$answers"
	TTY_IN=$answers TTY_OUT=$screen TTY_OPEN= ASSUME_YES=

	ask "Install?" || first=$?
	ask "Again?" || second=$?

	assert_same 0 "$first"
	assert_same 1 "$second"
	assert_contains "? Install? [Y/n] " "$(cat "$screen")"
	assert_same 3 "$(grep -o '? [A-Z][a-z]*?' "$screen" | wc -l | tr -d ' ')"
}

function test_beside_an_install_of_before_the_kit_the_choice_is_asked_and_a_new_grid_leaves_it_starting() {
	quick_install_load_library || return
	legacy_fixture
	LEGACY_MODE=
	local answers=$WORK/answers screen=$WORK/screen
	printf 'n\n' >"$answers"
	TTY_IN=$answers TTY_OUT=$screen TTY_OPEN= ASSUME_YES=
	as_root() { "$@"; }

	legacy_gate >/dev/null

	assert_same new "$LEGACY_MODE"
	assert_contains "[M]igrate  [I]n place  [N]ew grid beside it  [A]bort (M/i/n/a):" "$(cat "$screen")"
	assert_file_exists "$LEGACY_CRON"
	assert_file_exists "$WORK/systemd/opensim.service.w4os-disabled"
}

# A command line of the kit that says the plan of a migration and keeps what it is asked to do
function migration_stub() {
	clone=$WORK/kit
	mkdir -p "$clone/bin"
	cat >"$clone/bin/opensim" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
"api GET") [[ -f "$WORK/here" ]] && echo '{"data":{"attributes":{"name":"Kimbe Red","uri":"kimbe.example:8002"}}}' || exit 1 ;;
"api POST") cat >/dev/null; echo '{"data":{"attributes":{"name":"Kimbe Red","grid":"w4osdemogrid","ports":{"public":8002,"private":8003},"gridInfo":["[GridInfoService] gridname '"'Kimbé Red'"' -> '"'Kimbe Red'"': OpenSim cannot"],"site":"https://kimbe.example/opensim/","data":[],"problems":{}}}}' ;;
"status w4osdemogrid") [[ -f "$WORK/up" ]] && echo "w4osdemogrid  robust  [up]" ;;
*) echo "\$*" >>"$WORK/opensim-calls"; [[ "\$1" != import ]] || : >"$WORK/here" ;;
esac
STUB
	chmod +x "$clone/bin/opensim"
	as_root() { "$@"; }
	maptiles_package() { :; }
	website_possible() { return 1; }
	PROC_ROOT=$WORK/proc INSTALL_LOG=$WORK/install.log
	mkdir -p "$PROC_ROOT"
	: >"$INSTALL_LOG"
}

function test_a_migration_asks_everything_first_then_runs_the_import_with_the_name_chosen() {
	quick_install_load_library || return
	legacy_fixture
	migration_stub
	LEGACY_MODE=migrate
	local said answers=$WORK/answers screen=$WORK/screen
	# The ASCII name refused, another given, then the start
	printf 'n\nKimbe Rouge\n\n' >"$answers"
	TTY_IN=$answers TTY_OUT=$screen TTY_OPEN= ASSUME_YES=

	said=$(legacy_after_install)

	assert_same "import --robust $LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini --apply --switch --grid-name Kimbe Rouge --simulator $LEGACY_ROOT/etc/opensim.d/w4osdemogrid_welcome.ini" "$(cat "$WORK/opensim-calls")"
	assert_contains '? Grid name "Kimbé Red" becomes "Kimbe Red" (viewers need ASCII). OK? [Y/n] ? Grid name: [Kimbe Red] ? Start? [Y/n]' "$(cat "$screen")"
	assert_contains "✓ Old config readable (2 files)" "$said"
	assert_contains "✓ Migrated and started: w4osdemogrid" "$said"
	assert_contains "Grid       Kimbe Red (w4osdemogrid)" "$said"
	assert_contains "Login      http://kimbe.example:8002" "$said"
	assert_contains "Old install  $LEGACY_ROOT, stopped, kept" "$said"
	assert_not_contains "opensim import" "$said"
}

function test_a_migration_refused_at_start_changes_nothing() {
	quick_install_load_library || return
	legacy_fixture
	migration_stub
	LEGACY_MODE=migrate
	local said answers=$WORK/answers
	printf '\nn\n' >"$answers"
	TTY_IN=$answers TTY_OUT=$WORK/screen TTY_OPEN= ASSUME_YES=

	said=$(legacy_after_install)

	assert_file_not_exists "$WORK/opensim-calls"
	assert_contains "Stopped: nothing changed." "$said"
}

function test_a_rerun_says_a_grid_migrated_already_and_starts_one_written_only() {
	quick_install_load_library || return
	legacy_fixture
	migration_stub
	LEGACY_MODE=migrate ASSUME_YES=yes
	: >"$WORK/here"
	: >"$WORK/up"
	local said
	said=$(legacy_after_install)
	assert_contains "w4osdemogrid is already here. Nothing to do." "$said"
	assert_contains "Grid       Kimbe Red (w4osdemogrid)" "$said"
	assert_file_not_exists "$WORK/opensim-calls"

	rm "$WORK/up"
	said=$(legacy_after_install)
	assert_contains "w4osdemogrid is written here, not started yet." "$said"
	assert_same "import --robust $LEGACY_ROOT/etc/robust.d/W4osDemoGrid.ini --switch" "$(cat "$WORK/opensim-calls")"
}

function test_a_long_step_that_fails_says_its_log_then_retries_when_asked() {
	quick_install_load_library || return
	local said status=0 answers=$WORK/answers screen=$WORK/screen
	INSTALL_LOG=$WORK/install.log
	: >"$INSTALL_LOG"

	said=$(run_step "Thing" - false 2>&1) || status=$?
	printf 'r\n' >"$answers"
	TTY_IN=$answers TTY_OUT=$screen TTY_OPEN= ASSUME_YES=
	flaky() { [[ -f "$WORK/once" ]] || { : >"$WORK/once"; return 1; }; }
	local retried=0
	run_step "Other" - flaky >/dev/null || retried=$?

	assert_same 1 "$status"
	assert_contains "✗ Thing" "$said"
	assert_contains "Log: $WORK/install.log" "$said"
	assert_same 0 "$retried"
	assert_contains "[R]etry  [A]bort (R/a):" "$(cat "$screen")"
}

function test_the_packages_being_installed_are_counted_from_what_dpkg_says() {
	quick_install_load_library || return
	INSTALL_LOG=$WORK/install.log PACKAGES_TOTAL=3 PACKAGES_FROM=6
	printf 'before\nUnpacking a (1.0) ...\nSetting up a (1.0) ...\nUnpacking b:amd64 (2) ...\n' >"$INSTALL_LOG"

	assert_same "1/3 b" "$(packages_counter)"
}
