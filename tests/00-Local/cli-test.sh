#!/usr/bin/env bash
# Integration tests for w4os-cli
#
# Run with: composer test
#
# These tests confirm the current state:
# - Locally: ./bin/opensim commands work

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK"
	unset OPENSIM_CONF OPENSIM_RC
	export OPENSIM_SYSTEM_USER=
	mkdir -p "$WORK/bin" "$WORK/etc/opensim/opensim.d"
	cat >"$WORK/.w4os.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc/opensim
		SystemUser =
	INI
}

function tear_down() {
	[[ -z "${CONSOLE_PID:-}" ]] || kill "$CONSOLE_PID" 2>/dev/null || true
	rm -rf "$WORK"
}

function make_test_grid() {
	mkdir -p "$WORK/etc/opensim/grids/tender_tern/sims"
	cat >"$WORK/etc/opensim/grids/tender_tern/Robust.ini" <<'INI'
[Const]
BaseURL = "http://127.0.0.1:8002"
[GridInfoService]
gridname = "Tender Tern"
INI
	cat >"$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" <<'INI'
[Network]
http_listener_port = 9000
console_port = 9004
INI
	cat >"$WORK/etc/opensim/grids/tender_tern/tender_tern.conf" <<'INI'
[Grid]
Center = 8002,8002
INI
}

function test_opensim_without_command_shows_usage() {
	local output
	output=$("$OPENSIM" 2>&1)
	assert_contains "usage: opensim" "$output"
	assert_contains "setup" "$output"
}

function test_layout_env_outputs_sourceable_system_and_current_identities() {
	local api="$WORK/w4os-api" etc_real var_real logs_real
	mkdir -p "$WORK/layout/etc-target" "$WORK/layout/var-target" "$WORK/layout/logs-target"
	ln -s "$WORK/layout/etc-target" "$WORK/layout/etc-link"
	ln -s "$WORK/layout/var-target" "$WORK/layout/var-link"
	ln -s "$WORK/layout/logs-target" "$WORK/layout/logs-link"
	etc_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/etc-link")
	var_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/var-link")
	logs_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/logs-link")
	export LAYOUT_ETC_ROOT="$WORK/layout/etc-link" LAYOUT_VAR_ROOT="$WORK/layout/var-link" LAYOUT_LOGS_ROOT="$WORK/layout/logs-link"
	cat >"$api" <<'API'
#!/usr/bin/env bash
[[ "$1 $2" == "GET /layout" ]] || exit 2
jq -cn --arg etc "$LAYOUT_ETC_ROOT" --arg var "$LAYOUT_VAR_ROOT" --arg logs "$LAYOUT_LOGS_ROOT" \
    '{data:{type:"layout",attributes:{systemUser:"opensim",systemUid:123,systemGroup:"opensim",systemGid:456,currentUser:"magic",currentUid:501,currentGroup:"staff",currentGid:20,etcRoot:$etc,varRoot:$var,logsRoot:$logs}}}'
API
	chmod +x "$api"
	assert_exec "OPENSIM_API='$api' '$OPENSIM' --layout --format=env" \
		--stdout-contains "OPENSIM_SYSTEM_USER='opensim'" \
		--stdout-contains "OPENSIM_SYSTEM_UID='123'" \
		--stdout-contains "OPENSIM_ADMIN_USER='magic'" \
		--stdout-contains "OPENSIM_ETC_ROOT='$WORK/layout/etc-link'" \
		--stdout-contains "CANONICAL_ETC_ROOT='$etc_real'" \
		--stdout-contains "OPENSIM_VAR_ROOT='$WORK/layout/var-link'" \
		--stdout-contains "CANONICAL_VAR_ROOT='$var_real'" \
		--stdout-contains "OPENSIM_LOGS_ROOT='$WORK/layout/logs-link'" \
		--stdout-contains "CANONICAL_LOGS_ROOT='$logs_real'" \
		--stdout-not-contains 'export '
}

function test_layout_rejects_unsupported_format() {
	assert_exec "'$OPENSIM' --layout --format=json" --exit 1 --stderr-contains '--layout requires --format=env'
}

function test_opensim_status_works() {
	assert_exec "'$OPENSIM' status" --stdout-contains '0 up - 0 avatars - cpu'
}

function test_console_connects_to_a_running_instance() {
	local port log
	port=$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); echo substr(strrchr(stream_socket_get_name($socket, false), ":"), 1); fclose($socket);')
	log=$WORK/console-server.log
	cat >"$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini" <<INI
[Network]
http_listener_port = 9000
console_port = $port
ConsoleUser = admin
ConsolePass = secret
INI
	php -S "127.0.0.1:$port" "$(dirname "$OPENSIM")/../tests/fixtures/rest-console.php" >"$log" 2>&1 &
	CONSOLE_PID=$!
	for _ in {1..50}; do
		if php -r '$socket = @fsockopen("127.0.0.1", (int) $argv[1], $errno, $error, 0.1); if ($socket) fclose($socket); exit($socket ? 0 : 1);' "$port"; then break; fi
		sleep 0.1
	done
	assert_exec "'$OPENSIM' console tender_tern.welcome </dev/null" --stderr-contains 'Connection to tender_tern.welcome'
	kill "$CONSOLE_PID" 2>/dev/null || true
	CONSOLE_PID=
}

function test_next_port_skips_ports_in_configuration() {
	cat >"$WORK/etc/opensim/opensim.d/port-check.ini" <<'INI'
[Network]
http_listener_port = 58130
INI
	assert_exec "'$OPENSIM' next port 58130 1" --stdout '58131'
}

function test_next_location_uses_grid_center() {
	make_test_grid
	assert_exec "'$OPENSIM' next tender_tern location" --stdout '8002,8002'
}

function test_web_reports_missing_grid() {
	assert_exec "'$OPENSIM' web" --exit 2 --stderr-contains 'no local grid'
}

function test_web_shows_local_grid_services() {
	make_test_grid
	assert_exec "'$OPENSIM' web" --stdout-contains 'Grid:      tender_tern'
}

function test_web_prints_caddy_snippet() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern snippet caddy" --stdout-contains 'php_fastcgi'
}

function test_web_snippet_under_a_prefix_takes_the_helpers_under_it_alone() {
	make_test_grid
	printf '[Helpers]\nHelpersURL = "https://grid.example.test/opensim/economy"\n' >"$WORK/etc/opensim/grids/tender_tern/Helpers.ini"
	assert_exec "'$OPENSIM' web tender_tern snippet caddy --prefix /opensim" --stdout-contains '@opensim_helpers path /opensim/economy /opensim/economy/*'
}

function test_web_snippet_routes_the_addresses_the_grid_names_on_its_site_wherever_they_are() {
	make_test_grid
	printf '[Const]\nWebURL = "https://grid.example.test"\n' >>"$WORK/etc/opensim/grids/tender_tern/Robust.ini"
	printf '[Messaging]\nOfflineMessageModule = OfflineMessageModule\nOfflineMessageURL = "https://grid.example.test/helper/offline.php"\n' >"$WORK/etc/opensim/grids/tender_tern/OpenSim.ini"
	assert_exec "'$OPENSIM' web tender_tern snippet caddy" --stdout-contains '/helper/offline.php /helper/offline.php/*'
}

function test_web_paths_outside_a_prefix_are_the_addresses_of_the_helpers_elsewhere() {
	make_test_grid
	printf '[Const]\nWebURL = "https://grid.example.test"\n' >>"$WORK/etc/opensim/grids/tender_tern/Robust.ini"
	printf '[Helpers]\nHelpersURL = "https://grid.example.test/opensim/economy"\n' >"$WORK/etc/opensim/grids/tender_tern/Helpers.ini"
	printf '[Messaging]\nOfflineMessageModule = OfflineMessageModule\nOfflineMessageURL = "https://grid.example.test/helper/offline.php"\n' >"$WORK/etc/opensim/grids/tender_tern/OpenSim.ini"
	assert_exec "'$OPENSIM' web tender_tern paths --outside /opensim" --stdout-contains '/helper/offline.php/*'
	local output
	output=$("$OPENSIM" web tender_tern paths --outside /opensim)
	assert_not_contains '/opensim/economy' "$output"
}

function test_web_api_prints_the_pool_and_the_local_listener_of_the_engine_api() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern api caddy --port 8781" --stdout-contains '[w4os-api]'
	assert_exec "'$OPENSIM' web tender_tern api caddy --port 8781" --stdout-contains 'http://127.0.0.1:8781'
	# Without --port, the one of the grid: one of its block, kept in its conf, the same each time
	local first port
	first=$("$OPENSIM" web tender_tern api nginx 2>&1)
	port=$(sed -n 's/^ApiPort = //p' "$WORK/etc/opensim/grids/tender_tern/tender_tern.conf")
	assert_matches '^80[0-9][0-9]$' "$port"
	assert_contains "listen 127.0.0.1:$port;" "$first"
	assert_contains "api_url http://127.0.0.1:$port/api" "$first"
	assert_exec "'$OPENSIM' web tender_tern api nginx" --stdout-contains "listen 127.0.0.1:$port;"
	assert_exec "'$OPENSIM' web tender_tern api lighttpd" --exit 2 --stderr-contains 'unknown web server'
}

function test_web_api_install_writes_the_pool_and_the_listener_beside_the_sites_never_the_caddyfile() {
	make_test_grid
	mkdir -p "$WORK/caddy/sites" "$WORK/php/8.4/fpm/pool.d" "$WORK/stubs"
	printf 'import sites/*\n' >"$WORK/caddy/Caddyfile"
	printf '#!/usr/bin/env bash\n[ -z "${CADDY_REFUSES:-}" ] || { echo refused; exit 1; }\n' >"$WORK/stubs/caddy"
	printf '#!/usr/bin/env bash\necho "$*" >>"%s/reloads"\n' "$WORK" >"$WORK/stubs/systemctl"
	# The API answers once the pool is there, a key asked
	printf '#!/usr/bin/env bash\n[ -z "${API_DOWN:-}" ] && printf 401 || printf 502\n' >"$WORK/stubs/curl"
	chmod +x "$WORK/stubs/caddy" "$WORK/stubs/systemctl" "$WORK/stubs/curl"
	local caddyfile
	caddyfile=$(cat "$WORK/caddy/Caddyfile")
	assert_exec "env PATH='$WORK/stubs:$PATH' OPENSIM_CADDY_ETC='$WORK/caddy' OPENSIM_PHP_ETC='$WORK/php' OPENSIM_SYSTEMD=yes '$OPENSIM' web tender_tern api caddy --port 8781 --install" \
		--stdout-contains 'Engine API: http://127.0.0.1:8781/api'
	# The pool and the listener, without the instructions to copy them
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-api.conf" '[w4os-api]'
	assert_not_contains 'Put it in' "$(cat "$WORK/php/8.4/fpm/pool.d/w4os-api.conf")"
	# The helpers in a pool of their own, as the web user, beside the one of the API
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-helpers.conf" '[w4os-helpers]'
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-helpers.conf" 'listen = /run/php/w4os-helpers.sock'
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-helpers.conf" 'listen.group = caddy'
	assert_file_contains "$WORK/caddy/sites/tender_tern-api.w4os.caddyfile" 'http://127.0.0.1:8781 {'
	assert_not_contains 'api-key create' "$(cat "$WORK/caddy/sites/tender_tern-api.w4os.caddyfile")"
	assert_equals "$caddyfile" "$(cat "$WORK/caddy/Caddyfile")"
	# The pools written anew: PHP-FPM restarted, its sockets made again with their group
	assert_contains 'restart php8.4-fpm' "$(cat "$WORK/reloads")"
	assert_contains 'reload caddy' "$(cat "$WORK/reloads")"
	# An API that does not answer once installed (no pool, 502): said
	assert_exec "env API_DOWN=1 PATH='$WORK/stubs:$PATH' OPENSIM_CADDY_ETC='$WORK/caddy' OPENSIM_PHP_ETC='$WORK/php' OPENSIM_SYSTEMD=yes '$OPENSIM' web tender_tern api caddy --port 8781 --install" \
		--exit 1 --stderr-contains 'does not answer'
	# api alone is for Caddy
	assert_exec "'$OPENSIM' web tender_tern api --port 8781" --stdout-contains 'http://127.0.0.1:8781 {'
	# What Caddy refuses is taken back
	rm "$WORK/caddy/sites/tender_tern-api.w4os.caddyfile"
	assert_exec "env CADDY_REFUSES=1 PATH='$WORK/stubs:$PATH' OPENSIM_CADDY_ETC='$WORK/caddy' OPENSIM_PHP_ETC='$WORK/php' '$OPENSIM' web tender_tern api caddy --port 8781 --install" \
		--exit 1 --stderr-contains 'refused'
	assert_file_not_exists "$WORK/caddy/sites/tender_tern-api.w4os.caddyfile"
}

function test_web_api_install_gives_the_sockets_to_the_group_apache_runs_as() {
	make_test_grid
	mkdir -p "$WORK/apache/conf-available" "$WORK/php/8.4/fpm/pool.d" "$WORK/stubs"
	printf 'export APACHE_RUN_USER=magic\nexport APACHE_RUN_GROUP=magic\n' >"$WORK/apache/envvars"
	for stub in a2enmod a2enconf a2disconf apache2ctl systemctl; do printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/stubs/$stub"; done
	printf '#!/usr/bin/env bash\nprintf 401\n' >"$WORK/stubs/curl"
	chmod +x "$WORK"/stubs/*
	assert_exec "env PATH='$WORK/stubs:$PATH' OPENSIM_APACHE_ETC='$WORK/apache' OPENSIM_PHP_ETC='$WORK/php' OPENSIM_SYSTEMD=yes '$OPENSIM' web tender_tern api apache --port 8781 --install" \
		--stdout-contains 'Engine API: http://127.0.0.1:8781/api'
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-api.conf" 'listen.group = magic'
	assert_file_contains "$WORK/php/8.4/fpm/pool.d/w4os-helpers.conf" 'listen.group = magic'
}

function test_web_set_writes_the_one_key_of_a_page_and_says_robust_must_restart() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern set search https://site.example.org/search" --stdout-contains 'restart Robust'
	assert_file_contains "$WORK/etc/opensim/grids/tender_tern/Robust.ini" 'search = "https://site.example.org/search"'
}

function test_web_set_writes_the_base_of_the_helpers_in_helpers_ini() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern set helpers https://site.example.org/helperz" --stdout-contains 'HelpersURL'
	assert_file_contains "$WORK/etc/opensim/grids/tender_tern/Helpers.ini" 'HelpersURL = "https://site.example.org/helperz"'
}

function test_web_set_refuses_what_is_not_a_page() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern set menu https://site.example.org/menu" --exit 2 --stderr-contains 'not a page'
	assert_exec "'$OPENSIM' web tender_tern set search" --exit 2 --stderr-contains 'usage'
}

function test_web_show_says_who_serves_each_page() {
	make_test_grid
	"$OPENSIM" web tender_tern set helpers https://site.example.org/helpers >/dev/null
	"$OPENSIM" web tender_tern set search https://site.example.org/search >/dev/null
	local out
	out=$("$OPENSIM" web tender_tern show)
	assert_contains 'site (config)' "$out"
	# A page the grid does not set has no address, not one guessed under the helpers
	assert_same 1 "$(grep -cE '^  guide +\(none\)' <<<"$out")"
	assert_not_contains 'https://site.example.org/helpers/guide' "$out"
}

function test_ban_reports_missing_grid() {
	assert_exec "'$OPENSIM' ban Resident" --exit 2 --stderr-contains 'no local grid'
}

function test_ban_requires_account_database() {
	make_test_grid
	assert_exec "'$OPENSIM' ban tender_tern Resident" --exit 1 --stderr-contains 'no account database'
}

function test_save_requires_archive_kind() {
	assert_exec "'$OPENSIM' save" --exit 2 --stderr-contains 'usage: opensim save iar|oar'
}

function test_save_iar_reports_missing_required_arguments() {
	assert_exec "'$OPENSIM' save iar" --exit 2 --stderr-contains 'missing argument'
}

function test_backup_reports_missing_grid() {
	assert_exec "'$OPENSIM' backup" --exit 1 --stderr-contains 'no grid here'
}

function test_backup_writes_grid_archive() {
	local archive
	make_test_grid
	assert_exec "'$OPENSIM' backup tender_tern --output '$WORK/backups'" --stdout-contains "$WORK/backups/tender_tern-"
	archive=$(find "$WORK/backups" -maxdepth 1 -name 'tender_tern-*.tar.gz' -print -quit)
	assert_file_exists "$archive"
}

function test_rest_sends_a_command_to_an_instance_with_the_credentials_of_its_config() {
	local port log
	port=$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); echo substr(strrchr(stream_socket_get_name($socket, false), ":"), 1); fclose($socket);')
	log=$WORK/console-server.log
	cat >"$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini" <<INI
[Network]
http_listener_port = 9000
console_port = $port
ConsoleUser = admin
ConsolePass = secret
INI
	php -S "127.0.0.1:$port" "$(dirname "$OPENSIM")/../tests/fixtures/rest-console.php" >"$log" 2>&1 &
	CONSOLE_PID=$!
	for _ in {1..50}; do
		if php -r '$socket = @fsockopen("127.0.0.1", (int) $argv[1], $errno, $error, 0.1); if ($socket) fclose($socket); exit($socket ? 0 : 1);' "$port"; then break; fi
		sleep 0.1
	done
	assert_exec "'$OPENSIM' rest tender_tern.welcome -- show version" --stdout-contains 'answer to show version'
	assert_exec "'$OPENSIM' rest nowhere -- show version" --exit 1 --stderr-contains 'nowhere'
	kill "$CONSOLE_PID" 2>/dev/null || true
	CONSOLE_PID=
}

function test_rest_keeps_the_password_of_the_environment_for_the_system_user() {
	assert_contains 'OPENSIM_REST_PASSWORD' "$(grep '^export PRESERVE_ENV=' "$OPENSIM")"
}

function test_api_key_creates_lists_and_revokes_a_key_by_its_label() {
	local out key
	out=$("$OPENSIM" api-key create mini-site 2>&1)
	key=$(grep -o 'osk_[A-Za-z0-9_-]*' <<<"$out" | head -1)
	assert_not_empty "$key"
	# The key is shown once: the list has its label and its date, never the key
	assert_exec "'$OPENSIM' api-key list" --stdout-contains 'mini-site'
	assert_not_contains "$key" "$("$OPENSIM" api-key list 2>&1)"
	assert_exec "'$OPENSIM' api-key revoke mini-site" --stdout-contains 'revoked'
	assert_exec "'$OPENSIM' api-key list" --stdout-contains 'revoked'
	assert_exec "'$OPENSIM' api-key revoke nothing-here" --exit 1 --stderr-contains 'no key'
	assert_exec "'$OPENSIM' api-key create" --exit 2 --stderr-contains 'usage'
}

function test_rest_delegates_to_rest_cli() {
	assert_exec "'$OPENSIM' rest --help" --stdout-contains 'Run the opensim-rest-php console client'
}

function test_enable_links_simulator_configuration() {
	make_test_grid
	assert_exec "'$OPENSIM' enable tender_tern.welcome" --stdout-contains 'simulator tender_tern.welcome enabled'
	assert_file_exists "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
}

function test_disable_unlinks_simulator_configuration() {
	make_test_grid
	ln -s "$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
	assert_exec "'$OPENSIM' disable tender_tern.welcome" --stdout-contains 'simulator tender_tern.welcome disabled'
	assert_file_not_exists "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
}

function test_enable_applies_grid_feature_preset() {
	make_test_grid
	mkdir -p "$WORK/etc/opensim/presets/profiles"
	cat >"$WORK/etc/opensim/presets/profiles/option.conf" <<'INI'
[Option]
Label = Profiles
INI
	cat >"$WORK/etc/opensim/presets/profiles/OpenSim.ini" <<'INI'
[Startup]
TestProfileSetting = enabled
INI
	assert_exec "'$OPENSIM' enable tender_tern profiles" --stdout-contains 'profiles enabled for tender_tern'
	assert_file_contains "$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" 'TestProfileSetting = enabled'
}

function test_api_asks_the_engine_and_gives_its_answer() {
	local api="$WORK/w4os-api"
	printf '#!/bin/sh\necho "engine $*"\n' >"$api"
	chmod +x "$api"
	assert_exec "OPENSIM_API='$api' '$OPENSIM' api GET /grids --grid=demo" \
		--stdout-contains "engine GET /grids --grid=demo"
}

function test_verbose_and_quiet_reach_the_engine() {
	local api="$WORK/w4os-api"
	printf '#!/bin/sh\necho "DEBUG=$DEBUG QUIET=$QUIET"\n' >"$api"
	chmod +x "$api"
	assert_contains "DEBUG=yes" "$(OPENSIM_API="$api" "$OPENSIM" -v api GET /layout 2>&1)"
	assert_contains "QUIET=yes" "$(OPENSIM_API="$api" "$OPENSIM" -q api GET /layout 2>&1)"
}

function test_the_options_after_the_command_are_its_own() {
	local api="$WORK/w4os-api"
	printf '#!/bin/sh\necho "engine $*"\n' >"$api"
	chmod +x "$api"
	# -h and -v of the archives of OpenSimulator (the home URL, verbose) are not the help nor the verbose of the command line
	assert_contains "engine POST /archives -h http://home.example.org -v" \
		"$(OPENSIM_API="$api" "$OPENSIM" api POST /archives -h http://home.example.org -v 2>&1)"
	assert_not_contains "Save an inventory" "$("$OPENSIM" save iar -h http://home.example.org 2>&1)"
	assert_contains "Save an inventory" "$("$OPENSIM" save -h 2>&1)"
	assert_contains "Save an inventory" "$("$OPENSIM" save iar --help 2>&1)"
}

function test_version_tells_the_command_line_and_with_v_everything() {
	local api="$WORK/w4os-api"
	printf '#!/bin/sh\n[ "$1 $2" = "--version -v" ] && printf "%%-24s %%s\\n" w4os-engine 3.0.0-test PHP 8.4\n' >"$api"
	chmod +x "$api"
	assert_matches '^w4os-cli [^ ]+' "$(OPENSIM_API="$api" "$OPENSIM" --version 2>/dev/null)"
	local all
	all=$(OPENSIM_API="$api" "$OPENSIM" --version -v 2>/dev/null)
	assert_contains "w4os-cli" "$all"
	assert_matches "w4os-engine +3.0.0-test" "$all"
}

function test_oar_packs_reads_checks_and_unpacks_an_archive_of_regions() {
	local src="$WORK/plaza-src"
	mkdir -p "$src/assets" "$src/landdata" "$src/objects" "$src/settings" "$src/terrains"
	printf '<?xml version="1.0" encoding="utf-8"?><archive major_version="0" minor_version="8"><creation_info><datetime>1700000000</datetime></creation_info><assets_included>False</assets_included><region_info><is_megaregion>False</is_megaregion><size_in_meters>256,256</size_in_meters></region_info></archive>' >"$src/archive.xml"
	printf 'terrain' >"$src/terrains/Plaza.r32"
	printf '<RegionSettings/>' >"$src/settings/Plaza.xml"

	assert_contains "$WORK/plaza.oar" "$(cd "$WORK" && "$OPENSIM" oar pack "$src" 2>&1)"
	assert_file_exists "$WORK/plaza.oar"
	local info
	info=$("$OPENSIM" oar info "$WORK/plaza.oar" 2>&1)
	assert_contains "version" "$info"
	assert_contains "256x256" "$info"
	assert_exec "'$OPENSIM' oar check '$WORK/plaza.oar'" --exit 0 --stdout-contains "ok"
	assert_contains "$WORK/out" "$("$OPENSIM" oar unpack "$WORK/plaza.oar" "$WORK/out" 2>&1)"
	assert_file_exists "$WORK/out/terrains/Plaza.r32"
	assert_exec "'$OPENSIM' oar" --exit 2 --stderr-contains "usage: opensim oar"
}

function test_completion_knows_every_command_and_the_grids() {
	mkdir -p "$WORK/etc/opensim/grids/tender_tern/sims" "$WORK/etc/opensim/opensim.d"
	touch "$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini"
	# shellcheck disable=SC1091
	source "$(dirname "$OPENSIM")/../share/bash-completion/opensim"
	local commands
	commands=$(sed -n 's/^COMMANDOPTS=//p' "$OPENSIM" | tr ',' '\n' | sort)
	COMP_WORDS=(opensim '') COMP_CWORD=1 OPENSIM_ETC_DIRS="$WORK/etc/opensim"
	_opensim
	assert_equals "$commands" "$(printf '%s\n' "${COMPREPLY[@]}" | grep -v -- '^--' | sort)"
	COMP_WORDS=(opensim import '') COMP_CWORD=2
	_opensim
	assert_contains "tender_tern" "${COMPREPLY[*]}"
	assert_contains "--accounts" "${COMPREPLY[*]}"
	COMP_WORDS=(opensim enable '') COMP_CWORD=2
	_opensim
	assert_contains "tender_tern.welcome" "${COMPREPLY[*]}"
}

function test_module_enables_and_disables_a_module_for_the_install_the_others_kept() {
	local conf="$WORK/w4os.conf" output
	printf '[Defaults]\n    EnabledModules = opensimsearch\n' >"$conf"
	output=$(OPENSIM_CONF="$conf" "$(dirname "$OPENSIM")/../libexec/module" enable gloebit 2>&1)
	assert_contains "Module gloebit enabled for the install" "$output"
	assert_contains 'EnabledModules = "opensimsearch gloebit"' "$(cat "$conf")"
	output=$(OPENSIM_CONF="$conf" "$(dirname "$OPENSIM")/../libexec/module" disable gloebit 2>&1)
	assert_contains "Module gloebit disabled" "$output"
	assert_contains 'EnabledModules = "opensimsearch"' "$(cat "$conf")"
	OPENSIM_CONF="$conf" "$(dirname "$OPENSIM")/../libexec/module" start gloebit >/dev/null 2>&1
	assert_equals 2 "$?"
}
