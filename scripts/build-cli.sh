#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:-/private/tmp/scapare-cli/scapare}
mkdir -p "$(dirname "$output")"
xcrun swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path /private/tmp/scapare-cli-module-cache \
  Scapare/AutomationProtocol.swift Tools/scapare.swift -o "$output"
printf 'CLI built: %s\n' "$output"
