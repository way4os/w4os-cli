#!/usr/bin/env bash
# opensim address, with a stand-in for the engine (tests/fixtures/w4os-api): what is asked of the engine, and what its answer shows.
# What changes in the files of the grid is the engine's business, tested there.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

PLANNED='{"data":{"type":"address","id":"demo","attributes":{"mode":"plan","from":{"host":"old.example.org","port":8002,"site":"http://10.0.0.5:8830"},"to":{"host":"dev.example.org","port":8002,"site":"http://site.example.org:8830"},"changes":[{"file":"/etc/opensim/grids/demo/Robust.HG.ini","line":3,"before":"    BaseHostname = \"old.example.org\"","after":"BaseHostname = \"dev.example.org\""}],"rows":[{"database":"demo@localhost/demo","table":"UserAccounts","column":"ServiceURLs","before":"http://old.example.org:8002","after":"http://dev.example.org:8002","rows":11}],"applied":false}}}'
APPLIED='{"data":{"type":"address","id":"demo","attributes":{"mode":"apply","from":{"host":"old.example.org","port":8002,"site":""},"to":{"host":"dev.example.org","port":8012,"site":""},"changes":[],"applied":true}},"meta":{"reminders":[{"code":"restart-grid","detail":"Grid restart is required: opensim restart demo."}]}}'
REFUSED='{"type":"about:blank","title":"Invalid request","status":400,"detail":"the grid has this address already: give another host, port or site","code":"invalid-request"}'

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK" OPENSIM_SYSTEM_USER=
	unset OPENSIM_CONF OPENSIM_RC
	mkdir -p "$WORK/etc"
	cat >"$WORK/.w4os.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc
		SystemUser =
	INI
	local fixtures
	fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures"
	mkdir -p "$WORK/engine/bin" "$WORK/engine/lib" "$WORK/replies"
	ln -s "$fixtures/w4os-api" "$WORK/engine/bin/w4os-api"
	cp "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../vendor/way4os/w4os-engine/lib" && pwd)/rc-helpers" "$WORK/engine/lib/rc-helpers"
	export OPENSIM_API="$WORK/engine/bin/w4os-api" ENGINE_REPLIES="$WORK/replies" ENGINE_LOG="$WORK/requests" ENGINE_CALLS="$WORK/calls"
}

function tear_down() {
	rm -rf "$WORK"
}

function engine_says() {
	local n=0
	rm -f "$ENGINE_REPLIES"/*.json "$ENGINE_REPLIES/.count" "$ENGINE_LOG" "$ENGINE_CALLS"
	for reply in "$@"; do
		n=$((n + 1))
		printf '%s' "$reply" >"$ENGINE_REPLIES/$n.json"
	done
}

function test_plans_the_change_by_default_and_shows_each_line() {
	engine_says "$PLANNED"

	out=$("$OPENSIM" address demo --host dev.example.org --site http://site.example.org:8830 2>&1)

	assert_same "POST /grids/demo/address --data=-" "$(cat "$ENGINE_CALLS")"
	assert_same '{"data":{"type":"address","attributes":{"mode":"plan","host":"dev.example.org","site":"http://site.example.org:8830"}}}' "$(cat "$ENGINE_LOG")"
	assert_contains "old.example.org:8002 -> dev.example.org:8002" "$out"
	assert_contains "site: http://10.0.0.5:8830 -> http://site.example.org:8830" "$out"
	assert_contains "/etc/opensim/grids/demo/Robust.HG.ini:3" "$out"
	assert_contains '  + BaseHostname = "dev.example.org"' "$out"
	assert_contains "In the databases:" "$out"
	assert_contains "  UserAccounts.ServiceURLs (demo@localhost/demo): 11 rows, http://old.example.org:8002 -> http://dev.example.org:8002" "$out"
	assert_contains "Nothing written: opensim address demo --host dev.example.org --site http://site.example.org:8830 --apply" "$out"
}

function test_applies_with_apply_a_port_as_a_number_and_says_what_to_restart() {
	engine_says "$APPLIED"

	out=$("$OPENSIM" address demo --port 8012 --apply 2>&1)

	assert_same '{"data":{"type":"address","attributes":{"mode":"apply","port":8012}}}' "$(cat "$ENGINE_LOG")"
	assert_contains "Nothing to change." "$out"
	assert_contains "- Grid restart is required: opensim restart demo." "$out"
	assert_not_contains "Nothing written" "$out"
}

function test_changes_the_address_of_the_website_alone() {
	engine_says '{"data":{"type":"address","id":"demo","attributes":{"mode":"apply","from":{"website":"https://w4os.org/"},"to":{"website":"https://www.w4os.org/opensim/"},"changes":[{"file":"/etc/opensim/grids/demo/demo.conf","line":0,"before":"SiteAddress = https://w4os.org/","after":"SiteAddress = https://www.w4os.org/opensim/"}],"rows":[],"applied":true}}}'

	out=$("$OPENSIM" address demo --website https://www.w4os.org/opensim/ --apply 2>&1)

	assert_same '{"data":{"type":"address","attributes":{"mode":"apply","website":"https://www.w4os.org/opensim/"}}}' "$(cat "$ENGINE_LOG")"
	assert_contains "website: https://w4os.org/ -> https://www.w4os.org/opensim/" "$out"
	assert_not_contains "site: " "$(grep -v '^website' <<<"$out")"
	assert_not_contains "restart" "$out"
}

function test_says_what_the_engine_refuses() {
	engine_says "$REFUSED"

	out=$("$OPENSIM" address demo --host old.example.org 2>&1)
	status=$?

	assert_same 1 "$status"
	assert_contains "the grid has this address already" "$out"
}

function test_needs_a_grid_and_something_that_changes() {
	engine_says "$PLANNED"

	assert_contains "usage: opensim address" "$("$OPENSIM" address 2>&1)"
	assert_contains "give the --host, the --port, the --site or the --website" "$("$OPENSIM" address demo 2>&1)"
	assert_contains "--port takes a number" "$("$OPENSIM" address demo --port eighty 2>&1)"
	assert_file_not_exists "$ENGINE_CALLS"
}
