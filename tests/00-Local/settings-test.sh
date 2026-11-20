#!/usr/bin/env bash
# opensim settings and opensim posts, with a stand-in for the engine (tests/fixtures/opensim-api): what is asked of the engine, and what
# its answer shows. What the settings and the posts are is the engine's business, tested there.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

CONTRACT='{"paths":{"/grids/{grid}/settings/models":{"get":{"x-form":{"fields":[{"name":"match","type":"select"}]}}},"/grids/{grid}/settings/economy":{"get":{"x-form":{"fields":[{"name":"economyUrl","type":"url"},{"name":"economyModule","type":"select","readOnly":true},{"name":"moneyScriptKey","type":"secret"}]}},"patch":{}},"/grids/{grid}/settings/search":{"get":{"x-form":{"fields":[{"name":"searchDatabase","type":"connection-string"},{"name":"eventsUrl","type":"url"}]}}},"/grids/{grid}/posts":{"get":{}}}}'
ECONOMY='{"data":{"type":"settings","id":"economy","attributes":{"economyUrl":"https://play.example.org/helpers/","economyModule":"Gloebit","moneyScriptKey":"********"}}}'
SEARCH='{"data":{"type":"settings","id":"search","attributes":{"searchDatabase":{"host":"db.example.org","port":3307,"database":"ossearch","user":"opensim","password":"********","options":{}},"eventsUrl":null}}}'
REFUSED='{"type":"about:blank","title":"Invalid request","status":400,"detail":"'"'"'economyModule'"'"' is set by the options of the grid, not here","code":"invalid-request"}'
POSTS='{"data":[{"type":"posts","id":"aaaaaaaa-0000-4000-8000-000000000001","attributes":{"author":"11111111-1111-4111-8111-111111111111","name":"Ada Love","content":"Hello world","created":1700000000,"source":""}}],"meta":{"total":1}}'
NOT_THERE='{"type":"about:blank","title":"Not found","status":404,"detail":"There is no post called '"'"'nothing'"'"'","code":"not-found","resource":"posts"}'

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
	export OPENSIM_API="$WORK/engine/bin/opensim-api" ENGINE_REPLIES="$WORK/replies" ENGINE_LOG="$WORK/requests" ENGINE_CALLS="$WORK/calls"
}

function tear_down() {
	rm -rf "$WORK"
}

# The replies of the engine, in the order it is asked
function engine_says() {
	local n=0
	rm -f "$ENGINE_REPLIES"/*.json "$ENGINE_REPLIES/.count" "$ENGINE_LOG" "$ENGINE_CALLS"
	for reply in "$@"; do
		n=$((n + 1))
		printf '%s' "$reply" >"$ENGINE_REPLIES/$n.json"
	done
}

function test_shows_a_page_of_settings_a_secret_masked_what_the_options_set_marked() {
	engine_says "$CONTRACT" "$ECONOMY"

	out=$("$OPENSIM" settings demo economy 2>&1)

	assert_same $'GET /openapi.json\nGET /grids/demo/settings/economy' "$(cat "$ENGINE_CALLS")"
	assert_contains "economyUrl = https://play.example.org/helpers/" "$out"
	assert_contains "economyModule = Gloebit (set by the options of the grid)" "$out"
	assert_contains "moneyScriptKey = ********" "$out"
}

function test_shows_a_database_by_its_parts_and_what_is_not_set() {
	engine_says "$CONTRACT" "$SEARCH"

	out=$("$OPENSIM" settings demo search 2>&1)

	assert_contains "searchDatabase.host = db.example.org" "$out"
	assert_contains "searchDatabase.port = 3307" "$out"
	assert_contains "searchDatabase.password = ********" "$out"
	assert_contains "eventsUrl = (not set)" "$out"
}

function test_lists_the_pages_of_settings_without_one() {
	engine_says "$CONTRACT"

	out=$("$OPENSIM" settings demo 2>&1)

	assert_contains "economy" "$out"
	assert_contains "search" "$out"
	assert_contains "models" "$out"
	assert_not_contains "posts" "$out"
}

function test_changes_settings_a_part_of_a_database_alone_and_says_why_the_engine_refuses() {
	engine_says "$SEARCH"

	out=$("$OPENSIM" settings demo search --set searchDatabase.host=db2.example.org --set eventsUrl=https://events.example.org 2>&1)

	assert_same "PATCH /grids/demo/settings/search --data=-" "$(cat "$ENGINE_CALLS")"
	assert_same '{"data":{"type":"settings","id":"search","attributes":{"searchDatabase":{"host":"db2.example.org"},"eventsUrl":"https://events.example.org"}}}' "$(jq -c . "$ENGINE_LOG")"
	assert_contains "searchDatabase.host = db.example.org" "$out"

	engine_says "$REFUSED"
	out=$("$OPENSIM" settings demo economy --set economyModule=Gloebit 2>&1) && fail "a refusal ends in an error"
	assert_contains "is set by the options of the grid" "$out"
}

function test_a_change_says_the_restart_it_needs() {
	engine_says '{"data":{"type":"settings","id":"economy","attributes":{"currencySymbol":"ZZ$"}},"meta":{"reminders":[{"code":"restart-grid","params":{"restart":"opensim restart demo"},"detail":"Grid restart is required: opensim restart demo."}]}}'

	out=$("$OPENSIM" settings demo economy --set currencySymbol=ZZ\$ 2>&1)

	assert_contains "currencySymbol = ZZ$" "$out"
	assert_contains "Grid restart is required: opensim restart demo." "$out"
}

function test_set_needs_a_name_and_a_value() {
	out=$("$OPENSIM" settings demo economy --set economyUrl 2>&1) && fail "a setting without a value is an error"
	assert_contains "NAME=VALUE" "$out"
}

function test_lists_the_posts_of_a_grid_by_author_and_words() {
	engine_says "$POSTS"

	out=$("$OPENSIM" posts demo --author 11111111-1111-4111-8111-111111111111 --search hello 2>&1)

	assert_same "GET /grids/demo/posts filter[author]=11111111-1111-4111-8111-111111111111 search=hello" "$(cat "$ENGINE_CALLS")"
	assert_contains "2023-11-14 22:13  Ada Love: Hello world" "$out"
	assert_contains "aaaaaaaa-0000-4000-8000-000000000001" "$out"
	assert_contains "1 post" "$out"
}

function test_deletes_a_post_and_says_when_there_is_none() {
	engine_says ""

	out=$("$OPENSIM" posts delete demo aaaaaaaa-0000-4000-8000-000000000001 2>&1)

	assert_same "DELETE /grids/demo/posts/aaaaaaaa-0000-4000-8000-000000000001" "$(cat "$ENGINE_CALLS")"
	assert_contains "post aaaaaaaa-0000-4000-8000-000000000001 deleted" "$out"

	engine_says "$NOT_THERE"
	out=$("$OPENSIM" posts delete demo nothing 2>&1) && fail "a post that is not there is an error"
	assert_contains "There is no post called 'nothing'" "$out"
}
