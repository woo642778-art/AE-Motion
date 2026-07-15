#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: This bootstrap script must run on macOS." >&2
  exit 1
fi

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "error: Install Xcode in /Applications before running this script." >&2
  exit 1
fi

sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

if ! command -v brew >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Homebrew is required for the small command-line tool set.
Install Homebrew from https://brew.sh, then rerun:
  bash scripts/bootstrap-macos.sh
EOF
  exit 2
fi

brew bundle --file "$ROOT_DIR/Brewfile"

bash "$ROOT_DIR/scripts/generate-test-host.sh"
bash "$ROOT_DIR/scripts/doctor-macos.sh"

cat <<'EOF'

Bootstrap complete.
Open the generated project with:
  open TestHost/AEMotionTestHost.xcodeproj

Run all local checks with:
  make verify
EOF
