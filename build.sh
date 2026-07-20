#!/bin/bash
# Build and sign. Plain `swift build` produces ad-hoc signed binaries whose
# identity is the binary hash - every rebuild looks like a new app to the
# Keychain, so "Always Allow" never sticks and key prompts return forever.
# Signing with a real certificate and a stable identifier fixes that: one
# "Always Allow" (with the login password) per Keychain item, then never again.
set -euo pipefail
cd "$(dirname "$0")"

swift build "$@"

IDENTITY="Apple Development: nhan nguyen (F57V83ZMHX)"
codesign -f -i com.nhannht.maquette.app -s "$IDENTITY" .build/debug/MaquetteApp
codesign -f -i com.nhannht.maquette.cli -s "$IDENTITY" .build/debug/maquette-cli
echo "built and signed: MaquetteApp, maquette-cli"
