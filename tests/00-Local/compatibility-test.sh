#!/usr/bin/env bash
# What the code of the command line may use: what every platform it runs on has (no brace glob: musl, Alpine and lerd lack it).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function test_the_php_code_has_no_brace_glob_flag() {
	local needle="GLOB_""BRACE" files found
	# The code of the project, not what it brings (vendor, lib) nor what it makes (build, dist)
	files=$(find "$ROOT" \( -name vendor -o -name lib -o -name build -o -name dist -o -name .git -o -name tmp \) -prune -o -type f -name "*.php" -print)
	assert_not_empty "$files"
	found=$(grep -l "$needle" $files 2>/dev/null || true)
	assert_empty "$found"
}
