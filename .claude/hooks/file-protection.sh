#!/bin/bash
set -euo pipefail

file_path=$(cat | jq -r '.tool_input.file_path // empty')

case "$file_path" in
  *.env*|*Secrets.swift|*/.git/*|.git/*)
    echo "Blocked: editing protected file: $file_path" >&2
    exit 2
    ;;
  *.pbxproj|*.entitlements|*.xcconfig|*/project.yml|project.yml)
    echo "Blocked: $file_path requires manual edit in Xcode (see ax-dev-execute-plans)" >&2
    exit 2
    ;;
esac

exit 0
