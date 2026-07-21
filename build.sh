#!/bin/bash
# Build and sign. Plain `swift build` produces ad-hoc signed binaries whose
# identity is the binary hash - every rebuild looks like a new app to the
# Keychain, so "Always Allow" never sticks and key prompts return forever.
# Signing with a real certificate and a stable identifier fixes that: one
# "Always Allow" (with the login password) per Keychain item, then never again.
# Set CODESIGN_IDENTITY to pick a certificate; otherwise the first Apple
# Development identity in the login keychain is used. Without either, binaries
# stay ad-hoc signed: everything works, Keychain prompts just repeat.
#
# `./build.sh app` additionally wraps the (debug) binary in Maquette.app -
# Info.plist, the MaquetteKit resource bundle, and the Icon Composer icon
# compiled by actool - and installs it to /Applications so LaunchServices
# registers it: Dock name + icon and Spotlight indexing only exist for .app
# bundles, never for a bare executable.
#
# `./build.sh release` builds an arm64 release bundle (SubjectLift depends
# on Swift Float16, which does not exist on x86_64 - Intel support would need
# a vImage half-float conversion there), signs it with the Developer ID
# Application certificate + hardened runtime,
# notarizes and staples the app (via zip) BEFORE packing it into
# .build/dist/Maquette-<version>.dmg, then notarizes and staples the DMG too.
# Needs a notarytool keychain profile (default name maquette-notary, override
# with NOTARY_PROFILE); create it once with `xcrun notarytool store-credentials`
# (Apple ID + app-specific password).
set -euo pipefail
cd "$(dirname "$0")"

MODE=build
case "${1:-}" in app|release) MODE=$1; shift ;; esac

if [ "$MODE" = release ]; then
    swift build -c release "$@"
    BINDIR=$(swift build -c release --show-bin-path)
else
    swift build "$@"
    BINDIR=.build/debug
fi

# Assemble an app bundle from the binaries in $2. Bundle.module resolves the
# SwiftPM resource bundle via Contents/Resources, which keeps the offline
# three.js renderer working inside the .app. actool compiles the Icon
# Composer project into Assets.car (layered dark/tinted variants) plus a
# legacy AppIcon.icns in one pass; it keys the icon name off the input file
# name, hence the AppIcon.icon staging copy. CFBundleIdentifier matches the
# bare binary's codesign identifier so the Keychain "Always Allow" ACL
# carries over between launch styles.
make_app() {
    local APP=$1 FROM=$2
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$FROM/MaquetteApp" "$APP/Contents/MacOS/MaquetteApp"
    cp -R "$FROM/maquette_MaquetteKit.bundle" "$APP/Contents/Resources/"
    local ICONTMP
    ICONTMP=$(mktemp -d)
    cp -R design/icon-composer.icon "$ICONTMP/AppIcon.icon"
    xcrun actool "$ICONTMP/AppIcon.icon" --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 \
        --app-icon AppIcon --output-partial-info-plist "$ICONTMP/partial.plist" \
        > /dev/null
    rm -rf "$ICONTMP"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>MaquetteApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.nhannht.maquette.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Maquette</string>
	<key>CFBundleDisplayName</key>
	<string>Maquette</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.graphics-design</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
}

# Submit for notarization under caffeinate (idle sleep kills uploads) and
# WITHOUT --wait: notarytool prints the submission id before the upload
# finishes, so a dead upload leaves a phantom id that never resolves. The id
# is only trustworthy once it appears in `history` (= Apple has the bytes);
# then poll `info` for the verdict. "does not exist" is a dead id - resubmit,
# never wait on it.
notarize_file() {
    local FILE=$1 OUT ID I
    OUT=$(caffeinate -i xcrun notarytool submit "$FILE" \
        --keychain-profile "$PROFILE" 2>&1) || { echo "$OUT"; return 1; }
    ID=$(echo "$OUT" | awk '/^  id: /{print $2; exit}')
    if [ -z "$ID" ]; then
        echo "$OUT"
        echo "no submission id in notarytool output"
        return 1
    fi
    sleep 3
    if ! xcrun notarytool history --keychain-profile "$PROFILE" 2>/dev/null \
            | grep -q "$ID"; then
        echo "submission $ID never registered in history - the upload died; rerun"
        return 1
    fi
    for I in $(seq 1 160); do
        OUT=$(xcrun notarytool info "$ID" --keychain-profile "$PROFILE" 2>&1) || true
        case "$OUT" in
            *"status: Accepted"*)
                echo "notarized: $FILE ($ID)"
                return 0 ;;
            *"status: Invalid"*|*"status: Rejected"*)
                xcrun notarytool log "$ID" --keychain-profile "$PROFILE"
                return 1 ;;
            *"does not exist"*)
                echo "submission $ID vanished (upload swept) - rerun"
                return 1 ;;
            *"No Keychain password item"*)
                echo "login keychain relocked - run: security unlock-keychain" \
                     "~/Library/Keychains/login.keychain-db"
                return 1 ;;
            *) sleep 15 ;;  # In Progress or a transient poll error
        esac
    done
    echo "no verdict for $ID after 40 min - check developer.apple.com/system-status"
    return 1
}

if [ "$MODE" = release ]; then
    DEVID="${DEVELOPER_ID_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
    if [ -z "$DEVID" ]; then
        echo "release needs a Developer ID Application certificate (none found)"
        exit 1
    fi
    PROFILE="${NOTARY_PROFILE:-maquette-notary}"
    if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
        echo "notary profile '$PROFILE' not found - create it once with:"
        echo "  xcrun notarytool store-credentials $PROFILE --apple-id <apple-account-email> --team-id <team-id>"
        echo "then rerun: ./build.sh release"
        exit 1
    fi
    DIST=.build/dist
    mkdir -p "$DIST"
    make_app "$DIST/Maquette.app" "$BINDIR"
    codesign -f --options runtime --timestamp -s "$DEVID" "$DIST/Maquette.app"

    # Notarize + staple the app BEFORE the DMG is built: the DMG is immutable,
    # so an app stapled afterwards would ship ticketless and fail offline
    # Gatekeeper checks. The zip is upload packaging only; the ticket staples
    # to the .app itself.
    ZIP="$DIST/Maquette.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$DIST/Maquette.app" "$ZIP"
    notarize_file "$ZIP"
    rm -f "$ZIP"
    xcrun stapler staple "$DIST/Maquette.app"
    xcrun stapler validate "$DIST/Maquette.app"
    spctl -a -vv "$DIST/Maquette.app"

    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
        "$DIST/Maquette.app/Contents/Info.plist")
    DMG="$DIST/Maquette-$VERSION.dmg"
    STAGE="$DIST/stage"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$DIST/Maquette.app" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname Maquette -srcfolder "$STAGE" -ov -format UDZO \
        "$DMG" > /dev/null
    rm -rf "$STAGE"
    codesign -f --timestamp -s "$DEVID" "$DMG"
    notarize_file "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "notarized and stapled: $DMG"
    exit 0
fi

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    codesign -f -i com.nhannht.maquette.app -s "$IDENTITY" .build/debug/MaquetteApp
    codesign -f -i com.nhannht.maquette.cli -s "$IDENTITY" .build/debug/maquette-cli
    echo "built and signed: MaquetteApp, maquette-cli"
else
    echo "built with ad-hoc signatures (no codesign identity found)"
fi

[ "$MODE" = app ] || exit 0

APP=.build/Maquette.app
make_app "$APP" .build/debug
if [ -n "$IDENTITY" ]; then
    codesign -f -s "$IDENTITY" "$APP"
else
    codesign -f -s - "$APP"
fi

DEST=/Applications
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
rm -rf "$DEST/Maquette.app"
cp -R "$APP" "$DEST/Maquette.app"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$DEST/Maquette.app"
echo "installed: $DEST/Maquette.app"
