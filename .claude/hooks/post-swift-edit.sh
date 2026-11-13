#!/bin/bash
set -euo pipefail

file_path=$(cat | jq -r '.tool_input.file_path // empty')

[[ "$file_path" == *.swift ]] || exit 0
command -v swiftformat >/dev/null 2>&1 || exit 0

swiftformat "$file_path" >/dev/null 2>&1 || true
exit 0
