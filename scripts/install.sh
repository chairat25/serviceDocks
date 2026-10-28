#!/bin/bash
# Installs the latest ServiceDock release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/chairat25/serviceDocks/main/scripts/install.sh | bash
#
# Downloads the release zip, checks its SHA-256, copies the app to /Applications, removes the
# quarantine flag (the app is ad-hoc signed, not notarized) and opens it. If macOS still blocks it,
# offers to open System Settings → Privacy & Security, where "Open Anyway" allows it.
set -euo pipefail

REPO="chairat25/serviceDocks"
APP_NAME="ServiceDock"
DEST="/Applications/$APP_NAME.app"
SETTINGS_URL="x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# Reads y/n from the terminal even when the script itself is piped from curl.
ask() {
    local answer=""
    if [[ -r /dev/tty ]]; then
        read -r -p "$1 [Y/n] " answer < /dev/tty || answer=""
    fi
    [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

[[ "$(uname -s)" == "Darwin" ]] || fail "ServiceDock runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 15 )) || fail "ServiceDock needs macOS 15 or later (this Mac has $(sw_vers -productVersion))."

info "Looking up the latest release…"
release_json="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" || fail "Could not reach GitHub."
zip_url="$(printf '%s' "$release_json" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
sha_url="$(printf '%s' "$release_json" | grep -o '"browser_download_url": *"[^"]*\.sha256"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[[ -n "$zip_url" ]] || fail "No .zip found in the latest release."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
zip_name="$(basename "$zip_url")"

info "Downloading $zip_name…"
curl -fsSL "$zip_url" -o "$work/$zip_name" || fail "Download failed."

if [[ -n "$sha_url" ]]; then
    curl -fsSL "$sha_url" -o "$work/checksums.sha256" || fail "Could not download checksums."
    expected="$(grep " $zip_name\$" "$work/checksums.sha256" | awk '{print $1}')"
    actual="$(shasum -a 256 "$work/$zip_name" | awk '{print $1}')"
    [[ -n "$expected" && "$expected" == "$actual" ]] || fail "Checksum mismatch for $zip_name — not installing."
    info "Checksum OK."
fi

ditto -x -k "$work/$zip_name" "$work/unpacked"
[[ -d "$work/unpacked/$APP_NAME.app" ]] || fail "$APP_NAME.app not found in the download."

if pgrep -x "$APP_NAME" > /dev/null; then
    ask "$APP_NAME is running. Quit it now? (this stops the services it runs)" || fail "Cancelled — quit $APP_NAME and run again."
    osascript -e "quit app \"$APP_NAME\"" || true
    for _ in $(seq 1 20); do pgrep -x "$APP_NAME" > /dev/null || break; sleep 0.5; done
fi

if [[ -d "$DEST" ]]; then
    ask "Replace the existing $DEST?" || fail "Cancelled."
fi

info "Installing to $DEST…"
if [[ -w /Applications ]]; then
    rm -rf "$DEST" && ditto "$work/unpacked/$APP_NAME.app" "$DEST"
else
    sudo rm -rf "$DEST" && sudo ditto "$work/unpacked/$APP_NAME.app" "$DEST"
fi

info "Removing the quarantine flag…"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || sudo xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

info "Opening $APP_NAME…"
open "$DEST" || true
sleep 3

if pgrep -x "$APP_NAME" > /dev/null; then
    info "Done — $APP_NAME is in the menu bar."
    exit 0
fi

echo
echo "macOS blocked $APP_NAME (it is not notarized by Apple)."
echo "To allow it: System Settings → Privacy & Security → scroll down → \"Open Anyway\" next to $APP_NAME."
if ask "Open Privacy & Security now?"; then
    open "$SETTINGS_URL"
    echo "After clicking \"Open Anyway\", open $APP_NAME from Applications."
fi
