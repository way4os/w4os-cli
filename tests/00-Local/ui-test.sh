#!/usr/bin/env bash
# The questions in dialog, with a stand-in for dialog that behaves as dialog 1.3 does with the text above a form, a checklist or a menu:
# an empty one is refused at once (status 255), so a screen of the engine without a text could never be answered.
#
# Run with: composer test

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up() {
	WORK="$(mktemp -d)"
	mkdir -p "$WORK/bin"
	cat >"$WORK/bin/dialog" <<-'DIALOG'
		#!/usr/bin/env bash
		# dialog as far as the tests need it: the text after the kind of box must not be empty; a form answers the values it was given
		args=("$@") fd= kind= text= start=
		for ((i = 0; i < ${#args[@]}; i++)); do
			case ${args[i]} in
			--output-fd) fd=${args[i + 1]} ;;
			--mixedform | --checklist | --menu | --inputbox) kind=${args[i]} text=${args[i + 1]} start=$((i + 2)) ;;
			esac
		done
		printf '%s\n' "$kind" >>"$DIALOG_LOG"
		printf '%s ' "$@" >"${DIALOG_LOG%/*}/args"
		[[ -n $text ]] || exit 255
		# The answers of a person, one call a line: the status and what is chosen or typed
		if [[ -s ${DIALOG_SCRIPT:-} ]]; then
			read -r code answer <"$DIALOG_SCRIPT"
			tail -n +2 "$DIALOG_SCRIPT" >"$DIALOG_SCRIPT.next" && mv "$DIALOG_SCRIPT.next" "$DIALOG_SCRIPT"
			printf '%s' "$answer" >&"$fd"
			exit "$code"
		fi
		if [[ $kind == --mixedform ]]; then
			for ((k = 0; k < ${args[start + 2]}; k++)); do
				printf '%s\n' "${args[start + 3 + k * 9 + 3]}" >&"$fd"
			done
		fi
		exit "${DIALOG_EXIT:-0}"
	DIALOG
	chmod +x "$WORK/bin/dialog"
	: >"$WORK/dialogrc"
	export PATH="$WORK/bin:$PATH" DIALOG_LOG="$WORK/dialog.log" OPENSIM_SETUP_UI=dialog FE_SCREEN=/dev/null FE_DIALOGRC="$WORK/dialogrc"
	# shellcheck source=/dev/null
	source "$ROOT/src/lib/ui"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_a_form_without_a_text_is_answered() {
	declare -gA LABEL=([f_name]="Region name" [f_port]="Region UDP port") SECRET=() READONLY=()
	f_name=Welcome f_port=9000
	local status=0

	ui_form "Simulator (join other grid)" "" f_name f_port || status=$?

	assert_same "0" "$status"
	assert_same "Welcome 9000" "$f_name $f_port"
	assert_same "--mixedform" "$(cat "$DIALOG_LOG")"
	assert_contains "--hline Enter: next field, Tab: buttons" "$(cat "$WORK/args")"
}

function test_a_form_with_choices_lists_the_fields_with_their_help_and_asks_the_choice_in_a_menu() {
	declare -gA LABEL=([f_register]="Register the regions" [f_events]="Events") SECRET=() READONLY=() \
		OPTIONS=([f_register]=$'both\x1fHelpers and 2do.directory\nhelpers\x1fHelpers only') HELP=([f_events]="A HYPEvents calendar")
	f_register=both f_events=https://2do.directory/events
	# The register changed to the helpers only, the events typed, then OK
	export DIALOG_SCRIPT="$WORK/script"
	printf '%s\n' "0 1" "0 helpers" "0 2" "0 https://events.example.org" "3" >"$DIALOG_SCRIPT"
	local status=0

	ui_form "Web services" "" f_register f_events || status=$?

	assert_same "0" "$status"
	assert_same "helpers https://events.example.org" "$f_register $f_events"
	assert_same $'--menu\n--menu\n--menu\n--inputbox\n--menu' "$(cat "$DIALOG_LOG")"
	assert_contains "--item-help" "$(cat "$WORK/args")"
	assert_contains "A HYPEvents calendar" "$(cat "$WORK/args")"
	assert_contains "Helpers only" "$(cat "$WORK/args")"
}

function test_a_form_with_choices_in_plain_text_shows_the_help_and_the_label_of_the_choice() {
	declare -gA LABEL=([f_search]="In-world search") SECRET=() READONLY=() \
		OPTIONS=([f_search]=$'internal\x1fHelpers\nshared\x1f2do.directory') HELP=([f_search]="2do.directory searches every destination")
	f_search=internal
	exec 7< <(printf '%s\n' 1 2 '')
	OPENSIM_SETUP_UI=plain FE_INPUT_FD=7 FE_UI=
	local status=0

	ui_form "Web services" "" f_search 2>"$WORK/out" || status=$?
	exec 7<&-

	assert_same "0" "$status"
	assert_same "shared" "$f_search"
	assert_contains "In-world search            Helpers" "$(cat "$WORK/out")"
	assert_contains "2do.directory searches every destination" "$(cat "$WORK/out")"
	assert_contains "2) 2do.directory" "$(cat "$WORK/out")"
}

function test_a_screen_of_the_engine_gives_the_key_of_the_choice() {
	local screen answers button state
	screen='{"kind":"form","title":"Web services","text":"","notice":"","state":"s","fields":[
		{"name":"web_search","label":"Web search","value":"internal","secret":false,"readonly":false,
		 "options":{"internal":"Helpers","shared":"2do.directory"},"help":"2do.directory searches every destination"}]}'
	exec 7< <(printf '%s\n' 1 2 '')
	OPENSIM_SETUP_UI=plain FE_INPUT_FD=7 FE_UI=

	ui_screen "$screen" 2>/dev/null
	exec 7<&-

	assert_same "next" "$button"
	assert_same '{"web_search":"shared"}' "$answers"
}

function test_check_boxes_without_a_text_are_answered() {
	declare -gA LABEL=([c_hypergrid]="Hypergrid")
	c_hypergrid=yes
	local status=0

	ui_checks "Options" "" c_hypergrid || status=$?

	assert_same "0" "$status"
	assert_same "--checklist" "$(cat "$DIALOG_LOG")"
}

function test_a_menu_without_a_text_is_answered() {
	local choice= status=0

	ui_menu choice "OpenSim setup" "" grid grid "Grid" standalone "Standalone" || status=$?

	assert_same "0" "$status"
	assert_same "--menu" "$(cat "$DIALOG_LOG")"
}

function test_a_review_with_a_button_of_its_own_says_when_it_is_pressed() {
	FE_EXTRA="Show passwords"
	export DIALOG_EXIT=3

	local status=0
	ui_review "Review" "" $'database\x1fDatabase account\x1fopensim@localhost: ********' || status=$?

	assert_same 3 "$status"
	assert_contains "--extra-button --extra-label Show passwords" "$(cat "$WORK/args")"
}

function test_a_review_in_plain_text_shows_the_passwords_when_s_is_answered() {
	exec 7<<<"s"
	FE_EXTRA="Show passwords" OPENSIM_SETUP_UI=plain FE_INPUT_FD=7 FE_UI=

	local status=0
	ui_review "Review" "" $'database\x1fDatabase account\x1fopensim@localhost: ********' 2>/dev/null || status=$?
	exec 7<&-

	assert_same 3 "$status"
}
