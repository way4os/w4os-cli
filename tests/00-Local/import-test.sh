#!/usr/bin/env bash
# opensim import, with a stand-in for the engine (tests/fixtures/opensim-api): what is asked of the engine, and what its answer shows.
# What an import does is the engine's business, tested there.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

PLAN='{"data":{"type":"imports","id":"demo.redoutable","attributes":{"kind":"simulator","mode":"plan","applied":false,"source":"/opt/opensim/etc/opensim.d/redoutable.ini","grid":"demo","simulator":"redoutable","slug":"demo.redoutable","core":"/core","config":"/etc/opensim/grids/demo/sims/demo.redoutable.ini","database":{"host":"localhost","name":"osredoutable","user":"opensim","kept":true},"ports":{"http":9250,"console":null},"regions":[{"file":"/opt/r/Redoutable.ini","to":"/etc/opensim/grids/demo/sims/demo.redoutable/regions/Redoutable.ini","name":"Redoutable","uuid":"1111","location":"1000,1000"}],"settings":[{"section":"XEngine","key":"MinThreads","value":"10","unknown":false}],"dropped":[{"section":"Launch","key":"SimName","value":"redoutable","reason":"layout"},{"section":"Network","key":"http_listener_port","value":"9250","reason":"same"},{"section":"Network","key":"ExternalHostName","value":"old.example.org","reason":"replaced"},{"section":"GridService","key":"MapTileDirectory","value":"/opt/opensim/var/redoutable/maptiles","reason":"replaced","replacement":"/var/cache/opensim/demo/demo.redoutable/maptiles"}],"backup":{"file":"/var/backups/opensim/demo/redoutable/demo-redoutable-20261117-120000-source.tar.gz","databases":["osredoutable"],"files":["/opt/opensim/etc/opensim.d/redoutable.ini"],"size":512},"scripts":{"from":["/opt/opensim/var/redoutable/ScriptEngines"],"to":"/var/lib/opensim/data/demo/demo.redoutable/ScriptEngines","size":2048,"copied":true},"report":"/etc/opensim/grids/demo/sims/demo.redoutable.import-report.txt","writes":["/etc/opensim/grids/demo/sims/demo.redoutable.ini"],"reminders":["Stop the old one.","Then: opensim enable demo.redoutable, opensim start demo.redoutable."]}}}'
REFUSED='{"type":"about:blank","title":"Bad request","status":400,"detail":"the grid already has the simulator demo.redoutable","code":"invalid-request"}'

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK" OPENSIM_SYSTEM_USER=
	# What the caller's environment says of the databases is not the test's
	unset OPENSIM_CONF OPENSIM_RC OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS OPENSIM_DB_HOST OPENSIM_DB_PORT OPENSIM_DB_NAME OPENSIM_DB_USER OPENSIM_DB_PASS
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
	assert_contains "Settings left: 4 (layout 1, replaced 2, same 1)" "$out"
	assert_contains "Backup of the source first: /var/backups/opensim/demo/redoutable/demo-redoutable-20261117-120000-source.tar.gz (databases osredoutable, 1 files)" "$out"
	assert_contains "State of the scripts: /opt/opensim/var/redoutable/ScriptEngines -> /var/lib/opensim/data/demo/demo.redoutable/ScriptEngines (2048 bytes)" "$out"
	assert_contains "  [GridService] MapTileDirectory = /opt/opensim/var/redoutable/maptiles -> /var/cache/opensim/demo/demo.redoutable/maptiles" "$out"
	assert_contains "  [Network] ExternalHostName = old.example.org: written by the new config its own way" "$out"
}

function test_plans_several_simulators_together_and_says_what_is_wrong_between_them() {
	engine_says "$(jq -c '{data: {type: "imports", id: "demo", attributes: {kind: "simulator", mode: "plan", applied: false, grid: "demo", steps: [.data.attributes, (.data.attributes | .slug = "demo.residences" | .simulator = "residences")], writes: ["/a", "/b"], problems: {"simulators.1": "the port 9250 is also the one of the simulator 1"}, reminders: []}}}' <<<"$PLAN")"
	printf '[Network]\nhttp_listener_port = 9250\n' >"$WORK/residences.ini"

	local out status=0
	out=$("$OPENSIM" import --simulator "$WORK/redoutable.ini" --simulator "$WORK/residences.ini" demo 2>&1) || status=$?

	assert_same "[\"$(realpath "$WORK/redoutable.ini")\",\"$(realpath "$WORK/residences.ini")\"]" "$(jq -c '[.data.attributes.simulators[].file]' "$ENGINE_LOG")"
	assert_contains "Simulator residences (demo.residences) of the grid demo" "$out"
	assert_contains "Problems, nothing can be written:" "$out"
	assert_contains "  simulators.1: the port 9250 is also the one of the simulator 1" "$out"
	assert_not_same "0" "$status"
}

function test_keeps_the_scripts_unless_asked_not_to() {
	engine_says "$PLAN"
	"$OPENSIM" import --simulator "$WORK/redoutable.ini" demo >/dev/null 2>&1
	assert_same "null" "$(jq -c '.data.attributes.scripts' "$ENGINE_LOG")"
	engine_says "$PLAN"
	"$OPENSIM" import --simulator "$WORK/redoutable.ini" demo --no-scripts >/dev/null 2>&1
	assert_same "false" "$(jq -c '.data.attributes.scripts' "$ENGINE_LOG")"
}

function test_several_simulators_take_no_name_nor_core() {
	local out status=0
	out=$("$OPENSIM" import --simulator "$WORK/redoutable.ini" --simulator "$WORK/redoutable.ini" demo --name Fort 2>&1) || status=$?

	assert_not_same "0" "$status"
	assert_contains "--name and --core are for one simulator" "$out"
}

function test_applies_with_the_name_and_the_core_given() {
	engine_says "$(jq -c '.data.attributes.applied = true | .data.attributes.mode = "apply"' <<<"$PLAN")"

	local out
	out=$("$OPENSIM" import demo --simulator "$WORK/redoutable.ini" --name Fort --core /cores/0.9.3.0 --apply 2>&1)

	assert_same '{"mode":"apply","name":"Fort","core":"/cores/0.9.3.0"}' "$(jq -c '.data.attributes | {mode,name,core}' "$ENGINE_LOG")"
	assert_contains "Written:" "$out"
	assert_contains "Report:   /etc/opensim/grids/demo/sims/demo.redoutable.import-report.txt" "$out"
}

SETTINGS='{"data":{"type":"imports","id":"demo","attributes":{"kind":"grid-settings","mode":"plan","applied":false,"grid":"demo","source":"/opt/opensim/etc/grids/Old/OpenSim.ini","target":"/etc/opensim/grids/demo/OpenSim.ini","settings":{"Search":{"Module":"OpenSimSearch"}},"files":{"/etc/opensim/grids/demo/OpenSim.ini":{"Const":{"WebURL":"https://web.example.org"},"Search":{"Module":"OpenSimSearch","SearchURL":"${Const|WebURL}/helpers/query.php"},"Gloebit":{"Include-Gloebit":"${Const|EtcDirectory}/Gloebit.ini"}},"/etc/opensim/grids/demo/Gloebit.ini":{"Gloebit":{"GLBEnvironment":"production","GLBSecret":"***"}}},"notes":["Economy/CurrencyServer: the money of DTL/NSL is not handled (old code, to install by hand), left out"]}}}'

function test_plans_the_settings_of_a_grid_of_another_install_the_secrets_masked() {
	engine_says "$SETTINGS"
	printf '[Search]\nModule = OpenSimSearch\n' >"$WORK/OpenSim.ini"

	local out
	out=$("$OPENSIM" import --grid-settings "$WORK/OpenSim.ini" demo 2>&1)

	assert_same '{"kind":"grid-settings","file":"'"$(realpath "$WORK/OpenSim.ini")"'","grid":"demo","mode":"plan"}' "$(jq -c '.data.attributes' "$ENGINE_LOG")"
	assert_contains "Settings of the grid demo, from /opt/opensim/etc/grids/Old/OpenSim.ini" "$out"
	assert_contains "Into /etc/opensim/grids/demo/OpenSim.ini:" "$out"
	assert_contains "  [Const] WebURL = https://web.example.org" "$out"
	assert_contains "  [Search] SearchURL = \${Const|WebURL}/helpers/query.php" "$out"
	assert_contains "Into /etc/opensim/grids/demo/Gloebit.ini:" "$out"
	assert_contains "  [Gloebit] GLBSecret = ***" "$out"
	assert_contains "- Economy/CurrencyServer: the money of DTL/NSL is not handled (old code, to install by hand), left out" "$out"
	assert_contains "Nothing was written: add --apply to write it." "$out"
}

function test_applies_the_settings_of_a_grid_and_says_what_lays_them_in_its_simulators() {
	engine_says "${SETTINGS/\"applied\":false/\"applied\":true}"
	printf '[Search]\nModule = OpenSimSearch\n' >"$WORK/OpenSim.ini"

	local out
	out=$("$OPENSIM" import --grid-settings "$WORK/OpenSim.ini" demo --apply 2>&1)

	assert_same "apply" "$(jq -r '.data.attributes.mode' "$ENGINE_LOG")"
	assert_contains "Written to /etc/opensim/grids/demo/Gloebit.ini, /etc/opensim/grids/demo/OpenSim.ini" "$out"
	assert_contains "opensim api POST /grids/demo/options/repair mode=apply" "$out"
}

function test_the_settings_of_a_grid_need_a_file_and_a_grid() {
	local out status=0
	out=$("$OPENSIM" import --grid-settings "$WORK/none.ini" demo 2>&1) || status=$?

	assert_not_same "0" "$status"
	assert_contains "cannot read" "$out"
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
	assert_contains "opensim import --simulator FILE" "$out"
}

FILES='{"data":{"type":"files","id":"demo","attributes":{"mode":"plan","applied":false,"grid":"demo","steps":[{"kind":"simulator","simulator":"North","slug":"demo.north","config":"/etc/opensim/grids/demo/sims/demo.north.ini","ports":{"http":9010,"console":null},"database":{"host":"localhost","name":"demo_north","user":"opensim"},"estate":{"name":"Ada Love Estate","owner":"Ada Love"},"region":{"name":"Big Garden","location":"1000,1000","size":512,"roles":["FallbackRegion"],"port":9011,"file":"/etc/opensim/grids/demo/sims/demo.north/regions/BigGarden.ini"}}],"writes":["/etc/opensim/grids/demo/sims/demo.north.ini","/etc/opensim/grids/demo/sims/demo.north/regions/BigGarden.ini"],"problems":{},"reminders":["opensim start demo.north"],"notes":[{"code":"plan-reserves-nothing","params":{},"detail":"A plan reserves nothing."}]}}}'

function test_applies_a_setup_file_given_alone() {
	engine_says "$FILES"
	printf 'grid:\n  nick: demo\n' >"$WORK/setup.yaml"

	local out
	out=$("$OPENSIM" import "$WORK/setup.yaml" 2>&1)

	assert_same '{"text":"grid:\n  nick: demo\n","mode":"plan"}' "$(jq -c '.data.attributes' "$ENGINE_LOG")"
	assert_contains "Simulator North (demo.north): /etc/opensim/grids/demo/sims/demo.north.ini, http 9010, database demo_north @ localhost, estate Ada Love Estate (Ada Love)" "$out"
	assert_contains "  Big Garden at 1000,1000, 512 m, port 9011, FallbackRegion: /etc/opensim/grids/demo/sims/demo.north/regions/BigGarden.ini" "$out"
	assert_contains "Nothing was written: add --apply to write it, then:" "$out"
	assert_contains "  opensim start demo.north" "$out"
	assert_contains "Note: A plan reserves nothing." "$out"
}

function test_gives_a_region_to_a_simulator() {
	engine_says "$FILES"

	"$OPENSIM" region add demo alpha --name "Alpha Two" --location 1200,1200 --size 512 --roles FallbackRegion,DefaultHGRegion --apply >/dev/null 2>&1

	assert_same '{"grid":{"nick":"demo"},"simulators":[{"name":"alpha","regions":[{"name":"Alpha Two","location":"1200,1200","size":512,"roles":["FallbackRegion","DefaultHGRegion"]}]}]}' "$(jq -c '.data.attributes.setup' "$ENGINE_LOG")"
	assert_same "apply" "$(jq -r '.data.attributes.mode' "$ENGINE_LOG")"
}

function test_gives_the_estate_its_regions_join() {
	engine_says "$FILES"

	"$OPENSIM" simulator add demo North --region "Big Garden" --owner "Ada Love" --estate "Ada Land" >/dev/null 2>&1

	assert_same '{"owner":"Ada Love","name":"Ada Land"}' "$(jq -c '.data.attributes.setup.simulators[0].estate' "$ENGINE_LOG")"
}

function test_gives_the_administrator_of_the_database_server_never_on_the_command_line() {
	engine_says "$FILES"

	OPENSIM_DB_ADMIN_PASS=admin-secret "$OPENSIM" simulator add demo North --region "Big Garden" --db-admin root >/dev/null 2>&1

	assert_same '{"admin_user":"root","admin_password":"admin-secret"}' "$(jq -c '.data.attributes.setup.simulators[0].database | {admin_user, admin_password}' "$ENGINE_LOG")"
}

function test_makes_a_simulator_with_its_first_region_and_the_database_of_the_environment() {
	engine_says "$FILES"

	OPENSIM_DB_USER=opensim OPENSIM_DB_PASS=secret "$OPENSIM" simulator add demo North --region "Big Garden" --size 512 --owner "Ada Love" >/dev/null 2>&1

	assert_same '{"name":"North","estate":{"owner":"Ada Love"},"database":{"user":"opensim","password":"secret"},"regions":[{"name":"Big Garden","size":512}]}' "$(jq -c '.data.attributes.setup.simulators[0]' "$ENGINE_LOG")"
	assert_same "plan" "$(jq -r '.data.attributes.mode' "$ENGINE_LOG")"
}

REGION='{"data":{"type":"regions","id":"aaaa","attributes":{"name":"Big Garden","roles":["FallbackRegion","Persistent"],"ownerName":"Bob Root"}},"meta":{"reminders":[{"code":"robust-restart-roles","params":{"key":"Region_Big_Garden","restart":"opensim restart demo"},"detail":"Robust reads Region_Big_Garden when it starts: restart Robust (opensim restart demo)."}]}}'
READ_ONLY='{"type":"about:blank","title":"Bad request","status":400,"detail":"the name of a region is the one of its file, changed there by its operator","code":"field-read-only"}'

function test_sets_the_roles_and_the_owner_of_a_region_and_says_what_is_left_to_do() {
	engine_says "$REGION"

	out=$("$OPENSIM" region set demo "Big Garden" --roles FallbackRegion,Persistent --owner 22222222-2222-4222-8222-222222222222 2>&1)

	assert_same '{"data":{"type":"regions","attributes":{"roles":["FallbackRegion","Persistent"],"owner":"22222222-2222-4222-8222-222222222222"}}}' "$(jq -c . "$ENGINE_LOG")"
	assert_contains "Big Garden: FallbackRegion, Persistent; owner Bob Root" "$out"
	assert_contains "Then:" "$out"
	assert_contains "  Robust reads Region_Big_Garden when it starts: restart Robust (opensim restart demo)." "$out"
}

function test_takes_no_roles_to_take_them_all_away_and_says_why_the_engine_refuses() {
	engine_says "$READ_ONLY"

	"$OPENSIM" region set demo Welcome --roles "" >/dev/null 2>&1
	assert_same '{"data":{"type":"regions","attributes":{"roles":[]}}}' "$(jq -c . "$ENGINE_LOG")"
	engine_says "$READ_ONLY"
	out=$("$OPENSIM" region set demo Welcome --roles "" 2>&1) && fail "a refusal ends in an error"
	assert_contains "the name of a region is the one of its file" "$out"
}

function test_set_needs_something_to_set() {
	out=$("$OPENSIM" region set demo Welcome 2>&1) && fail "nothing to set is an error"
	assert_contains "usage" "$out"
}

RESTORE='{"data":{"type":"restores","id":"alpha-20261116-120000.tar.gz","attributes":{"mode":"plan","applied":false,"file":"/srv/backups/alpha/alpha-20261116-120000.tar.gz","grid":"alpha","simulator":null,"made":"2026-11-16T12:00:00+00:00","host":"old.example.org","databases":[{"host":"localhost","name":"alpha_robust","user":"opensim"}],"writes":["/etc/opensim/grids/alpha/Robust.HG.ini","/etc/opensim/robust.d/alpha.ini"],"kept":[],"reminders":[{"code":"restore-start","params":{"instance":"alpha","command":"opensim start alpha"},"detail":"Start alpha once it is restored: opensim start alpha"}]}}}'
CONFLICT='{"type":"about:blank","title":"Invalid request","status":400,"detail":"this machine has already what the backup holds: /etc/opensim/grids/alpha","code":"restore-conflict"}'

function test_plans_a_restore_and_says_nothing_was_written() {
	engine_says "$RESTORE"
	printf 'archive' >"$WORK/alpha.tar.gz"

	out=$("$OPENSIM" restore "$WORK/alpha.tar.gz" 2>&1)

	assert_same "{\"file\":\"$(realpath "$WORK/alpha.tar.gz")\",\"mode\":\"plan\"}" "$(jq -c '.data.attributes' "$ENGINE_LOG")"
	assert_contains "Backup of the grid alpha, made 2026-11-16T12:00:00+00:00 on old.example.org" "$out"
	assert_contains "  alpha_robust @ localhost (user opensim)" "$out"
	assert_contains "Would write:" "$out"
	assert_contains "  /etc/opensim/robust.d/alpha.ini" "$out"
	assert_contains "Nothing was written: add --apply to write it, then:" "$out"
	assert_contains "  Start alpha once it is restored: opensim start alpha" "$out"
}

function test_restores_an_archive_by_its_id_with_apply_and_says_why_the_engine_refuses() {
	engine_says "$CONFLICT"

	out=$("$OPENSIM" restore alpha_backup_alpha-20261116-120000 --apply 2>&1) && fail "a refusal ends in an error"

	assert_same '{"archive":"alpha_backup_alpha-20261116-120000","mode":"apply"}' "$(jq -c '.data.attributes' "$ENGINE_LOG")"
	assert_contains "this machine has already what the backup holds" "$out"
}


function test_accounts_are_sent_from_the_list_of_the_caller_and_the_result_kept_for_them_only() {
	local api="$WORK/opensim-api" list="$WORK/list.csv"
	printf 'first,last\nJohn,Roe\n' >"$list"
	cat >"$api" <<-'API'
	#!/usr/bin/env bash
	cat >"$WORK/request.json"
	mode=$(jq -r '.data.attributes.mode' "$WORK/request.json")
	jq -cn --arg mode "$mode" '{data: {type: "imports", attributes: ({kind: "accounts", grid: "demo", mode: $mode, applied: ($mode == "apply"), errors: ["line 3: name \"Bad\" must be a first and a last name"], counts: {"created": 1}, results: [{first: "John", last: "Roe", email: "", status: (if $mode == "apply" then "created" else "would create" end), detail: "", generated: true, password: "Made1234abcd"}]} + (if $mode == "apply" then {csv: "first,last,email,status,password,detail\nJohn,Roe,,created,Made1234abcd,\n"} else {} end))}}'
	API
	chmod +x "$api"
	export WORK

	local plan
	plan=$(cd "$WORK" && OPENSIM_API="$api" "$OPENSIM" import --accounts "$list" demo 2>&1)
	assert_contains "would create   John Roe" "$plan"
	assert_contains "line 3:" "$plan"
	assert_contains "Nothing was written" "$plan"
	assert_contains "John,Roe" "$(jq -r '.data.attributes.text' "$WORK/request.json")"
	assert_not_contains "Made1234abcd" "$plan"

	local applied
	applied=$(cd "$WORK" && OPENSIM_API="$api" "$OPENSIM" import --accounts "$list" demo --apply --keep-going --result "$WORK/result.csv" 2>&1)
	assert_contains "created        John Roe" "$applied"
	assert_equals "true" "$(jq -r '.data.attributes.keepGoing' "$WORK/request.json")"
	assert_contains "Made1234abcd" "$(cat "$WORK/result.csv")"
	assert_equals "600" "$(stat -c %a "$WORK/result.csv" 2>/dev/null || stat -f %Lp "$WORK/result.csv")"
	assert_not_contains "Made1234abcd" "$applied"
}
