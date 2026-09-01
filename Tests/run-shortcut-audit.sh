#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
audit_dir=$(mktemp -d /tmp/byway-shortcut-audit.XXXXXX)
trap 'rm -rf "$audit_dir"' EXIT HUP INT TERM

mkdir -p "$audit_dir/es" "$audit_dir/en"
swift "$repo_dir/Tools/GenerateWorkflowShortcuts.swift" "$audit_dir/es"
swift "$repo_dir/Tools/LocalizeWorkflowShortcuts.swift" "$audit_dir/es" "$audit_dir/en"
swift "$repo_dir/Tests/AuditWorkflowShortcuts.swift" "$audit_dir/es" "$audit_dir/en"
