#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d /private/tmp/scapare-tests.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
sources=()
for source in Scapare/*.swift; do
  if [[ "$source" != "Scapare/ScapareApp.swift" ]]; then sources+=("$source"); fi
done
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -target "$(uname -m)-apple-macos14.0" -module-cache-path /private/tmp/scapare-regression-module-cache \
  "${sources[@]}" Tests/RegressionTests.swift -o "$output_dir/RegressionTests"
"$output_dir/RegressionTests"
