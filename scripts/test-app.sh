#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
CHECK_ROOT="$TASK_ROOT/.build/checks"
if (( $# > 1 )); then
    echo "Usage: $0 [--ui]" >&2
    exit 2
fi
if (( $# == 1 )) && [[ "$1" != "--ui" ]]; then
    echo "Usage: $0 [--ui]" >&2
    exit 2
fi
mkdir -p "$CHECK_ROOT/module-cache"
cd "$CHECK_ROOT"
# Command Line Tools do not ship XCTest. Compile the same production sources into
# a separate runner, excluding only the application's entry point and delegate.
source_files=("$TASK_ROOT"/Sources/SevenDayTodo/**/*.swift)
source_files=("${(@)source_files:#*/SevenDayTodoApp.swift}")
test_files=("$TASK_ROOT"/Tests/SevenDayTodoTests/*.swift)
swiftc -parse-as-library -swift-version 6 \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$CHECK_ROOT/module-cache" \
    -module-name SevenDayTodoChecks \
    "${source_files[@]}" "${test_files[@]}" \
    -o "$CHECK_ROOT/SevenDayTodoChecks"
"$CHECK_ROOT/SevenDayTodoChecks" "$@"
