#!/bin/bash
set -euo pipefail
umask 077
if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo 'Usage: bash Scripts/install.sh "Developer ID Application: Name (TEAMID)"'
  exit 64
fi
identity="$1"
[[ "$identity" == "Developer ID Application: "* ]] || { echo 'A stable Developer ID identity is required.' >&2; exit 64; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
destination="$HOME/Applications/AXTestTools/AXRunner.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$root"
swift test
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
stage="$(mktemp -d "$root/.build/package.XXXXXX")"
app="$stage/AXRunner.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/AXRunner" "$app/Contents/MacOS/AXRunner"
cp "$root/Assets/Info.plist" "$app/Contents/Info.plist"
/usr/bin/codesign --force --options runtime --sign "$identity" "$app"
/usr/bin/codesign --verify --strict "$app"
if [[ -L "$destination" ]]; then echo 'Refusing symlink install target.' >&2; exit 64; fi
if [[ -e "$destination" ]]; then
  /usr/bin/codesign --verify --strict "$destination"
  old_requirement="$(/usr/bin/codesign -d -r- "$destination" 2>&1 | /usr/bin/sed -n '/^designated => /p')"
  new_requirement="$(/usr/bin/codesign -d -r- "$app" 2>&1 | /usr/bin/sed -n '/^designated => /p')"
  [[ -n "$old_requirement" && "$old_requirement" == "$new_requirement" ]] || { echo 'Signing identity changed; refusing replacement.' >&2; exit 65; }
  if /usr/bin/pgrep -f "$destination/Contents/MacOS/AXRunner" >/dev/null; then
    echo 'AXRunner is running; wait for completion before installing.' >&2; exit 75
  fi
fi
mkdir -p "$(dirname "$destination")"
/usr/bin/ditto "$app" "$destination"
/usr/bin/codesign --verify --strict "$destination"
/usr/bin/codesign -d -r- "$destination"
echo "Installed: $destination"
echo 'Accessibility permission remains user-controlled. No TCC settings were changed.'
