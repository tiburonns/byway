#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
test_home="$(mktemp -d /tmp/byway-core-tests.XXXXXX)"
test_binary="$test_home/byway-core-tests"
trap 'rm -rf "$test_home"' EXIT

xcrun swiftc \
  "$repo_root/Xcode/byway/Domain/VariableKind.swift" \
  "$repo_root/Xcode/byway/Domain/VariableValue.swift" \
  "$repo_root/Xcode/byway/Domain/GlobalVariable.swift" \
  "$repo_root/Xcode/byway/Domain/AdvancedModels.swift" \
  "$repo_root/Xcode/byway/Persistence/StorageLocation.swift" \
  "$repo_root/Xcode/byway/Persistence/BywayArchive.swift" \
  "$repo_root/Xcode/byway/Persistence/VariableRepository.swift" \
  "$repo_root/Tests/AdvancedCoreIntegration.swift" \
  -o "$test_binary"

CFFIXED_USER_HOME="$test_home/home" "$test_binary"
