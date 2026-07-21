#!/bin/bash
# Build and sign. Plain `swift build` produces ad-hoc signed binaries whose
# identity is the binary hash - every rebuild looks like a new app to the
# Keychain, so "Always Allow" never sticks and key prompts return forever.
# Signing with a real certificate and a stable identifier fixes that: one
# "Always Allow" (with the login password) per Keychain item, then never again.
# Set CODESIGN_IDENTITY to pick a certificate; otherwise the first Apple
# Development identity in the login keychain is used. Without either, binaries
# stay ad-hoc signed: everything works, Keychain prompts just repeat.
set -euo pipefail
cd "$(dirname "$0")"

swift build "$@"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    codesign -f -i com.nhannht.maquette.app -s "$IDENTITY" .build/debug/MaquetteApp
    codesign -f -i com.nhannht.maquette.cli -s "$IDENTITY" .build/debug/maquette-cli
    echo "built and signed: MaquetteApp, maquette-cli"
else
    echo "built with ad-hoc signatures (no codesign identity found)"
fi
