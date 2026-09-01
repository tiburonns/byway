#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
test_home="$(mktemp -d /tmp/byway-intent-tests.XXXXXX)"
test_binary="$test_home/byway-intent-tests"
trap 'rm -rf "$test_home"' EXIT

xcrun swiftc \
  "$repo_root/Xcode/byway/Domain/VariableKind.swift" \
  "$repo_root/Xcode/byway/Domain/VariableValue.swift" \
  "$repo_root/Xcode/byway/Domain/GlobalVariable.swift" \
  "$repo_root/Xcode/byway/Domain/AdvancedModels.swift" \
  "$repo_root/Xcode/byway/Persistence/StorageLocation.swift" \
  "$repo_root/Xcode/byway/Persistence/BywayArchive.swift" \
  "$repo_root/Xcode/byway/Persistence/VariableRepository.swift" \
  "$repo_root/Xcode/byway/Intents/IntentSupport.swift" \
  "$repo_root/Xcode/byway/Intents/VariableEntity.swift" \
  "$repo_root/Xcode/byway/Intents/AdvancedIntentEntities.swift" \
  "$repo_root/Xcode/byway/Intents/AdvancedVariableIntents.swift" \
  "$repo_root/Tests/AdvancedIntentIntegration.swift" \
  -o "$test_binary"

CFFIXED_USER_HOME="$test_home/home" "$test_binary"
