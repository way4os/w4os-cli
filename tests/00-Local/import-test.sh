#!/usr/bin/env bash
# opensim import, with a stand-in for the engine (tests/fixtures/opensim-api): what is asked of the engine, and what its answer shows.
# What an import does is the engine's business, tested there.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

PLAN='{"data":{"type":"imports","id":"demo.redoutable","attributes":{"kind":"simulator","mode":"plan","applied":false,"source":"/opt/opensim/etc/opensim.d/redoutable.ini","grid":"demo","simulator":"redoutable","slug":"demo.redoutable","core":"/core","config":"/etc/opensim/grids/demo/sims/demo.redoutable.ini","database":{"host":"localhost","name":"osredoutable","user":"opensim","kept":true},"ports":{"http":9250,"console":null},"regions":[{"file":"/opt/r/Redoutable.ini","to":"/etc/opensim/grids/demo/sims/demo.redoutable/regions/Redoutable.ini","name":"Redoutable","uuid":"1111","location":"1000,1000"}],"settings":[{"section":"XEngine","key":"MinThreads","value":"10","unknown":false}],"report":"/etc/opensim/grids/demo/sims/demo.redoutable.import-report.txt","writes":["/etc/opensim/grids/demo/sims/demo.redoutable.ini"],"reminders":["Stop the old one.","Then: opensim enable demo.redoutable, opensim start demo.redoutable."]}}}'
REFUSED='{"type":"about:blank","title":"Bad request","status":400,"detail":"the grid already has the simulator demo.redoutable","code":"invalid-request"}'

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK" OPENSIM_SYSTEM_USER=
	unset OPENSIM_CONF OPENSIM_RC
	mkdir -p "$WORK/etc"
	cat >"$WORK/.opensim.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc
		SystemUser =
	INI
	local fixtures
	fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures"
	mkdir -p "$WORK/engine/bin" "$WORK/engine/lib" "$WORK/replies"
	ln -s "$fixtures/opensim-api" "$WORK/engine/bin/opensim-api"
	cp "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../vendor/magicoli/opensim-engine/lib" && pwd)/rc-helpers" "$WORK/engine/lib/rc-helpers"
	export OPENSIM_API="$WORK/engine/bin/opensim-api" ENGINE_REPLIES="$WORK/replies" ENGINE_LOG="$WORK/requests"
	printf '[Network]\nhttp_listener_port = 9250\n' >"$WORK/redoutable.ini"
}

function tear_down() {
	rm -rf "$WORK"
}

function engine_says() {
	printf '%s' "$1" >"$ENGINE_REPLIES/1.json"
	rm -f "$ENGINE_REPLIES/.count" "$ENGINE_LOG"
}

function test_plans_the_import_and_says_nothing_was_written() {
	engine_says "$PLAN"

	local out
	out=$("$OPENSIM" import --simulator "$WORK/redoutable.ini" demo 2>&1)

	assert_same '{"kind":"simulator","file":"'"$(realpath "$WORK/redoutable.ini")"'","grid":"demo","mode":"plan"}' "$(jq -c '.data.attributes' "$ENGINE_LOG")"
	assert_contains "Simulator redoutable (demo.redoutable) of the grid demo" "$out"
	assert_contains "Database: osredoutable @ localhost (user opensim), kept as it is" "$out"
	assert_contains "  Redoutable (1111, 1000,1000): /opt/r/Redoutable.ini -> /etc/opensim/grids/demo/sims/demo.redoutable/regions/Redoutable.ini" "$out"
	assert_contains "Would write:" "$out"
	assert_contains "Nothing was written: add --apply to write it." "$out"
	assert_contains "- Then: opensim enable demo.redoutable, opensim start demo.redoutable." "$out"
}

function test_applies_with_the_name_and_the_core_given() {
	engine_says "$(jq -c '.data.attributes.applied = true | .data.attributes.mode = "apply"' <<<"$PLAN")"

	local out
	out=$("$OPENSIM" import demo --simulator "$WORK/redoutable.ini" --name Fort --core /cores/0.9.3.0 --apply 2>&1)

	assert_same '{"mode":"apply","name":"Fort","core":"/cores/0.9.3.0"}' "$(jq -c '.data.attributes | {mode,name,core}' "$ENGINE_LOG")"
	assert_contains "Written:" "$out"
	assert_contains "Report:   /etc/opensim/grids/demo/sims/demo.redoutable.import-report.txt" "$out"
}

function test_says_why_the_engine_refuses() {
	engine_says "$REFUSED"

	local out status=0
	out=$("$OPENSIM" import --simulator "$WORK/redoutable.ini" demo 2>&1) || status=$?

	assert_not_same "0" "$status"
	assert_contains "the grid already has the simulator demo.redoutable" "$out"
}

function test_needs_a_file_and_a_grid() {
	local out status=0
	out=$("$OPENSIM" import --simulator "$WORK/redoutable.ini" 2>&1) || status=$?

	assert_not_same "0" "$status"
	assert_contains "usage: opensim import --simulator FILE GRID" "$out"
}
