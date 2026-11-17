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
			--mixedform | --checklist | --menu) kind=${args[i]} text=${args[i + 1]} start=$((i + 2)) ;;
			esac
		done
		printf '%s\n' "$kind" >>"$DIALOG_LOG"
		printf '%s ' "$@" >"${DIALOG_LOG%/*}/args"
		[[ -n $text ]] || exit 255
		if [[ $kind == --mixedform ]]; then
			for ((k = 0; k < ${args[start + 2]}; k++)); do
				printf '%s\n' "${args[start + 3 + k * 9 + 3]}" >&"$fd"
			done
		fi
		exit 0
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
