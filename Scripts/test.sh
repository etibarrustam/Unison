#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# swift-testing ships with the Command Line Tools but is off the default
# search path. The flags must be global (not per-target) so the derived
# test runner compiles with canImport(Testing) == true; otherwise the run
# silently executes zero tests.
FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" \
  "$@"
