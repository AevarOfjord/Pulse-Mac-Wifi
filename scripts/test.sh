#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
toolchain_bin="$(dirname "$(xcrun --find swiftc)")"
plugin="$toolchain_bin/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
extra=()
if [[ -f "$plugin" ]]; then extra=(-Xswiftc -load-plugin-library -Xswiftc "$plugin"); fi
swift test --disable-xctest --disable-sandbox --cache-path "$PWD/.build/cache" "${extra[@]}"
