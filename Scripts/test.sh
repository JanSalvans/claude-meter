#!/bin/bash
# Passa les proves amb swift-testing.
# Amb Command Line Tools (sense Xcode), SwiftPM no troba sol ni Testing.framework
# ni lib_TestingInterop.dylib: cal indicar-li els dos camins i els dos rpath.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLT="$(xcode-select -p)"
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
LIBS="$CLT/Library/Developer/usr/lib"

if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
  echo "No hi ha Testing.framework a $FRAMEWORKS." >&2
  exit 1
fi

cd "$ROOT"
exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$LIBS" \
  "$@"
